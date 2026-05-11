import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Realtime stream of parent-logged moments for one child.
///
/// `parent_logged_moments` is RLS-scoped to `family_id = auth.uid()` so
/// each family only sees their own. The Realtime subscription delivers
/// new rows the moment the RPC inserts them.
final parentLoggedMomentsProvider = StreamProvider.family<
    List<Map<String, dynamic>>, String>((ref, childId) {
  final ctrl = StreamController<List<Map<String, dynamic>>>();

  final sub = Supabase.instance.client
      .from('parent_logged_moments')
      .stream(primaryKey: ['id'])
      .eq('child_id', childId)
      .order('logged_at', ascending: false)
      .limit(20)
      .listen(
        (rows) => ctrl.add(
          rows.map((r) => Map<String, dynamic>.from(r)).toList(),
        ),
        onError: ctrl.addError,
      );

  ref.onDispose(() {
    sub.cancel();
    ctrl.close();
  });
  return ctrl.stream;
});

/// The "Diary" timeline shown on the Adventure dashboard — most recent
/// 20 parent-logged moments. Empty state nudges the parent to log
/// something via the "My kid did this" button above.
class KidDiarySection extends ConsumerWidget {
  final String childId;
  const KidDiarySection({super.key, required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(parentLoggedMomentsProvider(childId));
    return async.when(
      loading: () => const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (rows) {
        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.lightSurface,
                border: Border.all(color: AppColors.lightBorder),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No diary entries yet',
                    style: AppTextStyles.bodyLarge(context),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap "My kid did this" to start your child\'s diary — '
                    'small moments from anywhere, kept forever.',
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'DIARY',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ).copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            for (final m in rows) _DiaryEntry(row: m),
          ],
        );
      },
    );
  }
}

class _DiaryEntry extends StatelessWidget {
  final Map<String, dynamic> row;
  const _DiaryEntry({required this.row});

  @override
  Widget build(BuildContext context) {
    final hero = (row['hero'] as String?) ?? 'rafi';
    final accent = _heroColor(hero);
    final emoji = _heroEmoji(hero);
    final text = (row['moment_text'] as String?) ?? '';
    final loggedAt = DateTime.tryParse((row['logged_at'] as String?) ?? '');
    final xp = (row['xp_awarded'] as int?) ?? 5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: AppTextStyles.body(context)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '+$xp XP',
                        style: AppTextStyles.caption(context, color: accent)
                            .copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '·',
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatRelative(loggedAt),
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _heroColor(String hero) => switch (hero) {
        'rafi' => AppColors.rafiCoral,
        'ellie' => AppColors.ellieBlue,
        'gerry' => AppColors.gerryAmber,
        'zena' => AppColors.zenaGreen,
        _ => AppColors.navy,
      };

  static String _heroEmoji(String hero) => switch (hero) {
        'rafi' => '🛡️',
        'ellie' => '❤️',
        'gerry' => '🔍',
        'zena' => '🎨',
        _ => '✨',
      };

  static String _formatRelative(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]}';
  }
}
