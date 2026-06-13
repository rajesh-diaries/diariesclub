import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A branded error state with a retry action.
class BrandedErrorState extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const BrandedErrorState({
    super.key,
    this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIconsRegular.warningCircle,
            size: 48,
            color: AppColors.adminRed.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 16),
          Text(
            message ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyLarge(
              context,
              color: AppColors.navy,
            ).copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Please check your connection and try again.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(
                PhosphorIconsRegular.arrowClockwise,
                size: 18,
                color: AppColors.navy,
              ),
              label: Text(
                'Try again',
                style: AppTextStyles.body(
                  context,
                  color: AppColors.navy,
                ).copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
