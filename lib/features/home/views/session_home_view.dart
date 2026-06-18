import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/active_sessions_provider.dart';
import '../../../core/providers/server_clock_provider.dart';
import '../../../core/providers/urgent_home_prompts_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/session_timer.dart';
import '../../club/widgets/while_you_wait_card.dart';
import '../../sessions/widgets/extend_session_sheet.dart';
import '../widgets/birthday_card.dart';
import '../widgets/healthy_bite_reminder_banner.dart';
import '../widgets/home_banner_carousel.dart';
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
      // Show a compact branded loader instead of a full skeleton flash.
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.navy),
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
        const SizedBox(height: 20),
        const HomeBannerCarousel(),
        const SizedBox(height: 20),
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
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.navy),
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
            borderRadius: BorderRadius.circular(kHomeCardRadius),
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

  Future<void> _wrapUp(BuildContext context, WidgetRef ref) async {
    // Bind action callbacks to the dialog's own context (`dialogCtx`)
    // so Navigator.pop targets the dialog's Navigator directly.
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
    if (ok != true || !context.mounted) {
      return;
    }
    try {
      await Supabase.instance.client.rpc<dynamic>('session_complete', params: {
        'p_session_id': sessionId,
      });
      if (!context.mounted) {
        return;
      }
      // Force-invalidate the active-sessions stream so the home view
      // rebuilds into IdleHomeView immediately. Supabase realtime
      // emission for the status='completed' update can lag 1-5s on
      // slow connections, and during that window the user sees a stale
      // "wrapping up" card next to the "Session complete" snackbar —
      // exactly the symptom reported. Manual invalidation refetches
      // directly so the UI matches the success message.
      ref.invalidate(activeSessionsProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) {
          return;
        }
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Session complete! Thanks for visiting.'),
            duration: Duration(seconds: 4),
          ),
        );
      });
      context.go('/home');
    } on PostgrestException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't wrap up: ${e.message}")),
      );
    } catch (e) {
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
            onPressed: () => _wrapUp(context, ref),
            child: const Text("I'm wrapping up"),
          ),
        ),
      ],
    );
  }
}

