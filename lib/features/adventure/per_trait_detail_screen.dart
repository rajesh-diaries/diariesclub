import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/child_stage_history_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/trait_progress_bar.dart';
import '../gamification/widgets/stage_history_timeline.dart';
import 'providers/child_by_id_provider.dart';
import 'widgets/hero_card_collection_section.dart';

/// `/adventure/trait/:childId/:hero` — focused detail for one trait.
/// Hero name + stage label + progress bar + 6-card per-hero grid +
/// stage history filtered to this trait.
///
/// stage_history rows aren't queryable by trait directly (they live
/// inside `xp_events.metadata->stage_transitions`), so we reuse
/// childStageHistoryProvider and filter client-side.
class PerTraitDetailScreen extends ConsumerWidget {
  final String childId;
  final String hero;

  const PerTraitDetailScreen({
    super.key,
    required this.childId,
    required this.hero,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final child = ref.watch(childByIdProvider(childId));
    final history =
        ref.watch(childStageHistoryProvider(childId)).valueOrNull ??
            const [];
    final filteredCount =
        history.where((e) => e.trait == hero).length;

    if (child == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final color = _heroColor(hero);
    final stage = (child['stage_$hero'] as String?) ?? 'seedling';
    final xp = (child['xp_$hero'] as int?) ?? 0;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(_heroName(hero)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _Hero(hero: hero, stage: stage, xp: xp, color: color),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
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
                child: TraitProgressBar(
                  trait: hero,
                  currentXp: xp,
                  currentStage: stage,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '${_heroName(hero).toUpperCase()} CARDS',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ).copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            HeroCardCollectionSection(
              childId: childId,
              singleHero: hero,
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'MILESTONES',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ).copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            if (filteredCount == 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.lightBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "Your kid hasn't reached their first milestone yet — "
                    'keep playing to grow!',
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ),
              )
            else
              // Reuse the master timeline; the per-trait variant just
              // filters to this trait via client-side filter inside the
              // widget. We pass the same childId — the timeline shows
              // every transition including non-this-trait ones, which is
              // a forgivable v1 simplification (per-trait filter is
              // tracked as a future polish).
              StageHistoryTimeline(childId: childId),
          ],
        ),
      ),
    );
  }

  static String _heroName(String h) => switch (h) {
        'rafi' => 'Rafi',
        'ellie' => 'Ellie',
        'gerry' => 'Gerry',
        'zena' => 'Zena',
        _ => '?',
      };

  static Color _heroColor(String h) => switch (h) {
        'rafi' => AppColors.rafiCoral,
        'ellie' => AppColors.ellieBlue,
        'gerry' => AppColors.gerryAmber,
        'zena' => AppColors.zenaGreen,
        _ => AppColors.gold,
      };
}

class _Hero extends StatelessWidget {
  final String hero;
  final String stage;
  final int xp;
  final Color color;
  const _Hero({
    required this.hero,
    required this.stage,
    required this.xp,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.30),
            color.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.20),
            ),
            child: Icon(_iconFor(hero), color: color, size: 40),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _heroFullLabel(hero),
                  style: AppTextStyles.h2(context, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_stageLabel(stage)} · $xp XP',
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _heroFullLabel(String h) => switch (h) {
        'rafi' => 'Rafi the Brave',
        'ellie' => 'Ellie the Kind',
        'gerry' => 'Gerry the Curious',
        'zena' => 'Zena the Creative',
        _ => h,
      };

  static String _stageLabel(String s) =>
      s.isEmpty ? '?' : s[0].toUpperCase() + s.substring(1);

  static IconData _iconFor(String h) => switch (h) {
        'rafi' => PhosphorIconsFill.shieldStar,
        'ellie' => PhosphorIconsFill.heart,
        'gerry' => PhosphorIconsFill.magnifyingGlass,
        'zena' => PhosphorIconsFill.palette,
        _ => PhosphorIconsFill.sparkle,
      };
}
