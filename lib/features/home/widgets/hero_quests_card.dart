import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/family_children_provider.dart';
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

/// Home-tab card showing this week's 4 hero quests for each kid in the
/// family. Auto-hides when no quests are scheduled for the current
/// Monday-IST week. Each kid gets their own row of 4 quest chips with
/// done/not-done state from hero_quest_progress.
class HeroQuestsCard extends ConsumerWidget {
  const HeroQuestsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(currentQuestWeekDateProvider);
    final weekRow = ref.watch(questWeekProvider).valueOrNull;
    final defs =
        ref.watch(questDefinitionsProvider).valueOrNull ?? const [];
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    final progress =
        ref.watch(questProgressForFamilyStreamProvider).valueOrNull ?? const [];

    if (weekRow == null) {
      // No quests scheduled this week — hide card entirely.
      return const SizedBox.shrink();
    }

    final defsById = {for (final d in defs) d['id'] as String: d};
    final scheduled = <String, Map<String, dynamic>?>{
      'rafi': defsById[weekRow['quest_id_rafi'] as String?],
      'ellie': defsById[weekRow['quest_id_ellie'] as String?],
      'gerry': defsById[weekRow['quest_id_gerry'] as String?],
      'zena': defsById[weekRow['quest_id_zena'] as String?],
    };

    final hasAny = scheduled.values.any((q) => q != null);
    if (!hasAny || children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.18),
            AppColors.gold.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsFill.compass,
                  color: AppColors.gold, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "This week's quests",
                  style: AppTextStyles.h3(context),
                ),
              ),
              Text(
                'Resets Monday',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final c in children)
            _ChildQuestsRow(
              child: c,
              week: week,
              scheduled: scheduled,
              progress: progress
                  .where((p) => p['child_id'] == c['id'])
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _ChildQuestsRow extends StatelessWidget {
  final Map<String, dynamic> child;
  final String week;
  final Map<String, Map<String, dynamic>?> scheduled;
  final List<Map<String, dynamic>> progress;
  const _ChildQuestsRow({
    required this.child,
    required this.week,
    required this.scheduled,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final done = <String, bool>{
      for (final p in progress)
        if (p['week_start_date'] == week)
          p['hero'] as String:
              p['completed_at'] != null,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              (child['name'] as String?) ?? 'Hero',
              style: AppTextStyles.body(context).copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final hero in _heroOrder)
            if (scheduled[hero] != null)
              _QuestChip(
                hero: hero,
                quest: scheduled[hero]!,
                isDone: done[hero] ?? false,
              ),
        ],
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
            width: 26, height: 26,
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
              size: 16,
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
                    color: isDone
                        ? AppColors.lightTextSecondary
                        : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_heroLabels[hero] ?? hero} · +$xp XP',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (isDone)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                PhosphorIconsFill.checkCircle,
                color: AppColors.activeGreen,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }
}

// Providers extracted to lib/core/providers/hero_quests_providers.dart
// so the Adventure tab's per-kid card shares the same realtime stream.
