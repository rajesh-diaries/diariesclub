import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Promoted "tap to reflect" card that lives on Home post-session. Reads
/// from a hero_recaps row (joined with children for the name). Time-pressure
/// caption appears in the last 6 hours of the reflection window.
class HeroRecapCardWidget extends ConsumerWidget {
  final Map<String, dynamic> recap;
  const HeroRecapCardWidget({super.key, required this.recap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionId = recap['session_id'] as String;
    final totalXp = (recap['total_xp_pool'] as int?) ?? 0;
    final childName =
        ((recap['children'] as Map?)?['name'] as String?) ?? 'Your hero';
    final deadline = recap['reflection_deadline'] as String?;
    final hoursLeft = _hoursUntilDeadline(deadline);

    return GestureDetector(
      onTap: () => context.push('/reflection/$sessionId'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2A4A8B), AppColors.navy],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.20),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  PhosphorIconsFill.sparkle,
                  color: AppColors.gold,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Hero Recap',
                  style: AppTextStyles.caption(context, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$childName had an adventure!',
              style: AppTextStyles.h2(context, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap to see what they earned.',
              style: AppTextStyles.body(context, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '+$totalXp XP to share',
                style: AppTextStyles.caption(context, color: AppColors.gold),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Reflect on the session',
                  style: AppTextStyles.button(context, color: AppColors.gold),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward,
                  color: AppColors.gold,
                  size: 18,
                ),
              ],
            ),
            if (hoursLeft != null && hoursLeft < 6) ...[
              const SizedBox(height: 8),
              Text(
                hoursLeft <= 0
                    ? 'Reflection window has just closed'
                    : 'Reflection closes in ${hoursLeft}h',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.warningYellow,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  int? _hoursUntilDeadline(String? iso) {
    if (iso == null) return null;
    final diff = DateTime.parse(iso).difference(DateTime.now()).inHours;
    return diff < 0 ? 0 : diff;
  }
}
