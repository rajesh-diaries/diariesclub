import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// 5-step progress bar visualizing the parent's distance to the child's
/// birthday. Pure presentation; the days-until value comes in from a
/// caller. Steps (BUG-009 cadence): 4 weeks, 2 weeks, 1 week, 3 days, Today!
class JourneyProgressBar extends StatelessWidget {
  final int daysUntil;
  const JourneyProgressBar({super.key, required this.daysUntil});

  static const _milestones = <(int, String)>[
    (28, '4 weeks'),
    (14, '2 weeks'),
    (7, '1 week'),
    (3, '3 days'),
    (0, 'Today!'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'JOURNEY',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ).copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < _milestones.length; i++) ...[
                _Dot(isPast: daysUntil <= _milestones[i].$1),
                if (i < _milestones.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: daysUntil <= _milestones[i + 1].$1
                          ? AppColors.gold
                          : AppColors.lightBorder,
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final m in _milestones)
                Text(
                  m.$2,
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ).copyWith(fontSize: 9),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool isPast;
  const _Dot({required this.isPast});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isPast ? AppColors.gold : AppColors.lightBorder,
      ),
    );
  }
}
