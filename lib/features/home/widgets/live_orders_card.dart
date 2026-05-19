import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../club/providers/active_orders_provider.dart';

/// Customer-facing kitchen-status card on home. Renders one row per
/// in-flight order with a status pill that flips in real time as the
/// staff app advances the order through placed → preparing → ready.
///
/// Sits between the session timer and the "Order food" CTA on
/// multi-session home so the parent can glance and know exactly what's
/// happening with their cappuccino + meal.
///
/// Hidden when there are no in-flight orders (no empty state — the
/// "Order food" CTA right below already invites action).
class LiveOrdersCard extends ConsumerWidget {
  const LiveOrdersCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(activeOrdersProvider);
    final orders = ordersAsync.valueOrNull ?? const [];
    if (orders.isEmpty) return const SizedBox.shrink();

    final orderIds = orders.map((o) => o['id'] as String).toList();
    final itemsAsync = ref.watch(activeOrderItemsProvider(orderIds));
    final allItems = itemsAsync.valueOrNull ?? const [];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                const Icon(
                  PhosphorIconsFill.cookingPot,
                  size: 20,
                  color: AppColors.navy,
                ),
                const SizedBox(width: 8),
                Text(
                  orders.length == 1
                      ? 'Your order'
                      : 'Your orders (${orders.length})',
                  style: AppTextStyles.bodyLarge(context).copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < orders.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: AppColors.lightBorder),
            _OrderRow(
              order: orders[i],
              items: allItems
                  .where((it) => it['order_id'] == orders[i]['id'])
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  const _OrderRow({required this.order, required this.items});

  @override
  Widget build(BuildContext context) {
    final id = order['id'] as String;
    final status = (order['status'] as String?) ?? 'pending';
    final isServed = status == 'served';

    return InkWell(
      onTap: () => context.push('/club/order/$id'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _itemsSummary(items),
                    style: AppTextStyles.body(context),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  _StatusPills(status: status),
                  if (isServed) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.gold.withValues(alpha: 0.40),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text('✨', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Enjoy! Hope it's lovely. ❤️",
                              style: AppTextStyles.body(context).copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.navy,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              color: AppColors.lightTextSecondary,
            ),
          ],
        ),
      ),
    );
  }

  /// "Cappuccino · Lean Meal · 1 more" — terse summary so the row stays
  /// readable on a narrow phone. Quantities collapsed into qty×name.
  String _itemsSummary(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return 'Order placed';
    final parts = <String>[];
    for (final it in items.take(3)) {
      final name = (it['name_snapshot'] as String?) ?? 'Item';
      final qty = (it['quantity'] as int?) ?? 1;
      parts.add(qty > 1 ? '${qty}× $name' : name);
    }
    final remaining = items.length - parts.length;
    if (remaining > 0) {
      parts.add('+$remaining more');
    }
    return parts.join(' · ');
  }
}

/// Compact pill row: placed → preparing → ready → served. The current
/// status is filled with colour, past states get a dimmer fill, future
/// states are outlined. Mirrors what the kitchen sees on the staff app.
class _StatusPills extends StatelessWidget {
  final String status;
  const _StatusPills({required this.status});

  static const _steps = <(_OrderStep, String)>[
    (_OrderStep.placed, 'Placed'),
    (_OrderStep.preparing, 'Preparing'),
    (_OrderStep.ready, 'Ready'),
    (_OrderStep.served, 'Served'),
  ];

  _OrderStep get _currentStep => switch (status) {
        'pending' => _OrderStep.placed,
        'preparing' => _OrderStep.preparing,
        'ready' => _OrderStep.ready,
        'served' => _OrderStep.served,
        _ => _OrderStep.placed,
      };

  @override
  Widget build(BuildContext context) {
    final current = _currentStep;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (step, label) in _steps)
          _StatusPill(
            label: label,
            state: step.index < current.index
                ? _PillState.past
                : step.index == current.index
                    ? _PillState.current
                    : _PillState.future,
          ),
      ],
    );
  }
}

enum _OrderStep { placed, preparing, ready, served }

enum _PillState { past, current, future }

class _StatusPill extends StatelessWidget {
  final String label;
  final _PillState state;
  const _StatusPill({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color textColor;
    final Color border;
    final bool showDot;

    switch (state) {
      case _PillState.current:
        fill = AppColors.navy;
        textColor = Colors.white;
        border = AppColors.navy;
        showDot = true;
        break;
      case _PillState.past:
        fill = AppColors.activeGreen.withValues(alpha: 0.18);
        textColor = AppColors.activeGreen;
        border = AppColors.activeGreen.withValues(alpha: 0.40);
        showDot = false;
        break;
      case _PillState.future:
        fill = Colors.transparent;
        textColor = AppColors.lightTextSecondary;
        border = AppColors.lightBorder;
        showDot = false;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state == _PillState.past)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.check, size: 12, color: AppColors.activeGreen),
            ),
          if (showDot)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          Text(
            label,
            style: AppTextStyles.caption(context, color: textColor).copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
