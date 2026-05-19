import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/child_avatar.dart';

/// One child tile in the multi-child Adventure picker. Hero-color ring +
/// avatar + name + level badge + overall stage chip.
class ChildSelectCard extends StatelessWidget {
  final Map<String, dynamic> child;
  final VoidCallback onTap;

  const ChildSelectCard({
    super.key,
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = (child['name'] as String?) ?? '—';
    final favouriteHero = (child['favourite_hero'] as String?) ?? 'ellie';
    final level = (child['current_level'] as int?) ?? 1;
    final stage = (child['current_overall_stage'] as String?) ?? 'seedling';
    final color = _heroColor(favouriteHero);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(
            color: AppColors.gold.withValues(alpha: 0.30),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 3),
              ),
              child: ChildAvatar(
                name: name,
                size: 80,
              ),
            ),
            const SizedBox(height: 12),
            Text(name, style: AppTextStyles.h3(context)),
            const SizedBox(height: 4),
            Text(
              'Level $level',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                _stageLabel(stage),
                style: AppTextStyles.caption(context, color: AppColors.gold)
                    .copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _stageLabel(String s) =>
      s.isEmpty ? '?' : s[0].toUpperCase() + s.substring(1);

  static Color _heroColor(String h) => switch (h) {
        'rafi' => AppColors.rafiCoral,
        'ellie' => AppColors.ellieBlue,
        'gerry' => AppColors.gerryAmber,
        'zena' => AppColors.zenaGreen,
        _ => AppColors.gold,
      };

  // Unused helper kept for potential trait-icon future use.
  // ignore: unused_element
  static IconData _heroIcon(String h) => switch (h) {
        'rafi' => PhosphorIconsFill.shieldStar,
        'ellie' => PhosphorIconsFill.heart,
        'gerry' => PhosphorIconsFill.magnifyingGlass,
        'zena' => PhosphorIconsFill.palette,
        _ => PhosphorIconsFill.sparkle,
      };
}
