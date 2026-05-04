import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/hero_recap_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Compact banner shown above the dashboard when this child has any
/// pending hero recaps. Tapping the banner deep-links to the most-recent
/// reflection so the parent can clear it without leaving Adventure.
class PendingRecapsBanner extends ConsumerWidget {
  final String childId;
  const PendingRecapsBanner({super.key, required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingRecapsProvider).valueOrNull ?? const [];
    final mine = pending.where((r) => r['child_id'] == childId).toList();
    if (mine.isEmpty) return const SizedBox.shrink();

    final latest = mine.first;
    final sessionId = latest['session_id'] as String;
    final extra = mine.length - 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: InkWell(
        onTap: () => context.push('/reflection/$sessionId'),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2A4A8B), AppColors.navy],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(
                PhosphorIconsFill.sparkle,
                color: AppColors.gold,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      extra > 0
                          ? '${mine.length} reflections waiting'
                          : 'Reflection waiting',
                      style:
                          AppTextStyles.bodyLarge(context, color: Colors.white),
                    ),
                    Text(
                      'Tap to share which moments felt true.',
                      style:
                          AppTextStyles.caption(context, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward, color: AppColors.gold, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
