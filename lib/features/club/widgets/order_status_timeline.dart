import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Vertical timeline for order status. Past steps get a check, current
/// step gets the spinning/active dot, future steps stay outlined.
class OrderStatusTimeline extends StatelessWidget {
  final String currentStatus;
  const OrderStatusTimeline({super.key, required this.currentStatus});

  static const _steps = ['pending', 'preparing', 'ready', 'served'];

  @override
  Widget build(BuildContext context) {
    final cancelled = currentStatus == 'cancelled';
    final currentIndex = cancelled ? -1 : _steps.indexOf(currentStatus);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _steps.length; i++)
          _Step(
            label: _label(_steps[i]),
            isPast: !cancelled && i < currentIndex,
            isCurrent: !cancelled && i == currentIndex,
            isLast: i == _steps.length - 1,
          ),
        if (cancelled)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(
                  PhosphorIconsFill.xCircle,
                  color: AppColors.adminRed,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Order cancelled. Refunded to wallet.',
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.adminRed,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _label(String s) => switch (s) {
        'pending' => 'Order received',
        'preparing' => 'Preparing your food',
        'ready' => 'Ready for pickup',
        'served' => 'Served',
        _ => s,
      };
}

class _Step extends StatelessWidget {
  final String label;
  final bool isPast;
  final bool isCurrent;
  final bool isLast;
  const _Step({
    required this.label,
    required this.isPast,
    required this.isCurrent,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final color = isPast || isCurrent ? AppColors.activeGreen : AppColors.lightBorder;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isPast
                        ? AppColors.activeGreen
                        : isCurrent
                            ? AppColors.gold
                            : AppColors.lightBorder,
                  ),
                  child: isPast
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : isCurrent
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: color,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 0, 16),
              child: Text(
                label,
                style: isCurrent
                    ? AppTextStyles.bodyLarge(context)
                    : AppTextStyles.body(
                        context,
                        color: isPast
                            ? AppColors.lightTextPrimary
                            : AppColors.lightTextSecondary,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
