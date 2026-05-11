import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/child_stage_history_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Vertical timeline of every stage transition this child has had.
/// Reused by the Adventure tab profile view (Session 8). Empty state
/// nudges parents back into the play loop.
class StageHistoryTimeline extends ConsumerWidget {
  final String childId;
  const StageHistoryTimeline({super.key, required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(childStageHistoryProvider(childId));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (entries) {
        if (entries.isEmpty) {
          return _Empty();
        }
        return Column(
          children: [
            for (var i = 0; i < entries.length; i++)
              _Row(
                entry: entries[i],
                isFirst: i == 0,
                isLast: i == entries.length - 1,
              ),
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  final StageTransitionEntry entry;
  final bool isFirst;
  final bool isLast;
  const _Row({
    required this.entry,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final color = _heroColor(entry.trait);
    final label =
        '${_heroName(entry.trait)}: ${_stageLabel(entry.fromStage)} → ${_stageLabel(entry.toStage)}';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 12,
                  color: isFirst ? Colors.transparent : AppColors.lightBorder,
                ),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : AppColors.lightBorder,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('MMM d, yyyy').format(entry.occurredAt),
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(label, style: AppTextStyles.body(context)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _heroColor(String t) => switch (t) {
        'rafi' => AppColors.rafiCoral,
        'ellie' => AppColors.ellieBlue,
        'gerry' => AppColors.gerryAmber,
        'zena' => AppColors.zenaGreen,
        _ => AppColors.gold,
      };
  static String _heroName(String t) => switch (t) {
        'rafi' => 'Rafi',
        'ellie' => 'Ellie',
        'gerry' => 'Gerry',
        'zena' => 'Zena',
        _ => '?',
      };
  static String _stageLabel(String s) =>
      s.isEmpty ? '?' : s[0].toUpperCase() + s.substring(1);
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            PhosphorIconsRegular.tree,
            color: AppColors.lightTextSecondary,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            "Take 5 minutes after your next session to reflect — that's how characters grow.",
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
