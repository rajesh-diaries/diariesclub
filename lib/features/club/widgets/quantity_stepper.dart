import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../providers/cart_provider.dart';

/// −/qty/+ stepper used on menu cards once the item is in the cart.
/// Decrements remove the line entirely when qty drops to 0 (handled by
/// the cart notifier).
class QuantityStepper extends ConsumerWidget {
  final String? menuItemId;
  final String? lineId;
  final int currentQty;

  const QuantityStepper({
    super.key,
    this.menuItemId,
    this.lineId,
    required this.currentQty,
  }) : assert(menuItemId != null || lineId != null);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);
    void change(int delta) {
      HapticFeedback.lightImpact();
      if (lineId != null) {
        notifier.changeQuantityById(lineId!, delta);
      } else {
        notifier.changeQuantity(menuItemId!, delta);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Btn(
            icon: PhosphorIconsRegular.minus,
            onTap: () => change(-1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '$currentQty',
              style: AppTextStyles.body(
                context,
                color: Colors.white,
              ).copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _Btn(
            icon: PhosphorIconsRegular.plus,
            onTap: () => change(1),
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _Btn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}
