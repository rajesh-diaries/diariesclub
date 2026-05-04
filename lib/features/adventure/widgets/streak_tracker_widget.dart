import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_text_styles.dart';
import '../providers/child_streak_provider.dart';

/// Visit streak card. Renders nothing when the streak record is missing
/// or current_streak_weeks is 0 (we don't want to "celebrate" a zero
/// streak — the empty state is no UI).
class StreakTrackerWidget extends ConsumerWidget {
  final String childId;
  const StreakTrackerWidget({super.key, required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(childStreakProvider(childId));
    final row = async.valueOrNull;
    final current = (row?['current_streak_weeks'] as int?) ?? 0;
    final longest = (row?['longest_streak_weeks'] as int?) ?? 0;
    if (current <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFB347), Color(0xFFE8524A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(
              PhosphorIconsFill.fire,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$current week${current == 1 ? '' : 's'} streak',
                    style: AppTextStyles.h3(context, color: Colors.white),
                  ),
                  Text(
                    _subtext(),
                    style: AppTextStyles.caption(
                      context,
                      color: Colors.white70,
                    ),
                  ),
                  if (longest > current) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Best ever: $longest weeks',
                      style: AppTextStyles.caption(
                        context,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtext() {
    final daysToSunday = (DateTime.sunday - DateTime.now().weekday) % 7;
    if (daysToSunday <= 2) {
      return 'Visit by Sunday to extend your streak.';
    }
    return 'Streak is safe through this week.';
  }
}
