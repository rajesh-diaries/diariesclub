import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/family_children_provider.dart';
import '../../core/providers/hero_recap_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/skeleton_card.dart';
import '../../core/widgets/trait_progress_bar.dart';
import '../gamification/widgets/stage_history_timeline.dart';
import 'providers/child_by_id_provider.dart';
import 'providers/child_stats_summary_provider.dart';
import 'widgets/child_header.dart';
import 'widgets/growth_this_month_card.dart';
import 'widgets/hero_card_collection_section.dart';
import 'widgets/hero_within_celebration_card.dart';
import 'widgets/kid_quests_card.dart';
import 'widgets/no_sessions_empty_state.dart';
import 'widgets/pending_recaps_banner.dart';
import 'widgets/stats_summary.dart';
import 'widgets/streak_tracker_widget.dart';

/// Per-child Adventure dashboard. Empty when the child has no completed
/// sessions yet (steers them to /home). Otherwise scrolls through:
///
///   1. ChildHeader (avatar, name, level, stage, switch CTA)
///   2. PendingRecapsBanner (if any reflections pending)
///   3. StatsSummary
///   4. StreakTrackerWidget (hidden when current_streak_weeks == 0)
///   5. Hero progress (4 TraitProgressBar — tappable into per-trait detail)
///   6. HeroCardCollectionSection
///   7. StageHistoryTimeline (existing widget from Session 6)
///
/// Realtime: children, hero_card_collection, streak_records, xp_events
/// are all in supabase_realtime — every panel updates without refresh.
class ChildAdventureDashboard extends ConsumerWidget {
  final String childId;
  const ChildAdventureDashboard({super.key, required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final child = ref.watch(childByIdProvider(childId));
    if (child == null) {
      // childByIdProvider returns null both while the family children
      // stream loads AND when the child no longer exists (soft-deleted).
      // Only skeleton the former; a resolved null means "not found".
      final resolved = ref.watch(familyChildrenProvider).hasValue;
      if (!resolved) {
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: SkeletonList(itemCount: 6, itemHeight: 96),
          ),
        );
      }
      return const SafeArea(
        child: Center(
          child: BrandedEmptyState(
            icon: PhosphorIconsRegular.userMinus,
            title: 'Child not found',
            subtitle: 'This profile may have been removed.',
          ),
        ),
      );
    }

    final totalXp = (child['total_xp'] as int?) ?? 0;
    final pending = ref.watch(pendingRecapsProvider).valueOrNull ?? const [];
    final mine = pending.where((r) => r['child_id'] == childId).toList();
    if (totalXp <= 0 && mine.isEmpty) {
      // No sessions yet → "begin the journey" empty state. (Total XP > 0
      // means at least one reflection or healthy-bite credit has fired.)
      return Column(
        children: [
          ChildHeader(child: child),
          const Expanded(child: NoSessionsEmptyState()),
        ],
      );
    }

    final childName = (child['name'] as String?) ?? 'Your kid';
    return RefreshIndicator(
      onRefresh: () async {
        // Re-seed the realtime-backed child data and the future-backed
        // stats/recaps so a pull-to-refresh recovers from a dropped socket.
        ref.invalidate(familyChildrenProvider);
        ref.invalidate(pendingRecapsProvider);
        ref.invalidate(childStatsSummaryProvider(childId));
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          ChildHeader(child: child),
          PendingRecapsBanner(childId: childId),
          const SizedBox(height: kHomeSectionGap),
          HeroWithinCelebrationCard(childId: childId, childName: childName),
          StatsSummary(childId: childId),
          const SizedBox(height: kHomeSectionGap),
          StreakTrackerWidget(childId: childId),
          const SizedBox(height: kHomeSectionGap),
          GrowthThisMonthCard(childId: childId, childName: childName),
          const SizedBox(height: kHomeSectionGap),
          _HeroProgress(child: child),
          const SizedBox(height: 16),
          KidQuestsCard(childId: childId),
          const SizedBox(height: 16),
          HeroCardCollectionSection(childId: childId),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'HERO MILESTONES',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ).copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          StageHistoryTimeline(childId: childId),
        ],
      ),
    );
  }
}

class _HeroProgress extends StatelessWidget {
  final Map<String, dynamic> child;
  const _HeroProgress({required this.child});

  @override
  Widget build(BuildContext context) {
    final childId = child['id'] as String;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HERO PROGRESS',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ).copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: kHomeSectionGap),
          for (final hero in const ['rafi', 'ellie', 'gerry', 'zena']) ...[
            InkWell(
              onTap: () => context.push('/adventure/trait/$childId/$hero'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.lightSurface,
                  border: Border.all(color: AppColors.lightBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TraitProgressBar(
                        trait: hero,
                        currentXp: (child['xp_$hero'] as int?) ?? 0,
                        currentStage:
                            (child['stage_$hero'] as String?) ?? 'seedling',
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      PhosphorIconsRegular.caretRight,
                      color: AppColors.lightTextSecondary,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
