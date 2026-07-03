import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Vertical timeline for order status. Past steps get a check, current
/// step gets the spinning/active dot, future steps stay outlined.
class OrderStatusTimeline extends StatelessWidget {
  final String currentStatus;
  final String fulfillmentMode;
  final String paymentMethod;
  const OrderStatusTimeline({
    super.key,
    required this.currentStatus,
    this.fulfillmentMode = 'dine_in',
    this.paymentMethod = 'wallet',
  });

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
                    _cancelledSubtitle(paymentMethod),
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

  String _cancelledSubtitle(String paymentMethod) => switch (paymentMethod) {
        'wallet' => 'Order cancelled. Refunded to wallet.',
        'cash' => 'Order cancelled. No charge.',
        'razorpay' => 'Order cancelled. Refund initiated to your original payment method.',
        _ => 'Order cancelled.',
      };

  String _label(String s) {
    if (s == 'ready') {
      return switch (fulfillmentMode) {
        'takeaway' => 'Ready for pickup',
        'table_service' => 'Ready to serve',
        _ => 'Ready to serve',
      };
    }
    return switch (s) {
      'pending' => 'Order received',
      'preparing' => 'Preparing your food',
      'served' => 'Served',
      _ => s,
    };
  }
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
                      ? const Icon(PhosphorIconsBold.check,
                          color: Colors.white, size: 14)
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
