import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';

/// Shown when the family is_cafe_only=true (or has zero live children).
/// Dignified empty state — emphasizes the four heroes are waiting,
/// rather than guilt-tripping the parent.
class CafeOnlyEmptyState extends StatelessWidget {
  const CafeOnlyEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 240,
                height: 160,
                child: _HeroIdleRow(),
              ),
              const SizedBox(height: 24),
              Text(
                'Adventures await!',
                style: AppTextStyles.h1(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Add a child to your family to start their journey with '
                'Rafi, Ellie, Gerry, and Zena.',
                style: AppTextStyles.body(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 240,
                child: PrimaryButton(
                  label: 'Add a child',
                  onPressed: () => context.push('/profile/add-child'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroIdleRow extends StatelessWidget {
  static const _cells = [
    (PhosphorIconsFill.shieldStar, AppColors.rafiCoral),
    (PhosphorIconsFill.heart, AppColors.ellieBlue),
    (PhosphorIconsFill.magnifyingGlass, AppColors.gerryAmber),
    (PhosphorIconsFill.palette, AppColors.zenaGreen),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final (icon, color) in _cells)
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
      ],
    );
  }
}
