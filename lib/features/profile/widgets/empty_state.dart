import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Reusable empty-state for activity sub-screens. Centred icon + line +
/// optional CTA that navigates to a related discovery surface.
class ProfileEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? ctaLabel;
  final String? ctaRoute;

  const ProfileEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.ctaLabel,
    this.ctaRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.lightTextSecondary),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (ctaLabel != null && ctaRoute != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push(ctaRoute!),
                child: Text(ctaLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
