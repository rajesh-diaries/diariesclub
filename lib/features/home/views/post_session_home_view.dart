import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/hero_recap_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../gamification/widgets/hero_recap_card_widget.dart';
import '../../sessions/widgets/session_complete_overlay.dart';
import 'idle_home_view.dart';

/// Recently-completed-session state. The most recent pending recap shows
/// at the top via [HeroRecapCardWidget]; if there are more pending recaps,
/// a quiet "+N more recaps" link routes to /profile/sessions where the
/// full list is filterable.
///
/// A full-screen [SessionCompleteOverlay] celebrates the session completion
/// on first appearance, then fades to reveal the normal content underneath.
class PostSessionHomeView extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  const PostSessionHomeView({super.key, required this.session});

  @override
  ConsumerState<PostSessionHomeView> createState() =>
      _PostSessionHomeViewState();
}

class _PostSessionHomeViewState extends ConsumerState<PostSessionHomeView> {
  bool _showCelebration = true;

  void _onCelebrationDismissed() {
    if (!mounted) return;
    setState(() => _showCelebration = false);
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = widget.session['id'] as String;
    final pending = ref.watch(pendingRecapsProvider).valueOrNull ?? const [];

    final primary = pending.firstWhere(
      (r) => r['session_id'] == sessionId,
      orElse: () => <String, dynamic>{
        'session_id': sessionId,
        'total_xp_pool': widget.session['total_xp_earned'] ?? 0,
        'reflection_deadline': widget.session['reflection_deadline'],
        'children': const {'name': 'Your kid'},
      },
    );

    final extraRecapCount = pending
        .where((r) => r['session_id'] != primary['session_id'])
        .length;

    final childName =
        (primary['children'] as Map?)?['name'] as String? ?? 'Your kid';
    final xpEarned = (primary['total_xp_pool'] as int?) ??
        (widget.session['total_xp_earned'] as int?) ??
        0;

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeroRecapCardWidget(recap: primary),
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
              const IdleHomeBody(),
            ],
          ),
        ),
        if (_showCelebration)
          Positioned.fill(
            child: SessionCompleteOverlay(
              childName: childName,
              xpEarned: xpEarned,
              onDismissed: _onCelebrationDismissed,
            ),
          ),
      ],
    );
  }
}
