import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../club/providers/pending_club_tab_provider.dart';

/// "Order food" CTA shown on multi-session home (i.e. while at least one
/// kid is playing). Tap → opens /club on the Cafe tab so the parent can
/// grab a coffee or snack while the kid plays. We force the Cafe tab via
/// `pendingClubTabProvider` because ClubScreen's TabController persists
/// across the bottom-nav shell, so a plain go('/club') could land on
/// whatever tab the user last visited.
class OrderFoodCard extends ConsumerWidget {
  const OrderFoodCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        ref.read(pendingClubTabProvider.notifier).state = 0; // Cafe
        context.go('/club');
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.coffeeBrown.withValues(alpha: 0.20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                PhosphorIconsFill.coffee,
                color: AppColors.coffeeBrown,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order food', style: AppTextStyles.h3(context)),
                  const SizedBox(height: 2),
                  Text(
                    'Coffee, snacks, meals',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, color: AppColors.navy),
          ],
        ),
      ),
    );
  }
}
