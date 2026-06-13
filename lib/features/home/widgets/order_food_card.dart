import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../club/providers/pending_club_tab_provider.dart';

/// "Order food" CTA on idle & multi-session home. Warm cream card that
/// mirrors the Let's Play card layout — text left, button + Rafi right.
class OrderFoodCard extends ConsumerWidget {
  const OrderFoodCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(kHomeCardRadius),
      onTap: () {
        ref.read(pendingClubTabProvider.notifier).state = 0; // Cafe
        context.go('/club');
      },
      child: Container(
        padding: const EdgeInsets.all(kHomeCardPadding),
        decoration: BoxDecoration(
          color: const Color(0xFFFDF8EE),
          borderRadius: BorderRadius.circular(kHomeCardRadius),
          border: Border.all(
            color: AppColors.coffeeBrown.withValues(alpha: 0.20),
          ),
          boxShadow: [kHomeCardShadow(context)],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.coffeeBrown.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                PhosphorIconsFill.coffee,
                color: AppColors.coffeeBrown,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Order food',
                    style: AppTextStyles.cardTitle(context),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Coffee, snacks & meals',
                    style: AppTextStyles.cardSubtitle(context),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ORDER',
                    style: AppTextStyles.pillLabel(context),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    PhosphorIconsRegular.arrowRight,
                    color: Colors.white,
                    size: 14,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
