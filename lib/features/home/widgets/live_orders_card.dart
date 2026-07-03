import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../club/providers/active_orders_provider.dart';

/// Customer-facing kitchen-status card on home. Shows a compact, at-a-glance
/// view of in-flight orders: item summary + current status badge + short
/// human status line. Tapping opens the order detail page.
///
/// Hidden when there are no in-flight orders.
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
        borderRadius: BorderRadius.circular(kHomeCardRadius),
        border: Border.all(color: AppColors.lightBorder),
        boxShadow: [kHomeCardShadow(context)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                const Icon(
                  PhosphorIconsFill.cookingPot,
                  size: 18,
                  color: AppColors.navy,
                ),
                const SizedBox(width: 8),
                Text(
                  orders.length == 1
                      ? 'Your order'
                      : 'Your orders (${orders.length})',
                  style: AppTextStyles.cardTitle(context),
                ),
              ],
            ),
          ),
          for (var i = 0; i < orders.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 14, endIndent: 14, color: AppColors.lightBorder),
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
    final serviceType = (order['service_type'] as String?) ?? 'dine_in';

    return InkWell(
      onTap: () => context.push('/club/order/$id'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
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
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _StatusBadge(status: status),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusMessage(status, serviceType),
                          style: AppTextStyles.caption(
                            context,
                            color: AppColors.lightTextSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              PhosphorIconsRegular.caretRight,
              size: 18,
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
      parts.add(qty > 1 ? '$qty× $name' : name);
    }
    final remaining = items.length - parts.length;
    if (remaining > 0) {
      parts.add('+$remaining more');
    }
    return parts.join(' · ');
  }

  String _statusMessage(String status, String serviceType) {
    final isPickup = serviceType == 'takeaway';
    return switch (status) {
      'preparing' => 'Preparing your order',
      'ready' => isPickup ? 'Ready for pickup' : 'Ready to serve',
      'served' => 'Served — enjoy!',
      _ => 'Order received',
    };
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'preparing' => ('Preparing', AppColors.gold),
      'ready' => ('Ready', AppColors.navy),
      'served' => ('Served', AppColors.activeGreen),
      _ => ('Placed', AppColors.lightTextSecondary),
    };

    final bg = status == 'ready' || status == 'served'
        ? color
        : color.withValues(alpha: 0.12);
    final fg = status == 'ready' || status == 'served'
        ? Colors.white
        : color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption(context, color: fg)
            .copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}
