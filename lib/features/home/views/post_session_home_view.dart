import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/hero_recap_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../gamification/widgets/hero_recap_card_widget.dart';
import 'idle_home_view.dart';

/// Recently-completed-session state. The most recent pending recap shows
/// at the top via [HeroRecapCardWidget]; if there are more pending recaps,
/// a quiet "+N more recaps" link routes to /profile/sessions where the
/// full list is filterable.
///
/// Below that, the page mirrors the idle layout so wallet, birthday, etc.
/// remain reachable.
class PostSessionHomeView extends ConsumerWidget {
  final Map<String, dynamic> session;
  const PostSessionHomeView({super.key, required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[BUG-039] PostSessionHomeView.build entered');
    final sessionId = session['id'] as String;
    final pendingAsync = ref.watch(pendingRecapsProvider);
    debugPrint('[BUG-039] pendingRecapsProvider state='
        'isLoading=${pendingAsync.isLoading} '
        'hasError=${pendingAsync.hasError} '
        'hasValue=${pendingAsync.hasValue}');
    if (pendingAsync.hasError) {
      debugPrint('[BUG-039] pendingRecapsProvider error='
          '${pendingAsync.error}');
    }
    final pending = pendingAsync.valueOrNull ?? const [];
    debugPrint('[BUG-039] pending count=${pending.length}');

    final primary = pending.firstWhere(
      (r) => r['session_id'] == sessionId,
      orElse: () => <String, dynamic>{
        'session_id': sessionId,
        'total_xp_pool': session['total_xp_earned'] ?? 0,
        'reflection_deadline': session['reflection_deadline'],
        'children': const {'name': 'Your hero'},
      },
    );
    debugPrint('[BUG-039] primary recap fields: '
        'session_id=${primary['session_id']} '
        'total_xp_pool=${primary['total_xp_pool']} '
        'reflection_deadline=${primary['reflection_deadline']} '
        'children=${primary['children']}');

    final extraRecapCount = pending
        .where((r) => r['session_id'] != primary['session_id'])
        .length;
    debugPrint('[BUG-039] extraRecapCount=$extraRecapCount');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Builder(builder: (_) {
            debugPrint('[BUG-039] building HeroRecapCardWidget');
            return HeroRecapCardWidget(recap: primary);
          }),
          if (extraRecapCount > 0) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => context.push('/profile/sessions'),
                child: Text(
                  '+$extraRecapCount more recap${extraRecapCount == 1 ? '' : 's'}',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Builder(builder: (_) {
            debugPrint('[BUG-039] building IdleHomeBody');
            return const IdleHomeBody();
          }),
        ],
      ),
    );
  }
}
