import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/server_clock_provider.dart';
import '../../../core/providers/urgent_home_prompts_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/session_timer.dart';
import '../../club/widgets/while_you_wait_card.dart';
import '../../sessions/widgets/extend_session_sheet.dart';
import '../widgets/birthday_card.dart';
import '../widgets/healthy_bite_reminder_banner.dart';
import '../widgets/hydration_reminder_banner.dart';
import '../widgets/wallet_card.dart';

/// "There's an open session" state. Adapts between two layouts depending
/// on whether other prompts are urgent enough to compete for attention:
///
///   * No urgent prompts → big dominant timer takes the top half.
///   * Urgent prompts    → compact timer row at the top, content below.
///
/// The active vs grace visual flip happens entirely inside the timer
/// widget (yellow color + "+MM:SS" prefix). The screen tint also flips,
/// so this widget itself ticks at 1Hz.
class SessionHomeView extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  const SessionHomeView({super.key, required this.session});

  @override
  ConsumerState<SessionHomeView> createState() => _SessionHomeViewState();
}

class _SessionHomeViewState extends ConsumerState<SessionHomeView> {
  Timer? _ticker;

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

  bool get _isGrace {
    final expiresStr = widget.session['expires_at'] as String?;
    final expiresAt = expiresStr == null
        ? null
        : DateTime.tryParse(expiresStr);
    if (expiresAt == null) return false;
    final serverNow = ref.read(serverClockProvider.notifier).serverNow;
    return expiresAt.isBefore(serverNow);
  }

  void _showExtendSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExtendSessionSheet(session: widget.session),
    );
  }

  // BUG-034: while a session is active, the primary action is ordering
  // food (Coffee Diaries / FIT Diaries), not re-displaying the QR. Staff
  // already scanned, the QR has no further purpose. Route to the Club tab
  // which lands on Coffee by default.
  void _goToOrderFood() {
    context.go('/club');
  }

  @override
  Widget build(BuildContext context) {
    final urgent = ref.watch(hasUrgentHomePromptsProvider);
    final isGrace = _isGrace;

    return Container(
      decoration: BoxDecoration(
        color: isGrace
            ? AppColors.sessionYellowBg
            : Theme.of(context).scaffoldBackgroundColor,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: urgent
            ? _CompactLayout(
                session: widget.session,
                isGrace: isGrace,
                onExtend: _showExtendSheet,
                onOrderFood: _goToOrderFood,
              )
            : _DominantLayout(
                session: widget.session,
                isGrace: isGrace,
                onExtend: _showExtendSheet,
                onOrderFood: _goToOrderFood,
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Dominant — no urgent prompts, big timer takes the top half.
// ---------------------------------------------------------------------------
class _DominantLayout extends StatelessWidget {
  final Map<String, dynamic> session;
  final bool isGrace;
  final VoidCallback onExtend;
  final VoidCallback onOrderFood;

  const _DominantLayout({
    required this.session,
    required this.isGrace,
    required this.onExtend,
    required this.onOrderFood,
  });

  @override
  Widget build(BuildContext context) {
    final expiresStr = session['expires_at'] as String?;
    final expiresAt =
        expiresStr == null ? null : DateTime.tryParse(expiresStr);
    if (expiresAt == null) {
      // Briefly null between session_create and the next stream tick.
      // Render a non-crashing placeholder; the realtime stream will
      // refresh the row within a second and this rebuilds correctly.
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // FEATURE-002 — complimentary Healthy Bite reminder. Self-hides
        // outside the 10-min window, when claimed, or when dismissed.
        HealthyBiteReminderBanner(session: session),
        // 20-min hydration nudge. Self-hides until session has been
        // running 20+ min, and on dismiss.
        HydrationReminderBanner(session: session),
        const SizedBox(height: 24),
        SessionTimerWidget(
          expiresAt: expiresAt,
          size: TimerSize.dominant,
        ),
        const SizedBox(height: 28),
        if (isGrace)
          _GraceCtaPair(onExtend: onExtend, sessionId: session['id'] as String)
        else
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onOrderFood,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(PhosphorIconsRegular.coffee),
                  label: const Text('Order food'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onExtend,
                  icon: const Icon(PhosphorIconsRegular.plusCircle),
                  label: const Text('Extend'),
                ),
              ),
            ],
          ),
        const SizedBox(height: 28),
        const WalletCard(compact: true),
        const SizedBox(height: 16),
        if (!isGrace) WhileYouWaitCard(session: session),
        const BirthdayCardList(),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Compact — urgent prompts visible, timer is a slim row.
// ---------------------------------------------------------------------------
class _CompactLayout extends StatelessWidget {
  final Map<String, dynamic> session;
  final bool isGrace;
  final VoidCallback onExtend;
  final VoidCallback onOrderFood;

  const _CompactLayout({
    required this.session,
    required this.isGrace,
    required this.onExtend,
    required this.onOrderFood,
  });

  @override
  Widget build(BuildContext context) {
    final expiresStr = session['expires_at'] as String?;
    final expiresAt =
        expiresStr == null ? null : DateTime.tryParse(expiresStr);
    if (expiresAt == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // FEATURE-002 — Healthy Bite reminder above the compact timer too.
        HealthyBiteReminderBanner(session: session),
        HydrationReminderBanner(session: session),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.lightSurface,
            border: Border.all(color: AppColors.lightBorder),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: SessionTimerWidget(
                  expiresAt: expiresAt,
                  size: TimerSize.compact,
                ),
              ),
              IconButton(
                onPressed: onOrderFood,
                tooltip: 'Order food',
                icon: const Icon(PhosphorIconsRegular.coffee),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!isGrace) WhileYouWaitCard(session: session),
        const BirthdayCardList(),
        const SizedBox(height: 12),
        const WalletCard(compact: true),
        const SizedBox(height: 16),
        // BUG-041 fix: in grace, the compact layout used to show only an
        // Extend button — no wrap-up CTA, leaving the customer with no way
        // to end an overrun session from this layout. Now mirrors the
        // dominant layout's _GraceCtaPair (Extend + "I'm wrapping up").
        if (isGrace)
          _GraceCtaPair(onExtend: onExtend, sessionId: session['id'] as String)
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onExtend,
              icon: const Icon(PhosphorIconsRegular.plusCircle),
              label: const Text('Add more time'),
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _GraceCtaPair extends ConsumerWidget {
  final VoidCallback onExtend;
  final String sessionId;
  const _GraceCtaPair({required this.onExtend, required this.sessionId});

  Future<void> _wrapUp(BuildContext context) async {
    debugPrint('[BUG-038] _wrapUp invoked, sessionId=$sessionId');
    // BUG-038 root cause: previous version called `Navigator.pop(context, …)`
    // inside the dialog actions, where `context` was the captured OUTER
    // (SessionHomeView) context — not the dialog's own. On Flutter web that
    // can resolve to the wrong Navigator (root vs dialog), silently fails to
    // pop, and `await showDialog<bool>` hangs forever — which is exactly the
    // symptom the BUG-038 instrumentation showed (only "_wrapUp invoked"
    // printed; "dialog returned ok=…" never reached).
    // Fix: bind the action callbacks to the dialog's own context (`dialogCtx`
    // from the builder) so the pop targets the dialog's Navigator directly.
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Wrap up the session?'),
        content: const Text('We\'ll mark this play session complete.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text("I'm wrapping up"),
          ),
        ],
      ),
    );
    debugPrint('[BUG-038] dialog returned ok=$ok mounted=${context.mounted}');
    if (ok != true || !context.mounted) {
      debugPrint('[BUG-038] dialog cancelled or context unmounted, exiting');
      return;
    }
    try {
      debugPrint('[BUG-038] calling session_complete RPC');
      final result = await Supabase.instance.client
          .rpc<dynamic>('session_complete', params: {
        'p_session_id': sessionId,
      });
      debugPrint('[BUG-038] RPC returned: $result');
      if (!context.mounted) {
        debugPrint('[BUG-038] context unmounted after RPC, skipping nav');
        return;
      }
      debugPrint('[BUG-038] scheduling post-frame snackbar');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('[BUG-038] post-frame fired, showing snackbar');
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) {
          debugPrint('[BUG-038] messenger is null, snackbar skipped');
          return;
        }
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Session complete! Thanks for visiting.'),
            duration: Duration(seconds: 4),
          ),
        );
        debugPrint('[BUG-038] snackbar shown');
      });
      debugPrint('[BUG-038] before context.go(/home)');
      context.go('/home');
      debugPrint('[BUG-038] after context.go(/home)');
    } on PostgrestException catch (e, st) {
      debugPrint('[BUG-038] PostgrestException: code=${e.code} '
          'message=${e.message} details=${e.details} hint=${e.hint}');
      debugPrint('[BUG-038] stack: $st');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't wrap up: ${e.message}")),
      );
    } catch (e, st) {
      debugPrint('[BUG-038] generic exception: $e');
      debugPrint('[BUG-038] stack: $st');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't wrap up: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onExtend,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navy,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(PhosphorIconsRegular.plusCircle),
            label: const Text('Extend session'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _wrapUp(context),
            child: const Text("I'm wrapping up"),
          ),
        ),
      ],
    );
  }
}

