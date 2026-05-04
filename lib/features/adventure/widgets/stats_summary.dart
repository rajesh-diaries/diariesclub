import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../providers/child_stats_summary_provider.dart';

/// 4-stat grid: completed sessions, total XP, current level, days as a
/// hero. Per Session 8 scope — deliberately narrow vs. the spec's longer
/// list. The cell value falls back to "—" while the future loads.
class StatsSummary extends ConsumerWidget {
  final String childId;
  const StatsSummary({super.key, required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(childStatsSummaryProvider(childId));
    final s = async.valueOrNull;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'STATS',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ).copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    icon: PhosphorIconsFill.timer,
                    value: '${s?.sessionsCompleted ?? 0}',
                    label: 'Sessions',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    icon: PhosphorIconsFill.star,
                    value: '${s?.totalXp ?? 0}',
                    label: 'Total XP',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    icon: PhosphorIconsFill.medal,
                    value: 'Lv ${s?.currentLevel ?? 1}',
                    label: 'Level',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    icon: PhosphorIconsFill.confetti,
                    value: s?.daysAsHero == null
                        ? '—'
                        : '${s!.daysAsHero}',
                    label: 'Days as a hero',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.gold.withValues(alpha: 0.18),
          ),
          child: Icon(icon, color: AppColors.navy, size: 18),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: AppTextStyles.bodyLarge(context)),
            Text(
              label,
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
