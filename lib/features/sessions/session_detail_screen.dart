import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/active_sessions_provider.dart';
import '../../core/providers/family_children_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/session_timer.dart';
import '../home/widgets/healthy_bite_reminder_banner.dart';
import '../home/widgets/hydration_reminder_banner.dart';
import 'widgets/extend_session_sheet.dart';

/// Per-session detail screen. Reached by tapping an active/grace
/// session card on the multi-session home view. Shows the session's
/// timer + Order food / Extend / Wrap-up controls without forcing the
/// user back to the QR (which is only meaningful while pending).
class SessionDetailScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  Timer? _ticker;
  // In-flight guard so a double-tap on "I'm wrapping up" can't fire
  // session_complete_batch twice.
  bool _wrappingUp = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _showExtendSheet(Map<String, dynamic> session) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (_) => ExtendSessionSheet(session: session),
    );
  }

  void _goToOrderFood() => context.go('/club');

  Future<void> _confirmWrapUp(String sessionId) async {
    if (_wrappingUp) return;
    final sessionIds = [sessionId];

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Wrap up the session?'),
        content: const Text("We'll mark this play session complete."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text("I'm wrapping up"),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // Guard again after the dialog: two taps can open two dialogs, and
    // confirming both must still fire the RPC only once.
    if (_wrappingUp) return;
    _wrappingUp = true;
    try {
      final result =
          await Supabase.instance.client.rpc<dynamic>(
                'session_complete_batch',
                params: {'p_session_ids': sessionIds},
              )
              as Map<String, dynamic>;
      if (!mounted) return;
      // Force-invalidate the active-sessions stream so the home view
      // rebuilds without this kid's "Wrapping up" card immediately.
      // Supabase realtime emission for the status='completed' update
      // can lag a few seconds, and during that window the parent sees
      // the toast confirming wrap-up while the stale card still ticks
      // on home (the bug screenshot). Manual invalidation refetches
      // directly so the UI matches the success message. Mirrors the
      // single-session wrap-up handler in session_home_view.dart.
      ref.invalidate(activeSessionsProvider);
      final completedCount = (result['completed_count'] as num?)?.toInt() ?? 1;
      final names =
          (result['child_names'] as List<dynamic>?)
              ?.map((n) => n.toString())
              .where((n) => n.isNotEmpty)
              .toList() ??
          const <String>[];
      final snackText = completedCount > 1 && names.isNotEmpty
          ? 'Sessions complete for ${names.join(", ")}! Thanks for visiting.'
          : 'Session complete! Thanks for visiting.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(snackText),
          duration: const Duration(seconds: 4),
        ),
      );
      context.go('/home');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _wrappingUp = false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't wrap up: ${e.message}")));
    } catch (e) {
      if (!mounted) return;
      _wrappingUp = false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't wrap up: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(activeSessionsProvider).valueOrNull ?? const [];
    final session = sessions.firstWhere(
      (s) => s['id'] == widget.sessionId,
      orElse: () => const <String, dynamic>{},
    );

    if (session.isEmpty) {
      // Session ended (or stream hasn't loaded yet) — bounce home.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/home');
      });
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: AppColors.navy)),
      );
    }

    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    final childId = session['child_id'] as String?;
    final child = children.firstWhere(
      (c) => c['id'] == childId,
      orElse: () => const <String, dynamic>{},
    );
    final childName = (child['name'] as String?) ?? 'Your kid';

    final expiresAtStr = session['expires_at'] as String?;
    // tryParse so a malformed/transient row from Realtime doesn't blow up
    // the screen — the timer just hides until the next refresh fixes it.
    final expiresAt = expiresAtStr == null
        ? null
        : DateTime.tryParse(expiresAtStr);
    final now = DateTime.now();
    final isGrace = expiresAt != null && expiresAt.isBefore(now);

    return Scaffold(
      backgroundColor: isGrace
          ? AppColors.sessionYellowBg
          : AppColors.lightBackground,
      appBar: AppBar(
        title: Text("$childName's session"),
        leading: IconButton(
          icon: const Icon(PhosphorIconsRegular.arrowLeft),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HealthyBiteReminderBanner(session: session),
              HydrationReminderBanner(session: session),
              const SizedBox(height: 16),
              if (expiresAt != null)
                SessionTimerWidget(
                  expiresAt: expiresAt,
                  size: TimerSize.dominant,
                ),
              const SizedBox(height: 28),
              if (isGrace) ...[
                FilledButton.icon(
                  onPressed: () => _confirmWrapUp(session['id'] as String),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(PhosphorIconsRegular.checkCircle),
                  label: const Text("I'm wrapping up"),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _showExtendSheet(session),
                  icon: const Icon(PhosphorIconsRegular.plusCircle),
                  label: const Text('Extend session'),
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: _goToOrderFood,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(PhosphorIconsRegular.coffee),
                  label: const Text('Order food'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _showExtendSheet(session),
                  icon: const Icon(PhosphorIconsRegular.plusCircle),
                  label: const Text('Extend'),
                ),
              ],
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.lightSurface,
                  border: Border.all(color: AppColors.lightBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Session details', style: AppTextStyles.h3(context)),
                    const SizedBox(height: 8),
                    _DetailRow(
                      label: 'Duration',
                      value: session['duration_minutes'] != null
                          ? '${session['duration_minutes']} min'
                          : '—',
                    ),
                    _DetailRow(
                      label: 'Payment',
                      value: (session['payment_method'] as String? ?? '—'),
                    ),
                    _DetailRow(
                      label: 'Status',
                      value: (session['status'] as String? ?? '—'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
          Text(value, style: AppTextStyles.body(context)),
        ],
      ),
    );
  }
}
