import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers/active_sessions_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/family_children_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/venues.dart';
import '../../core/widgets/error_screen.dart';
import '../../core/widgets/primary_button.dart';
import 'providers/cart_provider.dart';

const _venueId = Venues.kondapurId;

/// Combo context passed to [FitBuilderScreen] via go_router `extra` when
/// the builder is opened from a combo that has a linked FIT template
/// (Option B). In combo mode the base price is shown as covered and the
/// "Add" CTA pops with the selections + upcharge so the calling combo
/// card can attach them to a `ComboLine`.
///
/// When [sessionMinutes] is non-null the combo also bundles a play session
/// (e.g. Play + FIT meal). The builder then shows a kid picker and calls
/// `order_place` directly with combo_id + fit_selections + child_id —
/// bypassing the cart, mirroring [ComboPurchaseSheet] for parity with
/// Play + Coffee.
class FitBuilderComboContext {
  final String comboId;
  final String comboName;
  final int comboPricePaise;
  final int? sessionMinutes;
  const FitBuilderComboContext({
    required this.comboId,
    required this.comboName,
    required this.comboPricePaise,
    this.sessionMinutes,
  });
}

/// Result returned by [FitBuilderScreen] when used in combo mode. Caller
/// (combo card) wraps these into a [ComboLine.linkedFit*] payload.
class FitBuilderResult {
  final String templateId;
  final String templateName;
  final Map<String, dynamic> selections;
  final List<String> selectionsSummary;
  final int upchargePaise;
  final String? imageUrl;
  const FitBuilderResult({
    required this.templateId,
    required this.templateName,
    required this.selections,
    required this.selectionsSummary,
    required this.upchargePaise,
    this.imageUrl,
  });
}

/// FIT meal builder. Loads template + linked categories + options, renders
/// single/multi selectors per category, and shows a sticky total bar.
///
/// Pricing is server-authoritative — fit_meal_compute_price is called on
/// every selection change to refresh the total. In stand-alone mode the
/// "Add to cart" CTA pushes a [FitMealLine] onto the cart. In combo mode
/// (when [comboContext] is non-null) the CTA pops with a
/// [FitBuilderResult] instead — combo card attaches it to a [ComboLine].
class FitBuilderScreen extends ConsumerStatefulWidget {
  final String templateId;
  final FitBuilderComboContext? comboContext;
  const FitBuilderScreen({
    super.key,
    required this.templateId,
    this.comboContext,
  });

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
  // Set in session-combo mode (Play + FIT) when the parent picks a kid.
  String? _selectedChildId;

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
      final base = (priced['base_price_paise'] as int?) ?? (_basePrice ?? 0);
      final upcharge = (priced['total_upcharge_paise'] as int?) ?? _upcharge;
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

      final templateName =
          (data.template['name'] as String?) ?? 'FIT meal';
      final imageUrl = data.template['photo_url'] as String?;

      if (widget.comboContext != null) {
        // Combo mode: don't touch the cart here. Pop with the result so
        // the calling combo card can attach it to a ComboLine. Avoids
        // double-add (combo + standalone FIT meal both in the cart).
        if (!mounted) return;
        // ignore: avoid_dynamic_calls
        Navigator.of(context).pop(
          FitBuilderResult(
            templateId: widget.templateId,
            templateName: templateName,
            selections: Map<String, dynamic>.from(_selections),
            selectionsSummary: summary,
            upchargePaise: upcharge,
            imageUrl: imageUrl,
          ),
        );
        return;
      }

      // Stand-alone mode: write directly to the cart.
      ref.read(cartProvider.notifier).addFitMeal(
            FitMealLine.create(
              templateId: widget.templateId,
              templateName: templateName,
              unitPricePaise: unit,
              quantity: 1,
              selectionsJsonb: Map<String, dynamic>.from(_selections),
              selectionsSummary: summary,
              imageUrl: imageUrl,
            ),
          );
      // Suppress an "unused" lint while the var is in scope for clarity.
      // ignore: unused_local_variable
      final _ = base;

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

  /// Place an order directly from the FIT builder when the combo bundles
  /// a play session (Play + FIT). Mirrors [ComboPurchaseSheet] — combo +
  /// fit_selections + child_id sent in one [order_place] call. Server
  /// creates the session row automatically. Bypasses the cart so the
  /// flow matches Play + Coffee.
  Future<void> _placeOrderDirectly() async {
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null || _selectedChildId == null) return;
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final result = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('order_place', params: {
        'p_venue_id': _venueId,
        'p_family_id': familyId,
        'p_items': [
          {
            'type': 'combo',
            'combo_id': widget.comboContext!.comboId,
            'quantity': 1,
            'fit_selections': _selections,
          }
        ],
        'p_fulfillment_mode': 'dine_in',
        'p_payment_method': 'wallet',
        'p_combo_id': null,
        'p_child_id': _selectedChildId,
        'p_idempotency_key': const Uuid().v4(),
        'p_customer_gstin': null,
      });
      final orderId = result['order_id'] as String?;
      if (!mounted) return;
      ref.invalidate(activeSessionsProvider);
      if (orderId != null) {
        context.go('/club/order/$orderId');
      } else {
        context.go('/club');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session pending — scan at the desk to start.'),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message.contains('insufficient_balance')
            ? 'Wallet balance is short. Top up to continue.'
            : _mapError(e.message);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = 'Could not place order: $e';
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
      error: (e, _) => Scaffold(
        body: FriendlyErrorScreen(
          code: 'E-FIT-1',
          userMessage: "Couldn't load this meal",
          technicalDetails: e.toString(),
          onRetry: () =>
              ref.invalidate(fitTemplateDetailProvider(widget.templateId)),
        ),
      ),
      data: (data) => _buildLoaded(context, data),
    );
  }

  Widget _buildLoaded(BuildContext context, _BuilderData data) {
    final tpl = data.template;
    _basePrice ??= tpl['base_price_paise'] as int?;
    final final_ = (_basePrice ?? 0) + _upcharge;
    final isCombo = widget.comboContext != null;
    final sessionCombo = isCombo && widget.comboContext!.sessionMinutes != null;

    // Required-category gating for the CTA.
    final allRequiredFilled = data.linkedCategories.every((lc) {
      final isReq = (lc.linker['is_required'] as bool?) ?? true;
      if (!isReq) return true;
      final sel = _selections[lc.category['id']];
      if (sel == null) return false;
      if (sel is List && sel.isEmpty) return false;
      return true;
    });

    // Idle-child list for the kid picker (session combos only).
    final allChildren = sessionCombo
        ? (ref.watch(familyChildrenProvider).valueOrNull ?? const [])
        : const <Map<String, dynamic>>[];
    final inSession = sessionCombo
        ? ref.watch(childrenWithActiveSessionProvider)
        : const <String>{};
    final idleChildren = allChildren
        .where((c) => !inSession.contains(c['id'] as String))
        .toList();

    // Auto-select the only idle kid for single-kid families. Post-frame so
    // we never setState during build.
    if (sessionCombo &&
        _selectedChildId == null &&
        idleChildren.length == 1) {
      final onlyId = idleChildren.first['id'] as String;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_selectedChildId == null) {
          setState(() => _selectedChildId = onlyId);
        }
      });
    }

    final ctaEnabled = allRequiredFilled &&
        !_busy &&
        (!sessionCombo ||
            (idleChildren.isNotEmpty && _selectedChildId != null));

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: Text(isCombo
            ? 'Customise your ${widget.comboContext!.comboName}'
            : (tpl['name'] as String?) ?? 'Build your meal'),
      ),
      // Single Column body — the previous Scaffold.bottomSheet pattern
      // collapsed the body content on Flutter web. Replaced with an
      // Expanded ListView + a fixed bottom bar so the layout is
      // dead-predictable.
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (((tpl['photo_url'] as String?) ?? '').isNotEmpty)
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      (tpl['photo_url'] as String?) ?? '',
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
                      if (isCombo)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.gold.withValues(alpha: 0.40),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.local_offer,
                                size: 18,
                                color: AppColors.navy,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${widget.comboContext!.comboName} '
                                      '(${Money.fromPaise(widget.comboContext!.comboPricePaise)}) '
                                      'covers the base.',
                                      style: AppTextStyles.body(context)
                                          .copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.navy,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Anything extra you pick adds to the combo total.',
                                      style: AppTextStyles.caption(
                                        context,
                                        color: AppColors.lightTextSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (sessionCombo) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.navy.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.navy.withValues(alpha: 0.20),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.play_circle_outline,
                                  color: AppColors.navy, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Includes a ${widget.comboContext!.sessionMinutes}-minute play session.',
                                  style: AppTextStyles.body(context).copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text("Who's playing?",
                            style: AppTextStyles.bodyLarge(context)),
                        const SizedBox(height: 8),
                        if (idleChildren.isEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withValues(alpha: 0.10),
                              border: Border.all(
                                  color:
                                      AppColors.gold.withValues(alpha: 0.40)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'All your kids are already playing. '
                              'Wrap up a session first to use this combo.',
                              style: AppTextStyles.body(context),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final c in idleChildren)
                                  _ComboChildTile(
                                    child: c,
                                    selected: _selectedChildId == c['id'],
                                    onTap: () => setState(() =>
                                        _selectedChildId = c['id'] as String),
                                  ),
                              ],
                            ),
                          ),
                      ],
                      if ((tpl['description'] as String?)?.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            tpl['description'] as String,
                            style: AppTextStyles.body(context),
                          ),
                        ),
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.fitGreen.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.fitGreen.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 18,
                              color: AppColors.fitGreen,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Included with every meal',
                                    style: AppTextStyles.caption(
                                      context, color: AppColors.fitGreen,
                                    ).copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Sauteed veggies · Garden salad',
                                    style: AppTextStyles.body(context),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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
                      if (data.linkedCategories.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              'No sections to customise.',
                              style: AppTextStyles.body(
                                context, color: AppColors.lightTextSecondary,
                              ),
                            ),
                          ),
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
          ),
          // Fixed bottom bar — replaces Scaffold.bottomSheet.
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              decoration: const BoxDecoration(
                color: AppColors.lightSurface,
                border: Border(top: BorderSide(color: AppColors.lightBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: isCombo
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Combo + extras',
                                style: AppTextStyles.caption(
                                  context,
                                  color: AppColors.lightTextSecondary,
                                ),
                              ),
                              Text(
                                Money.fromPaise(
                                  widget.comboContext!.comboPricePaise +
                                      _upcharge,
                                ),
                                style: AppTextStyles.h2(
                                  context,
                                  color: AppColors.fitGreen,
                                ),
                              ),
                              if (_upcharge > 0)
                                Text(
                                  '${Money.fromPaise(widget.comboContext!.comboPricePaise)} '
                                  'combo + ${Money.fromPaise(_upcharge)} extras',
                                  style: AppTextStyles.caption(
                                    context,
                                    color: AppColors.lightTextSecondary,
                                  ),
                                )
                              else
                                Text(
                                  'No extras — combo covers everything.',
                                  style: AppTextStyles.caption(
                                    context,
                                    color: AppColors.lightTextSecondary,
                                  ),
                                ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total',
                                style: AppTextStyles.caption(
                                  context,
                                  color: AppColors.lightTextSecondary,
                                ),
                              ),
                              Text(
                                Money.fromPaise(final_),
                                style: AppTextStyles.h2(
                                  context,
                                  color: AppColors.fitGreen,
                                ),
                              ),
                            ],
                          ),
                  ),
                  SizedBox(
                    width: 200,
                    child: PrimaryButton(
                      label: sessionCombo
                          ? 'Place order · ${Money.fromPaise(widget.comboContext!.comboPricePaise + _upcharge)}'
                          : (isCombo ? 'Confirm meal' : 'Add to cart'),
                      loading: _busy,
                      onPressed: !ctaEnabled
                          ? null
                          : (sessionCombo
                              ? _placeOrderDirectly
                              : () => _addToCart(data, final_)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
    final rawName = (category['name'] as String?) ?? '—';
    final slug = (category['slug'] as String?) ?? '';
    // Customer-facing display label: strip the parenthetical
    // disambiguator (e.g. '(Balanced)') and rename protein categories
    // to a friendlier 'Choose Your Protein'.
    final name = slug.startsWith('protein_')
        ? 'Choose Your Protein'
        : rawName.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
    final subtitle = (category['description'] as String?) ?? '';
    final required = (linker['is_required'] as bool?) ?? true;
    final selType = (linker['selection_type_override'] as String?)
        ?? (category['selection_type'] as String?) ?? 'single';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(name, style: AppTextStyles.h3(context))),
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
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: AppTextStyles.caption(
                context, color: AppColors.lightTextSecondary,
              ),
            ),
          ],
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

class _ComboChildTile extends StatelessWidget {
  final Map<String, dynamic> child;
  final bool selected;
  final VoidCallback onTap;
  const _ComboChildTile({
    required this.child,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = (child['name'] as String?) ?? '—';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(
            color: selected ? AppColors.navy : AppColors.lightBorder,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.navy : AppColors.lightBorder,
            ),
            const SizedBox(width: 12),
            Text(name, style: AppTextStyles.body(context)),
          ],
        ),
      ),
    );
  }
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
        .rpc<dynamic>('fit_template_detail', params: {
      'p_template_id': templateId,
    });
    final root = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};

    final tpl = root['template'] is Map
        ? Map<String, dynamic>.from(root['template'] as Map)
        : <String, dynamic>{};

    final sections = (root['sections'] is List
            ? List<dynamic>.from(root['sections'] as List)
            : const <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map((s) => Map<String, dynamic>.from(s))
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
