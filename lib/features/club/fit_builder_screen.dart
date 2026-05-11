import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/primary_button.dart';
import 'providers/cart_provider.dart';

/// FIT meal builder. Loads template + linked categories + options, renders
/// single/multi selectors per category, and shows a sticky total bar.
///
/// Pricing is server-authoritative — fit_meal_compute_price is called on
/// every selection change to refresh the total. On "Add to cart" we call
/// fit_meal_order_create which inserts a fit_meal_orders row with
/// status='in_cart'.
///
/// TODO(cart-integration): Module 2.5 keeps fit_meal_orders as a parallel
/// track to the existing menu_items cart. A follow-up commit will surface
/// in-cart FIT orders alongside menu_items in the unified cart sheet.
class FitBuilderScreen extends ConsumerStatefulWidget {
  final String templateId;
  const FitBuilderScreen({super.key, required this.templateId});

  @override
  ConsumerState<FitBuilderScreen> createState() => _FitBuilderScreenState();
}

class _FitBuilderScreenState extends ConsumerState<FitBuilderScreen> {
  // selections[category_id] = option_id (single) | List<option_id> (multi)
  final Map<String, dynamic> _selections = {};
  int? _basePrice;
  int _upcharge = 0;
  bool _busy = false;
  String? _errorText;

  Future<void> _refreshPrice(BuildContext context) async {
    try {
      final res = await Supabase.instance.client
          .rpc<Map<String, dynamic>>(
        'fit_meal_compute_price',
        params: {
          'p_template_id': widget.templateId,
          'p_selections': _selections,
        },
      );
      if (!mounted) return;
      setState(() {
        _basePrice = res['base_price_paise'] as int?;
        _upcharge = (res['total_upcharge_paise'] as int?) ?? 0;
        _errorText = null;
      });
    } on PostgrestException catch (e) {
      // Soft-error: shape failures (missing required) shouldn't kill the UI;
      // only show if the error is something other than category_required.
      if (e.message.contains('category_required')) return;
      if (!mounted) return;
      setState(() => _errorText = e.message);
    } catch (_) {
      // Network blip — ignore.
    }
  }

  Future<void> _addToCart(_BuilderData data, int finalPrice) async {
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      // Server-authoritative price re-validation. Throws on bad selections.
      final priced = await Supabase.instance.client
          .rpc<Map<String, dynamic>>(
        'fit_meal_compute_price',
        params: {
          'p_template_id': widget.templateId,
          'p_selections': _selections,
        },
      );
      final unit = (priced['final_price_paise'] as int?) ?? finalPrice;

      // Build human-readable summary of selections for the cart card.
      final summary = <String>[];
      for (final lc in data.linkedCategories) {
        final catId = lc.category['id'] as String;
        final sel = _selections[catId];
        if (sel == null) continue;
        if (sel is String) {
          final opt = lc.options.firstWhere(
            (o) => o['id'] == sel, orElse: () => const {},
          );
          if (opt.isNotEmpty) summary.add(opt['name'] as String? ?? '');
        } else if (sel is List) {
          for (final id in sel) {
            final opt = lc.options.firstWhere(
              (o) => o['id'] == id, orElse: () => const {},
            );
            if (opt.isNotEmpty) summary.add(opt['name'] as String? ?? '');
          }
        }
      }

      ref.read(cartProvider.notifier).addFitMeal(
            FitMealLine.create(
              templateId: widget.templateId,
              templateName: (data.template['name'] as String?) ?? 'FIT meal',
              unitPricePaise: unit,
              quantity: 1,
              selectionsJsonb: Map<String, dynamic>.from(_selections),
              selectionsSummary: summary,
              imageUrl: data.template['photo_url'] as String?,
            ),
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.activeGreen,
          content: Text('Added to cart · ${Money.fromPaise(unit)}'),
        ),
      );
      context.pop();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = _mapError(e.message);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = 'Could not add to cart: $e';
      });
    }
  }

  String _mapError(String raw) {
    if (raw.contains('category_required:')) {
      final slug = raw.split('category_required:').last.trim();
      return 'Please pick an option for: $slug';
    }
    if (raw.contains('option_unavailable:')) {
      return 'One of your selected options is sold out. Try another.';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final tpl = ref.watch(fitTemplateDetailProvider(widget.templateId));
    return tpl.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (data) => _buildLoaded(context, data),
    );
  }

  Widget _buildLoaded(BuildContext context, _BuilderData data) {
    final tpl = data.template;
    _basePrice ??= tpl['base_price_paise'] as int?;
    final final_ = (_basePrice ?? 0) + _upcharge;

    // Required-category gating for the CTA.
    final allRequiredFilled = data.linkedCategories.every((lc) {
      final isReq = (lc.linker['is_required'] as bool?) ?? true;
      if (!isReq) return true;
      final sel = _selections[lc.category['id']];
      if (sel == null) return false;
      if (sel is List && sel.isEmpty) return false;
      return true;
    });

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: Text((tpl['name'] as String?) ?? 'Build your meal'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          if ((tpl['photo_url'] as String?)?.isNotEmpty ?? false)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                tpl['photo_url'] as String,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.fitGreen.withValues(alpha: 0.15),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((tpl['description'] as String?)?.isNotEmpty ?? false)
                  Text(
                    tpl['description'] as String,
                    style: AppTextStyles.body(context),
                  ),
                const SizedBox(height: 16),
                for (final lc in data.linkedCategories)
                  _CategorySection(
                    category: lc.category,
                    linker: lc.linker,
                    options: lc.options,
                    selection: _selections[lc.category['id']],
                    onSelectionChange: (sel) {
                      final catId = lc.category['id'] as String;
                      setState(() {
                        if (sel == null ||
                            (sel is List && sel.isEmpty)) {
                          _selections.remove(catId);
                        } else {
                          _selections[catId] = sel;
                        }
                      });
                      _refreshPrice(context);
                    },
                  ),
                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorText!,
                    style: AppTextStyles.caption(
                      context, color: AppColors.adminRed,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomSheet: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: const BoxDecoration(
            color: AppColors.lightSurface,
            border: Border(top: BorderSide(color: AppColors.lightBorder)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total',
                      style: AppTextStyles.caption(
                        context, color: AppColors.lightTextSecondary,
                      ),
                    ),
                    Text(
                      Money.fromPaise(final_),
                      style: AppTextStyles.h2(
                        context, color: AppColors.fitGreen,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 200,
                child: PrimaryButton(
                  label: 'Add to cart',
                  loading: _busy,
                  onPressed: allRequiredFilled && !_busy
                      ? () => _addToCart(data, final_)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final Map<String, dynamic> category;
  final Map<String, dynamic> linker;
  final List<Map<String, dynamic>> options;
  final dynamic selection;
  final ValueChanged<dynamic> onSelectionChange;
  const _CategorySection({
    required this.category,
    required this.linker,
    required this.options,
    required this.selection,
    required this.onSelectionChange,
  });

  @override
  Widget build(BuildContext context) {
    final name = (category['name'] as String?) ?? '—';
    final required = (linker['is_required'] as bool?) ?? true;
    final selType = (linker['selection_type_override'] as String?)
        ?? (category['selection_type'] as String?) ?? 'single';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(name, style: AppTextStyles.h3(context)),
              const SizedBox(width: 8),
              if (required)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.adminRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Required',
                    style: AppTextStyles.caption(
                      context, color: AppColors.adminRed,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.lightTextSecondary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Optional',
                    style: AppTextStyles.caption(
                      context, color: AppColors.lightTextSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (selType == 'single')
            _SingleSelect(
              options: options,
              selected: selection as String?,
              onChange: onSelectionChange,
            )
          else
            _MultiSelect(
              options: options,
              selected: (selection as List<dynamic>?)?.cast<String>() ?? const [],
              onChange: onSelectionChange,
            ),
        ],
      ),
    );
  }
}

class _SingleSelect extends StatelessWidget {
  final List<Map<String, dynamic>> options;
  final String? selected;
  final ValueChanged<dynamic> onChange;
  const _SingleSelect({
    required this.options,
    required this.selected,
    required this.onChange,
  });
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(_label(o)),
            selected: selected == o['id'],
            onSelected: (v) => onChange(v ? o['id'] : null),
          ),
      ],
    );
  }

  String _label(Map<String, dynamic> o) {
    final name = (o['name'] as String?) ?? '';
    final up = (o['upcharge_paise'] as int?) ?? 0;
    if (up <= 0) return name;
    return '$name  +${Money.fromPaise(up)}';
  }
}

class _MultiSelect extends StatelessWidget {
  final List<Map<String, dynamic>> options;
  final List<String> selected;
  final ValueChanged<dynamic> onChange;
  const _MultiSelect({
    required this.options,
    required this.selected,
    required this.onChange,
  });
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          FilterChip(
            label: Text(_label(o)),
            selected: selected.contains(o['id']),
            onSelected: (v) {
              final next = [...selected];
              if (v) {
                next.add(o['id'] as String);
              } else {
                next.remove(o['id']);
              }
              onChange(next);
            },
          ),
      ],
    );
  }

  String _label(Map<String, dynamic> o) {
    final name = (o['name'] as String?) ?? '';
    final up = (o['upcharge_paise'] as int?) ?? 0;
    if (up <= 0) return name;
    return '$name  +${Money.fromPaise(up)}';
  }
}

class _LinkedCategory {
  final Map<String, dynamic> category;
  final Map<String, dynamic> linker;
  final List<Map<String, dynamic>> options;
  const _LinkedCategory({
    required this.category,
    required this.linker,
    required this.options,
  });
}

class _BuilderData {
  final Map<String, dynamic> template;
  final List<_LinkedCategory> linkedCategories;
  const _BuilderData({
    required this.template,
    required this.linkedCategories,
  });
}

/// Loads template + linker rows + categories + options for each linked
/// category, in display_order. RLS already filters out unpublished /
/// unavailable templates and options.
final fitTemplateDetailProvider =
    FutureProvider.autoDispose.family<_BuilderData, String>(
  (ref, templateId) async {
    // Switched from 4 chained PostgREST queries to a single SECURITY
    // DEFINER RPC (fit_template_detail). The chained version returned
    // empty sections for the customer despite RLS appearing correct —
    // the SECURITY DEFINER bypass guarantees a clean read.
    final raw = await Supabase.instance.client
        .rpc<Map<String, dynamic>>('fit_template_detail', params: {
      'p_template_id': templateId,
    });

    final tpl = Map<String, dynamic>.from(
      (raw['template'] as Map?) ?? const <String, dynamic>{},
    );

    final sections = ((raw['sections'] as List?) ?? const [])
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();

    final List<_LinkedCategory> linked = [];
    for (final s in sections) {
      final cat = (s['category'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      if (cat.isEmpty) continue;
      final linker = (s['linker'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final opts = ((s['options'] as List?) ?? const [])
          .map((o) => Map<String, dynamic>.from(o as Map))
          .toList();
      linked.add(_LinkedCategory(
        category: cat,
        linker: linker,
        options: opts,
      ));
    }

    return _BuilderData(
      template: tpl,
      linkedCategories: linked,
    );
  },
);
