import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/hero_quests_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

const _heroOrder = ['rafi', 'ellie', 'gerry', 'zena'];

const _heroLabels = {
  'rafi': 'Rafi',
  'ellie': 'Ellie',
  'gerry': 'Gerry',
  'zena': 'Zena',
};

const _heroColors = {
  'rafi': Color(0xFFE8524A),
  'ellie': Color(0xFF4A90E2),
  'gerry': Color(0xFFF39C12),
  'zena': Color(0xFF27AE60),
};

const _heroIcons = {
  'rafi': PhosphorIconsFill.shieldStar,
  'ellie': PhosphorIconsFill.heart,
  'gerry': PhosphorIconsFill.magnifyingGlass,
  'zena': PhosphorIconsFill.palette,
};

/// Adventure-tab "This week's quests" card scoped to a single kid. Sits
/// between Hero Progress and Hero Card Collection on the per-kid
/// dashboard so quest completion reads as part of the long-arc journey.
///
/// Auto-hides if no quests are scheduled this week. Uses the shared
/// realtime stream so completion (server-side trigger insert) reflects
/// here without a manual refresh.
class KidQuestsCard extends ConsumerWidget {
  final String childId;
  const KidQuestsCard({super.key, required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(currentQuestWeekDateProvider);
    final weekRow = ref.watch(questWeekProvider).valueOrNull;
    final defs = ref.watch(questDefinitionsProvider).valueOrNull ?? const [];
    final progress =
        ref.watch(questProgressForFamilyStreamProvider).valueOrNull ?? const [];

    if (weekRow == null) return const SizedBox.shrink();

    final defsById = {for (final d in defs) d['id'] as String: d};
    final scheduled = <String, Map<String, dynamic>?>{
      'rafi': defsById[weekRow['quest_id_rafi'] as String?],
      'ellie': defsById[weekRow['quest_id_ellie'] as String?],
      'gerry': defsById[weekRow['quest_id_gerry'] as String?],
      'zena': defsById[weekRow['quest_id_zena'] as String?],
    };
    if (!scheduled.values.any((q) => q != null)) {
      return const SizedBox.shrink();
    }

    final myProgress = progress
        .where((p) =>
            p['child_id'] == childId && p['week_start_date'] == week)
        .toList();
    final done = <String, bool>{
      for (final p in myProgress)
        p['hero'] as String: p['completed_at'] != null,
    };

    final completedCount = done.values.where((v) => v).length;
    final totalCount = scheduled.values.where((q) => q != null).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.gold.withValues(alpha: 0.16),
              AppColors.gold.withValues(alpha: 0.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(PhosphorIconsFill.compass,
                    color: AppColors.gold, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "This week's quests",
                    style: AppTextStyles.h3(context),
                  ),
                ),
                Text(
                  '$completedCount / $totalCount done',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Resets Monday',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 10),
            for (final hero in _heroOrder)
              if (scheduled[hero] != null)
                _QuestChip(
                  hero: hero,
                  quest: scheduled[hero]!,
                  isDone: done[hero] ?? false,
                ),
          ],
        ),
      ),
    );
  }
}

class _QuestChip extends StatelessWidget {
  final String hero;
  final Map<String, dynamic> quest;
  final bool isDone;
  const _QuestChip({
    required this.hero,
    required this.quest,
    required this.isDone,
  });

  @override
  Widget build(BuildContext context) {
    final color = _heroColors[hero] ?? AppColors.gold;
    final title = (quest['title'] as String?) ?? 'Quest';
    final description = (quest['description'] as String?) ?? '';
    final xp = quest['xp_bonus'] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(
          color: isDone
              ? AppColors.activeGreen.withValues(alpha: 0.50)
              : color.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              isDone
                  ? PhosphorIconsFill.checkCircle
                  : (_heroIcons[hero] ?? PhosphorIconsFill.sparkle),
              color: isDone ? AppColors.activeGreen : color,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.body(context).copyWith(
                    fontWeight: FontWeight.w700,
                    decoration:
                        isDone ? TextDecoration.lineThrough : null,
                    color: isDone ? AppColors.lightTextSecondary : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (description.isNotEmpty)
                  Text(
                    description,
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  '${_heroLabels[hero] ?? hero} · +$xp XP',
                  style: AppTextStyles.caption(context).copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
