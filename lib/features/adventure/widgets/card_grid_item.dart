import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/hero_cards_providers.dart';

/// One tile in the hero card grid. Earned cards render in full color
/// with a small "rare" star or a "birthday" cake corner badge.
/// Anything NOT yet earned gets the fully-sealed `???` tile so the
/// artwork stays a surprise across stage / birthday / surprise /
/// random_drop — no silhouette leaks.
class CardGridItem extends StatelessWidget {
  final HeroCardRow row;
  final VoidCallback? onTap;
  const CardGridItem({super.key, required this.row, this.onTap});

  @override
  Widget build(BuildContext context) {
    final earned = row.isEarned;
    final isRare = row.isRare;
    final imageUrl = row.imageUrl ?? '';

    final image = imageUrl.isEmpty
        ? Container(
            color: _placeholderColor(row.hero).withValues(alpha: 0.20),
            alignment: Alignment.center,
            child: Icon(
              PhosphorIconsFill.sparkle,
              color: _placeholderColor(row.hero),
              size: 32,
            ),
          )
        : CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
              color: _placeholderColor(row.hero).withValues(alpha: 0.20),
            ),
          );

    return InkWell(
      onTap: earned ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: earned && isRare
                ? AppColors.gold
                : earned
                    ? AppColors.lightBorder
                    : AppColors.lightBorder.withValues(alpha: 0.60),
            width: earned && isRare ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (earned)
                image
              else
                // Sealed mystery for every unearned card — no silhouette
                // leak across stage / birthday / surprise / random_drop.
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.gold.withValues(alpha: 0.35),
                        _placeholderColor(row.hero).withValues(alpha: 0.35),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '???',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 4,
                    ),
                  ),
                ),
              if (earned && isRare)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.gold,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      PhosphorIconsFill.star,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
              if (earned && row.isBirthdayExclusive)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.rafiCoral,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      PhosphorIconsFill.cake,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _placeholderColor(String hero) => switch (hero) {
        'rafi' => AppColors.rafiCoral,
        'ellie' => AppColors.ellieBlue,
        'gerry' => AppColors.gerryAmber,
        'zena' => AppColors.zenaGreen,
        _ => AppColors.gold,
      };
}
