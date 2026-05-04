import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';

/// Shown when a family has children but no completed sessions yet.
/// Steers them toward starting their first session rather than rendering
/// an empty dashboard.
class NoSessionsEmptyState extends StatelessWidget {
  const NoSessionsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                PhosphorIconsFill.compass,
                size: 64,
                color: AppColors.gold,
              ),
              const SizedBox(height: 16),
              Text(
                'The journey begins',
                style: AppTextStyles.h2(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Your hero's adventure begins after their first session.",
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
                  label: 'Start a session',
                  onPressed: () => context.go('/home'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
