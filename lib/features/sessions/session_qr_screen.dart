import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';

/// "Show this at the desk." Wakelock on, brightness boosted, large QR with
/// gold border. The QR payload is currently a base64-encoded JSON stub
/// containing { session_id, family_id, expires_at }; Session 10 will swap
/// this for a signed JWT against `qr_nonces` once the staff scanner exists.
class SessionQrScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const SessionQrScreen({super.key, required this.sessionId});

  @override
  ConsumerState<SessionQrScreen> createState() => _SessionQrScreenState();
}

class _SessionQrScreenState extends ConsumerState<SessionQrScreen> {
  Map<String, dynamic>? _session;
  String? _qrPayload;
  String? _error;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _boostBrightness();
    _loadSession();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    // Best-effort reset; failures are silent on platforms that don't
    // support per-app brightness.
    ScreenBrightness().resetApplicationScreenBrightness().catchError((_) {});
    super.dispose();
  }

  Future<void> _boostBrightness() async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(1.0);
    } catch (_) {
      // No-op; some emulators / desktop platforms throw here.
    }
  }

  Future<void> _loadSession() async {
    try {
      final row = await Supabase.instance.client
          .from('sessions')
          .select()
          .eq('id', widget.sessionId)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() => _error = 'Session not found.');
        return;
      }
      setState(() {
        _session = Map<String, dynamic>.from(row);
        _qrPayload = _buildPayload(_session!);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load session.");
    }
  }

  String _buildPayload(Map<String, dynamic> session) {
    // Stub payload — staff scanning is Session 10. Sessions are already
    // status='active' on creation (see session_create RPC), so the QR is
    // really just a reference for staff to look up the session in their
    // tablet app once that exists.
    final payload = {
      'v': 1,
      'session_id': session['id'],
      'family_id': session['family_id'],
      'expires_at': session['expires_at'],
    };
    return base64Url.encode(utf8.encode(jsonEncode(payload)));
  }

  Future<void> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave the QR screen?'),
        content: const Text(
          'You can come back to it any time from the Home tab while the '
          'session is active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay here'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final familyId = ref.watch(currentFamilyIdProvider);
    final session = _session;
    final iAmOwner = familyId != null &&
        session != null &&
        session['family_id'] == familyId;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Show this at the desk'),
          leading: IconButton(
            tooltip: 'Done',
            icon: const Icon(Icons.close),
            onPressed: _confirmExit,
          ),
        ),
        body: SafeArea(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: AppTextStyles.body(context),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : session == null
                  ? const Center(child: CircularProgressIndicator())
                  : _Body(
                      session: session,
                      qrPayload: _qrPayload!,
                      iAmOwner: iAmOwner,
                    ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Map<String, dynamic> session;
  final String qrPayload;
  final bool iAmOwner;
  const _Body({
    required this.session,
    required this.qrPayload,
    required this.iAmOwner,
  });

  @override
  Widget build(BuildContext context) {
    final duration = session['duration_minutes'] as int? ?? 0;
    final amount = session['amount_paise'] as int? ?? 0;
    final paymentMethod = (session['payment_method'] as String?) ?? '—';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.gold, width: 3),
              borderRadius: BorderRadius.circular(20),
              color: Colors.white,
            ),
            child: QrImageView(
              data: qrPayload,
              size: 280,
              version: QrVersions.auto,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppColors.navy,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColors.navy,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "Show this to staff. They'll scan to confirm.",
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: AppColors.lightSurface,
              border: Border.all(color: AppColors.lightBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  PhosphorIconsFill.timer,
                  color: AppColors.navy,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Text(
                  duration == 60 ? '1 hour' : '$duration min',
                  style: AppTextStyles.body(context),
                ),
                const Spacer(),
                Text(
                  '${Money.fromPaise(amount)} · $paymentMethod',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (!iAmOwner)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '(Heads up: this session is on a different account.)',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.adminRed,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
