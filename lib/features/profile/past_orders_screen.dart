import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/profile_history_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import 'widgets/empty_state.dart';

/// Past Café Diaries / FIT Diaries / Combos orders. Empty state CTA goes
/// to the Club tab to browse the menu (Session 7 builds the placement
/// flow; this screen lights up automatically once orders start landing).
class PastOrdersScreen extends ConsumerWidget {
  const PastOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pastOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Past orders'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const ProfileEmptyState(
            icon: PhosphorIconsRegular.coffee,
            message: "We couldn't load orders. Try again in a moment.",
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return const ProfileEmptyState(
                icon: PhosphorIconsRegular.coffee,
                message:
                    "You'll see your café and FIT orders here. Browse the menu →",
                ctaLabel: 'Browse menu',
                ctaRoute: '/club',
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(pastOrdersProvider),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.lightBorder),
                itemBuilder: (_, i) => _OrderRow(order: rows[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final Map<String, dynamic> order;
  const _OrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final amount = (order['total_paise'] as int?) ?? 0;
    final coins = (order['coins_earned'] as int?) ?? 0;
    final created = order['created_at'] as String?;
    final parsedCreated =
        created == null ? null : DateTime.tryParse(created)?.toLocal();
    final dateStr = parsedCreated == null
        ? '—'
        : DateFormat('MMM d, h:mm a').format(parsedCreated);

    final items = ((order['order_items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final brands = items
        .map((i) => (i['brand'] as String?)?.toLowerCase() ?? '')
        .toSet();

    // Title — derive from line-item brand mix. Combos show the combo
    // item's name (e.g., "Play + Coffee"); single-brand orders show the
    // brand label; mixed cafe+fit shows "Café + FIT Diaries".
    String title;
    IconData icon;
    if (brands.contains('combo')) {
      final comboItem = items.firstWhere(
        (i) => (i['brand'] as String?)?.toLowerCase() == 'combo',
        orElse: () => const {},
      );
      title = (comboItem['name_snapshot'] as String?) ?? 'Combo';
      icon = PhosphorIconsRegular.gift;
    } else if (brands.length == 1 && brands.first == 'fit') {
      title = 'FIT Diaries';
      icon = PhosphorIconsRegular.carrot;
    } else if (brands.length == 1 && brands.first == 'coffee') {
      title = 'Coffee Diaries';
      icon = PhosphorIconsRegular.coffee;
    } else if (brands.contains('fit') && brands.contains('coffee')) {
      title = 'Café + FIT Diaries';
      icon = PhosphorIconsRegular.forkKnife;
    } else {
      title = 'Order';
      icon = PhosphorIconsRegular.forkKnife;
    }

    // Item summary — "Cappuccino × 1, Croissant × 2" or just "Cappuccino"
    // when qty=1. Skip combo lines here (combo name is already the title).
    final itemSummary = items
        .where((i) => (i['brand'] as String?)?.toLowerCase() != 'combo')
        .map((i) {
          final name = (i['name_snapshot'] as String?) ?? '';
          final qty = (i['quantity'] as int?) ?? 1;
          return qty > 1 ? '$name × $qty' : name;
        })
        .where((s) => s.isNotEmpty)
        .join(', ');

    final subtitleParts = <String>[
      dateStr,
      if (coins > 0) 'earned $coins coins',
    ];

    return ListTile(
      leading: Icon(icon, color: AppColors.coffeeBrown),
      title: Text(title, style: AppTextStyles.body(context)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (itemSummary.isNotEmpty)
            Text(
              itemSummary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption(context),
            ),
          Text(
            subtitleParts.join(' · '),
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
      trailing: Text(
        Money.fromPaise(amount),
        style: AppTextStyles.body(context),
      ),
      onTap: () => _showOrderDetail(context, order, title, icon),
    );
  }

  void _showOrderDetail(
    BuildContext context,
    Map<String, dynamic> order,
    String title,
    IconData icon,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _OrderDetailSheet(order: order, title: title, icon: icon),
    );
  }
}

class _OrderDetailSheet extends StatelessWidget {
  final Map<String, dynamic> order;
  final String title;
  final IconData icon;
  const _OrderDetailSheet({
    required this.order,
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final items = ((order['order_items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final subtotal = (order['subtotal_paise'] as int?) ?? 0;
    final gst = (order['gst_paise'] as int?) ?? 0;
    final comboDiscount = (order['combo_discount_paise'] as int?) ?? 0;
    final total = (order['total_paise'] as int?) ?? 0;
    final coins = (order['coins_earned'] as int?) ?? 0;
    final created = order['created_at'] as String?;
    final parsedCreated =
        created == null ? null : DateTime.tryParse(created)?.toLocal();
    final dateStr = parsedCreated == null
        ? '—'
        : DateFormat('MMM d, yyyy · h:mm a').format(parsedCreated);

    return Padding(
      padding: EdgeInsets.only(
        top: 16,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(icon, color: AppColors.coffeeBrown, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: AppTextStyles.h2(context)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            dateStr,
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 20),
          Text('Items', style: AppTextStyles.bodyLarge(context)),
          const SizedBox(height: 8),
          for (final item in items) _ItemLine(item: item),
          const SizedBox(height: 16),
          const Divider(),
          _TotalLine(label: 'Subtotal', paise: subtotal),
          if (comboDiscount > 0)
            _TotalLine(
              label: 'Combo discount',
              paise: -comboDiscount,
              accent: AppColors.activeGreen,
            ),
          if (gst > 0) _TotalLine(label: 'GST', paise: gst),
          _TotalLine(label: 'Total', paise: total, bold: true),
          if (coins > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Earned $coins coins',
              style: AppTextStyles.caption(
                context,
                color: AppColors.gold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ItemLine({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = (item['name_snapshot'] as String?) ?? '—';
    final qty = (item['quantity'] as int?) ?? 1;
    final unitPaise = (item['unit_price_paise'] as int?) ?? 0;
    final linePaise = unitPaise * qty;
    final lineType = (item['line_type'] as String?) ?? '';
    final selections =
        (item['selections_jsonb'] as Map?)?.cast<String, dynamic>();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  qty > 1 ? '$name × $qty' : name,
                  style: AppTextStyles.body(context),
                ),
              ),
              Text(
                Money.fromPaise(linePaise),
                style: AppTextStyles.body(context),
              ),
            ],
          ),
          if (lineType == 'fit_meal' &&
              selections != null &&
              selections.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: _FitMealSelections(selections: selections),
            ),
        ],
      ),
    );
  }
}

/// Resolves a {category_id: option_id} selections map to readable
/// "Category: Option" lines under a FIT meal item.
class _FitMealSelections extends StatelessWidget {
  final Map<String, dynamic> selections;
  const _FitMealSelections({required this.selections});

  Future<List<Map<String, String>>> _resolve() async {
    final optionIds = selections.values.whereType<String>().toList();
    if (optionIds.isEmpty) return const [];
    final rows = await Supabase.instance.client
        .from('fit_meal_options')
        .select('id, name, fit_meal_categories(name)')
        .inFilter('id', optionIds);
    return (rows as List).map((r) {
      final row = r as Map;
      final cat = (row['fit_meal_categories'] as Map?)?['name'] as String?;
      return {
        'category': cat ?? '',
        'option': (row['name'] as String?) ?? '',
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, String>>>(
      future: _resolve(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in snap.data!)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '· ${s['category']}: ${s['option']}',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TotalLine extends StatelessWidget {
  final String label;
  final int paise;
  final bool bold;
  final Color? accent;
  const _TotalLine({
    required this.label,
    required this.paise,
    this.bold = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? AppTextStyles.bodyLarge(context)
        : AppTextStyles.body(context, color: accent);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(Money.fromPaise(paise), style: style),
        ],
      ),
    );
  }
}
