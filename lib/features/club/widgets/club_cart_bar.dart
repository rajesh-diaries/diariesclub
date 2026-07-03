import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../providers/cart_provider.dart';
import 'cart_sheet.dart';

/// Sticky cart summary shown at the bottom of the Club screen for tabs that
/// support ordering (Cafe / FIT / Combos). Hidden on Birthdays / Workshops.
class ClubCartBar extends ConsumerWidget {
  final bool visible;

  const ClubCartBar({super.key, required this.visible});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartItemCountProvider);
    final total = ref.watch(cartTotalPaiseProvider);

    if (!visible || count == 0) {
      return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        color: AppColors.navy,
        child: InkWell(
          onTap: () => _openCart(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    PhosphorIconsRegular.shoppingBag,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$count ${count == 1 ? 'item' : 'items'} added',
                        style: AppTextStyles.body(
                          context,
                          color: Colors.white,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        // Pre-GST subtotal — the bag/checkout adds food GST +
                        // rounding, so this is labelled a subtotal (not the
                        // final total) to avoid the number jumping at checkout.
                        'Subtotal ${Money.fromPaise(total)} + tax',
                        style: AppTextStyles.caption(
                          context,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View Cart',
                      style: AppTextStyles.body(
                        context,
                        color: Colors.white,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      PhosphorIconsRegular.caretRight,
                      color: Colors.white,
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openCart(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CartSheet(),
    );
  }
}
