import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/hero_avatar.dart';

/// Inline 2×2 hero picker reused by Add child + Edit child screens.
/// Shows the actual hero character images (from onboarding assets) so the
/// parent sees the real face their kid will adventure with.
class HeroPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const HeroPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const _heroes = [
    _Hero('rafi', 'Rafi', 'Brave', AppColors.rafiCoral,
        'assets/hero/rafi.png'),
    _Hero('ellie', 'Ellie', 'Kind', AppColors.ellieBlue,
        'assets/hero/ellie.png'),
    _Hero('gerry', 'Gerry', 'Curious', AppColors.gerryAmber,
        'assets/hero/gerry.png'),
    _Hero('zena', 'Zena', 'Creative', AppColors.zenaGreen,
        'assets/hero/zena.png'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: [
        for (final h in _heroes)
          _HeroTile(
            hero: h,
            selected: selected == h.id,
            onTap: () => onChanged(h.id),
          ),
      ],
    );
  }
}

class _Hero {
  final String id;
  final String name;
  final String trait;
  final Color color;
  final String imagePath;
  const _Hero(this.id, this.name, this.trait, this.color, this.imagePath);
}

class _HeroTile extends StatelessWidget {
  final _Hero hero;
  final bool selected;
  final VoidCallback onTap;
  const _HeroTile({
    required this.hero,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? hero.color.withValues(alpha: 0.18)
              : AppColors.lightSurface,
          border: Border.all(
            color: selected ? hero.color : AppColors.lightBorder,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            HeroAvatar(
              heroId: hero.id,
              size: 48,
              selected: selected,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(hero.name, style: AppTextStyles.bodyLarge(context)),
                  Text(
                    hero.trait,
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
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
