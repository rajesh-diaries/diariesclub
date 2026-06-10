import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// One child tile in the multi-child Adventure picker. Rectangular card
/// with the kid's favourite hero image, name, level and stage chip.
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
    final heroPath = 'assets/hero/$favouriteHero.png';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(
            color: AppColors.gold.withValues(alpha: 0.30),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero image area with rounded top corners.
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                padding: const EdgeInsets.all(10),
                child: Image.asset(
                  heroPath,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(
                      _heroIcon(favouriteHero),
                      color: color,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
            // Text info.
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      style: AppTextStyles.bodyLarge(context)
                          .copyWith(fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Level $level',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        _stageLabel(stage),
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.gold,
                        ).copyWith(
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
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

  static IconData _heroIcon(String h) => switch (h) {
        'rafi' => PhosphorIconsFill.shieldStar,
        'ellie' => PhosphorIconsFill.heart,
        'gerry' => PhosphorIconsFill.magnifyingGlass,
        'zena' => PhosphorIconsFill.palette,
        _ => PhosphorIconsFill.sparkle,
      };
}
