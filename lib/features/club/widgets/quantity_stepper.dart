import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/cart_provider.dart';

/// −/qty/+ stepper used on menu cards once the item is in the cart.
/// Decrements remove the line entirely when qty drops to 0 (handled by
/// the cart notifier).
class QuantityStepper extends ConsumerWidget {
  final String menuItemId;
  final int currentQty;

  const QuantityStepper({
    super.key,
    required this.menuItemId,
    required this.currentQty,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Btn(
            icon: Icons.remove,
            onTap: () {
              HapticFeedback.lightImpact();
              notifier.changeQuantity(menuItemId, -1);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '$currentQty',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _Btn(
            icon: Icons.add,
            onTap: () {
              HapticFeedback.lightImpact();
              notifier.changeQuantity(menuItemId, 1);
            },
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
