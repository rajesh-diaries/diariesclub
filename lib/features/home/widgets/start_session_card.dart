import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/haptics.dart';

/// CTA card on Home (idle or multi-session). Tap → /session/start.
/// Navy gradient with gold accents — action-oriented and premium.
class StartSessionCard extends StatelessWidget {
  final bool compact;
  const StartSessionCard({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(kHomeCardRadius),
      onTap: () {
        AppHaptics.light();
        context.push('/session/start');
      },
      child: Container(
        padding: compact
            ? const EdgeInsets.all(12)
            : const EdgeInsets.all(kHomeCardPadding),
        decoration: BoxDecoration(
          color: compact ? const Color(0xFFFDF8EE) : null,
          gradient: compact
              ? null
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF2A4A8B),
                    AppColors.navy,
                  ],
                ),
          borderRadius: BorderRadius.circular(kHomeCardRadius),
          border: compact
              ? Border.all(color: AppColors.navy.withValues(alpha: 0.12))
              : null,
          boxShadow: [kHomeCardShadow(context)],
        ),
        child: Row(
          children: [
            Container(
              width: compact ? 36 : 44,
              height: compact ? 36 : 44,
              decoration: BoxDecoration(
                color: compact
                    ? AppColors.gold.withValues(alpha: 0.15)
                    : AppColors.gold.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(compact ? 10 : 12),
              ),
              child: Icon(
                PhosphorIconsFill.usersThree,
                color: AppColors.gold,
                size: compact ? 18 : 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    compact ? 'Add a friend' : 'Add a friend to play!',
                    style: AppTextStyles.cardTitle(
                      context,
                      color: compact ? AppColors.navy : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    compact
                        ? 'Start for a sibling'
                        : 'Bring a sibling or friend along',
                    style: AppTextStyles.cardSubtitle(
                      context,
                      color: compact
                          ? AppColors.lightTextSecondary
                          : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              PhosphorIconsRegular.caretRight,
              color: compact
                  ? AppColors.lightTextSecondary
                  : Colors.white54,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}
