import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

const _heroOrder = ['rafi', 'ellie', 'gerry', 'zena'];

const _heroTraits = {
  'rafi': 'Bravery',
  'ellie': 'Kindness',
  'gerry': 'Curiosity',
  'zena': 'Creativity',
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

// Conversation prompts surfaced to the parent based on the kid's
// top-growing trait this month. Designed to spark a specific question
// at dinner instead of a generic "how was the venue?".
const _heroPrompts = {
  'rafi':
      'What made [name] brave this month? Pick one moment together.',
  'ellie':
      'Who did [name] help this month? What did it feel like?',
  'gerry':
      'What did [name] discover this month that they\'re still curious about?',
  'zena':
      'What\'s the one thing [name] made or invented that they\'re proudest of?',
};

/// Adventure-tab card showing the kid's last-30-day growth — per-trait
/// XP earned, top growing trait, and a parent conversation prompt.
/// Auto-hides if no XP earned in the window.
class GrowthThisMonthCard extends ConsumerWidget {
  final String childId;
  final String childName;
  const GrowthThisMonthCard({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(_recentXpEventsProvider(childId));
    return eventsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (events) {
        final totals = <String, int>{
          for (final h in _heroOrder) h: 0,
        };
        for (final e in events) {
          for (final h in _heroOrder) {
            totals[h] = totals[h]! + ((e['xp_$h'] as int?) ?? 0);
          }
        }
        final totalXp = totals.values.fold<int>(0, (a, b) => a + b);
        if (totalXp <= 0) return const SizedBox.shrink();

        // Top trait by XP gained — falls back to favourite if all tied.
        final top = _heroOrder.reduce(
          (a, b) => totals[a]! >= totals[b]! ? a : b,
        );
        final color = _heroColors[top]!;
        final prompt = (_heroPrompts[top] ?? '').replaceAll('[name]', childName);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.lightSurface,
              border: Border.all(color: color.withValues(alpha: 0.30)),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(PhosphorIconsFill.trendUp, color: color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Growth this month',
                        style: AppTextStyles.h3(context),
                      ),
                    ),
                    Text(
                      '+$totalXp XP',
                      style: AppTextStyles.body(context).copyWith(
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Per-trait deltas as a 2x2 grid for compact density.
                Row(
                  children: [
                    Expanded(child: _TraitDelta(hero: 'rafi', xp: totals['rafi']!)),
                    const SizedBox(width: 8),
                    Expanded(child: _TraitDelta(hero: 'ellie', xp: totals['ellie']!)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _TraitDelta(hero: 'gerry', xp: totals['gerry']!)),
                    const SizedBox(width: 8),
                    Expanded(child: _TraitDelta(hero: 'zena', xp: totals['zena']!)),
                  ],
                ),
                if (prompt.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(PhosphorIconsFill.chatCircleText,
                            color: color, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Conversation starter',
                                style: AppTextStyles.caption(context).copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                prompt,
                                style: AppTextStyles.body(context),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TraitDelta extends StatelessWidget {
  final String hero;
  final int xp;
  const _TraitDelta({required this.hero, required this.xp});

  @override
  Widget build(BuildContext context) {
    final color = _heroColors[hero]!;
    final faded = xp == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.lightBackground,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: color.withValues(
                alpha: faded ? 0.10 : 0.18,
              ),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              _heroIcons[hero]!,
              color: color.withValues(alpha: faded ? 0.50 : 1.0),
              size: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _heroTraits[hero]!,
                  style: AppTextStyles.caption(context).copyWith(
                    fontWeight: FontWeight.w700,
                    color: faded ? AppColors.lightTextSecondary : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  xp == 0 ? '—' : '+$xp XP',
                  style: AppTextStyles.caption(context).copyWith(
                    color: faded
                        ? AppColors.lightTextSecondary
                        : color,
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

// ─── providers ─────────────────────────────────────────────────────────────

final _recentXpEventsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, childId) async {
  final since = DateTime.now().toUtc().subtract(const Duration(days: 30));
  final rows = await Supabase.instance.client
      .from('xp_events')
      .select('xp_rafi, xp_ellie, xp_gerry, xp_zena, created_at, event_type')
      .eq('child_id', childId)
      .gte('created_at', since.toIso8601String());
  return List<Map<String, dynamic>>.from(rows);
});
