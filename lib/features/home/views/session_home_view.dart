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
import '../widgets/healthy_bite_widget.dart';
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
    final expiresAt = DateTime.parse(widget.session['expires_at'] as String);
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

  void _goToQr() {
    final id = widget.session['id'] as String;
    context.push('/session/qr/$id');
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
                onShowQr: _goToQr,
              )
            : _DominantLayout(
                session: widget.session,
                isGrace: isGrace,
                onExtend: _showExtendSheet,
                onShowQr: _goToQr,
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
  final VoidCallback onShowQr;

  const _DominantLayout({
    required this.session,
    required this.isGrace,
    required this.onExtend,
    required this.onShowQr,
  });

  @override
  Widget build(BuildContext context) {
    final expiresAt = DateTime.parse(session['expires_at'] as String);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                child: OutlinedButton.icon(
                  onPressed: onShowQr,
                  icon: const Icon(PhosphorIconsRegular.qrCode),
                  label: const Text('Show QR'),
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
        const HealthyBiteWidget(),
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
  final VoidCallback onShowQr;

  const _CompactLayout({
    required this.session,
    required this.isGrace,
    required this.onExtend,
    required this.onShowQr,
  });

  @override
  Widget build(BuildContext context) {
    final expiresAt = DateTime.parse(session['expires_at'] as String);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                onPressed: onShowQr,
                tooltip: 'Show QR',
                icon: const Icon(PhosphorIconsRegular.qrCode),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!isGrace) WhileYouWaitCard(session: session),
        const BirthdayCardList(),
        const HealthyBiteWidget(),
        const SizedBox(height: 12),
        const WalletCard(compact: true),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onExtend,
            icon: const Icon(PhosphorIconsRegular.plusCircle),
            label: Text(isGrace ? 'Extend session' : 'Add more time'),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Wrap up the session?'),
        content: const Text('We\'ll mark this play session complete.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("I'm wrapping up"),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    // session_complete is callable by the parent; the RPC enforces authority.
    try {
      await Supabase.instance.client
          .rpc<Map<String, dynamic>>('session_complete',
              params: {'p_session_id': sessionId});
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't wrap up. Please try again.")),
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

