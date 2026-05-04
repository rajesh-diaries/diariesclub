import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Onboarding progress indicator: small filled dots with the current step
/// highlighted in navy. Reads as "step 2 of 4" for screen readers.
class ProgressDots extends StatelessWidget {
  final int currentStep; // 1-based
  final int totalSteps;

  const ProgressDots({
    super.key,
    required this.currentStep,
    this.totalSteps = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step $currentStep of $totalSteps',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(totalSteps, (i) {
          final filled = i < currentStep;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? AppColors.navy : AppColors.lightBorder,
              ),
            ),
          );
        }),
      ),
    );
  }
}
