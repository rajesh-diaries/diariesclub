import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';

/// CTA card on Home (idle or multi-session). Tap → /session/start.
/// Navy gradient with gold accents — action-oriented and premium.
class StartSessionCard extends StatelessWidget {
  const StartSessionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/session/start'),
      child: Container(
        padding: const EdgeInsets.all(kHomeCardPadding),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF2A4A8B),
              AppColors.navy,
            ],
          ),
          borderRadius: BorderRadius.circular(kHomeCardRadius),
          boxShadow: [kHomeCardShadow(context)],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                PhosphorIconsFill.usersThree,
                color: AppColors.gold,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Add a friend to play!',
                    style: AppTextStyles.cardTitle(context, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Bring a sibling or friend along',
                    style: AppTextStyles.cardSubtitle(
                      context,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              PhosphorIconsRegular.caretRight,
              color: Colors.white54,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}
