import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Adventure-tab celebration shown only when this child has unlocked
/// "The Hero Within" — i.e. has a row in hero_within_unlocks. The
/// rarest unlock in the system, surfaced as a full-width gold gradient
/// card at the very top of the dashboard.
///
/// The widget queries hero_within_unlocks; if there's no row (or the
/// query errors because RLS hasn't surfaced one), it renders nothing —
/// the card is invisible to 99% of families.
class HeroWithinCelebrationCard extends ConsumerWidget {
  final String childId;
  final String childName;
  const HeroWithinCelebrationCard({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlockAsync = ref.watch(_heroWithinUnlockProvider(childId));
    return unlockAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (row) {
        if (row == null) return const SizedBox.shrink();
        final unlockedAt = DateTime.tryParse(
          (row['unlocked_at'] as String?) ?? '',
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFE082), Color(0xFFFFB300), Color(0xFFFF6F00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.30),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        PhosphorIconsFill.crown,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'THE HERO WITHIN',
                            style: AppTextStyles.caption(context).copyWith(
                              fontWeight: FontWeight.w800,
                              color: Colors.white.withValues(alpha: 0.85),
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            childName,
                            style: AppTextStyles.h2(context).copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Brave. Kind. Curious. Creative. Legend in all four.',
                  style: AppTextStyles.body(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'The rarest unlock in the Diaries Club — only the kids '
                  'who grow across every trait reach it.',
                  style: AppTextStyles.body(context).copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        PhosphorIconsFill.cake,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Lifetime free birthday upgrade',
                              style: AppTextStyles.body(context).copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Show this card at the venue when booking ${childName.split(' ').first}\'s next party.',
                              style: AppTextStyles.caption(context).copyWith(
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (unlockedAt != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Unlocked ${_formatDate(unlockedAt)}',
                    style: AppTextStyles.caption(context).copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
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

String _formatDate(DateTime d) {
  const months = [
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

final _heroWithinUnlockProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, childId) async {
  try {
    return await Supabase.instance.client
        .from('hero_within_unlocks')
        .select('child_id, unlocked_at, granted_birthday_upgrade, '
            'granted_birthday_upgrade_at, unlocked_at_total_xp')
        .eq('child_id', childId)
        .maybeSingle();
  } catch (_) {
    return null;
  }
});
