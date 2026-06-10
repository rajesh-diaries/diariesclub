import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
/// containing { session_id, family_id, expires_at }; signed-JWT replacement
/// is tracked as BUG-002 (deferred to v1.1).
///
/// Session 14 / BUG-004 — hold-then-charge:
///   Customer-initiated wallet sessions are created in status='pending'.
///   This screen renders a countdown ("Auto-cancels in MM:SS") and a
///   cancel-now button while pending. When staff scans the QR,
///   qr_scan_validate flips status to 'active' and converts the wallet
///   hold to a debit. Polling every 2s catches the flip and re-renders.
///   If the customer doesn't get scanned within
///   venue_config.session_pre_scan_timeout_minutes (default 15), the
///   session-autocancel-pending cron flips status to 'cancelled_pre_scan'
///   and releases the hold; we detect that in the same poll.
///
/// Clock-skew note: the countdown is derived from session.created_at
/// (server-stamped) + the venue timeout, then subtracted from
/// DateTime.now(). On NTP-synced devices the visual countdown is within
/// a couple of seconds of the server's actual deadline. If a client
/// clock is far off, the *visual* countdown drifts but the server-side
/// cancellation is unaffected — the next status poll catches the
/// real state. No money math runs on the client.
///
/// Batch mode: when [batchSessionIds] is non-empty, the QR payload
/// includes batch_mode=true so one scan checks in all kids.
class SessionQrScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final List<String> batchSessionIds;
  const SessionQrScreen({
    super.key,
    required this.sessionId,
    this.batchSessionIds = const [],
  });

  @override
  ConsumerState<SessionQrScreen> createState() => _SessionQrScreenState();
}

class _SessionQrScreenState extends ConsumerState<SessionQrScreen> {
  Map<String, dynamic>? _session;
  String? _qrPayload;
  String? _error;
  String _childName = '';
  // Batch mode: names of all children in the batch, in order.
  final List<String> _batchChildNames = [];

  StreamSubscription<List<Map<String, dynamic>>>? _statusSub;
  Timer? _countdownTick;
  Duration _remaining = Duration.zero;
  DateTime? _deadline;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _boostBrightness();
    _loadSession();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _countdownTick?.cancel();
    WakelockPlus.disable();
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

      final session = Map<String, dynamic>.from(row);
      final status = session['status'] as String?;

      // Fetch child's name so the QR screen can personalise the title.
      final childId = session['child_id'] as String?;
      if (childId != null) {
        try {
          final childRow = await Supabase.instance.client
              .from('children')
              .select('name')
              .eq('id', childId)
              .maybeSingle();
          _childName = (childRow?['name'] as String?) ?? '';
        } catch (_) {
          // Best-effort; leave _childName empty if fetch fails.
        }
      }

      // Batch mode: fetch names for all children in the batch.
      if (widget.batchSessionIds.isNotEmpty) {
        try {
          final rows = await Supabase.instance.client
              .from('sessions')
              .select('id, child_id')
              .inFilter('id', widget.batchSessionIds);
          final childIds = rows
              .map((r) => r['child_id'] as String?)
              .whereType<String>()
              .toList();
          if (childIds.isNotEmpty) {
            final childrenRows = await Supabase.instance.client
                .from('children')
                .select('id, name')
                .inFilter('id', childIds);
            final nameMap = {
              for (final r in childrenRows)
                r['id'] as String: r['name'] as String? ?? '—',
            };
            _batchChildNames.clear();
            for (final sid in widget.batchSessionIds) {
              final row = rows.firstWhere(
                (r) => r['id'] == sid,
                orElse: () => <String, dynamic>{},
              );
              final cid = row['child_id'] as String?;
              if (cid != null && nameMap.containsKey(cid)) {
                _batchChildNames.add(nameMap[cid]!);
              }
            }
          }
        } catch (_) {
          // Best-effort; batch names stay empty if fetch fails.
        }
      }

      // Pending sessions need a deadline. Pull venue timeout once, derive
      // deadline from server-stamped created_at, then run a 1Hz tick
      // locally + 2s status poll for state change detection.
      if (status == 'pending') {
        final venueId = session['venue_id'] as String?;
        if (venueId != null) {
          final cfg = await Supabase.instance.client
              .from('venue_config')
              .select('session_pre_scan_timeout_minutes')
              .eq('venue_id', venueId)
              .maybeSingle();
          if (!mounted) return;
          final timeoutMin =
              (cfg?['session_pre_scan_timeout_minutes'] as int?) ?? 15;
          final createdAt = DateTime.tryParse(
                (session['created_at'] as String?) ?? '',
              )?.toUtc() ??
              DateTime.now().toUtc();
          _deadline = createdAt.add(Duration(minutes: timeoutMin));
          _tickCountdown(); // seed _remaining
          _startTickers();
        }
      }

      setState(() {
        _session = session;
        _qrPayload = _buildPayload(session);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load session.");
    }
  }

  String _buildTitleText() {
    if (_batchChildNames.isNotEmpty) {
      if (_batchChildNames.length == 2) {
        return "${_batchChildNames[0].split(' ').first} & ${_batchChildNames[1].split(' ').first}'s Pass";
      } else if (_batchChildNames.length > 2) {
        final firsts = _batchChildNames.map((n) => n.split(' ').first).toList();
        return '${firsts.take(firsts.length - 1).join(", ")} & ${firsts.last}\'s Pass';
      }
    }
    if (_childName.isEmpty) return 'Play Pass';
    return "${_childName.split(' ').first}'s Pass";
  }

  void _startTickers() {
    _countdownTick?.cancel();
    _statusSub?.cancel();
    _countdownTick =
        Timer.periodic(const Duration(seconds: 1), (_) => _tickCountdown());
    // `sessions` is in supabase_realtime — subscribe to this row so the
    // pending → active / cancelled_pre_scan transition arrives within a
    // second of staff scanning or the autocancel cron firing, with no
    // 2s polling overhead.
    _statusSub = Supabase.instance.client
        .from('sessions')
        .stream(primaryKey: ['id'])
        .eq('id', widget.sessionId)
        .listen(_onStatusRows);
  }

  void _stopTickers() {
    _countdownTick?.cancel();
    _statusSub?.cancel();
    _countdownTick = null;
    _statusSub = null;
  }

  void _onStatusRows(List<Map<String, dynamic>> rows) {
    if (!mounted || _session == null || rows.isEmpty) return;
    final row = rows.first;
    final newStatus = row['status'] as String?;
    final oldStatus = _session?['status'] as String?;
    if (newStatus == oldStatus) return;
    setState(() {
      _session = {..._session!, ...Map<String, dynamic>.from(row)};
    });
    if (newStatus != 'pending') {
      _stopTickers();
      if (oldStatus == 'pending') {
        _autoDismissTo(newStatus);
      }
    }
  }

  /// Set once we kick off the auto-cancel on countdown zero, so the 1Hz
  /// tick doesn't keep firing the RPC every second after the deadline.
  bool _autoCancelFired = false;

  void _tickCountdown() {
    if (_deadline == null) return;
    final remaining = _deadline!.difference(DateTime.now().toUtc());
    if (!mounted) return;
    setState(() {
      _remaining = remaining.isNegative ? Duration.zero : remaining;
    });
    // When the timer reaches zero we used to just sit on "Auto-cancels
    // in 00:00" until the server-side cron tick (up to ~1 min later)
    // flipped status. During that gap home stayed on "Awaiting check-in"
    // and tapping Cancel sometimes raced with the cron. Fire the cancel
    // RPC client-side immediately so the server flips status now and
    // home + this screen converge within ~500ms. Cron remains the safety
    // net if the client crashes or loses connection.
    if (remaining.isNegative &&
        !_autoCancelFired &&
        (_session?['status'] as String?) == 'pending') {
      _autoCancelFired = true;
      _autoCancelOnTimeout();
    }
  }

  Future<void> _autoCancelOnTimeout() async {
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'session_cancel_pending',
        params: {'p_session_id': widget.sessionId},
      );
    } catch (_) {
      // Best-effort — the server-side cron is the safety net. Let the
      // realtime listener flip the screen state when it does eventually
      // catch up.
    }
  }

  // _pollStatus removed — replaced by realtime stream in _startTickers.

  Future<void> _autoDismissTo(String? newStatus) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = newStatus == 'active'
        ? 'Session started! Have fun ✨'
        : 'Session cancelled, hold released.';
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1400),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    context.go('/home');
  }

  String _buildPayload(Map<String, dynamic> session) {
    // Stub payload — signed-JWT replacement is BUG-002 (v1.1). The
    // session_id is unguessable and qr_scan_validate enforces single-use
    // via staff_scanned_at, so v1 trust holds for friends-and-family beta.
    final isBatch = widget.batchSessionIds.isNotEmpty;
    final payload = {
      'v': 1,
      'session_id': session['id'],
      'family_id': session['family_id'],
      'expires_at': session['expires_at'],
      if (isBatch) 'batch_mode': true,
      if (isBatch) 'batch_session_ids': widget.batchSessionIds,
    };
    return base64Url.encode(utf8.encode(jsonEncode(payload)));
  }

  Future<void> _cancelNow() async {
    if (_cancelling) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel this session?'),
        content: const Text(
          "We'll release the hold on your wallet. You can start again "
          'whenever you like.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text("Don't cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.adminRed),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Cancel session'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'session_cancel_pending',
        params: {'p_session_id': widget.sessionId},
      );
      if (!mounted) return;
      _stopTickers();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session cancelled, hold released.')),
      );
      context.go('/home');
    } on PostgrestException catch (e) {
      // If the auto-cancel cron (or the on-timeout client cancel) beat us
      // to it, the RPC returns success — we won't land here. This catch
      // is for unexpected server errors only.
      if (!mounted) return;
      setState(() => _cancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't cancel: ${e.message}")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't cancel: $e")),
      );
    }
  }

  Future<void> _confirmExit() async {
    final status = _session?['status'] as String?;
    if (status == 'pending') {
      // From the pending state, exit means "leave the QR open in the
      // background" — explain that the cron will auto-cancel if no scan.
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Leave the QR screen?'),
          content: Text(
            "If you don't get scanned within the timeout, your hold will "
            'be released automatically. You can come back from Home while '
            'the session is still pending.',
            style: AppTextStyles.body(context),
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
      return;
    }
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
    final status = session?['status'] as String?;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: AppColors.navy,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            status == 'cancelled_pre_scan'
                ? 'Session cancelled'
                : _buildTitleText(),
          ),
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
                  : status == 'cancelled_pre_scan'
                      ? _CancelledBody(onHome: () => context.go('/home'))
                      : _Body(
                          session: session,
                          qrPayload: _qrPayload!,
                          iAmOwner: iAmOwner,
                          isPending: status == 'pending',
                          remaining: _remaining,
                          cancelling: _cancelling,
                          onCancelNow: _cancelNow,
                          childName: _childName,
                          batchChildNames: _batchChildNames,
                        ),
        ),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  final Map<String, dynamic> session;
  final String qrPayload;
  final bool iAmOwner;
  final bool isPending;
  final Duration remaining;
  final bool cancelling;
  final VoidCallback onCancelNow;
  final String childName;
  final List<String> batchChildNames;

  const _Body({
    required this.session,
    required this.qrPayload,
    required this.iAmOwner,
    required this.isPending,
    required this.remaining,
    required this.cancelling,
    required this.onCancelNow,
    required this.childName,
    this.batchChildNames = const [],
  });

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> with SingleTickerProviderStateMixin {
  late final ConfettiController _confetti;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _confetti.play();
  }

  @override
  void dispose() {
    _confetti.dispose();
    _pulse.dispose();
    super.dispose();
  }

  String _formatRemaining(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _buildGreeting() {
    final names = widget.batchChildNames.isNotEmpty
        ? widget.batchChildNames
        : (widget.childName.isEmpty ? <String>[] : [widget.childName]);
    if (names.isEmpty) return "You're all set!";
    if (names.length == 1) return '${names.first} is ready to play!';
    if (names.length == 2) {
      return '${names[0]} & ${names[1]} are ready to play!';
    }
    final firsts = names.take(names.length - 1).join(', ');
    return '$firsts & ${names.last} are ready to play!';
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.session['duration_minutes'] as int? ?? 0;
    final amount = widget.session['amount_paise'] as int? ?? 0;
    final paymentMethod = (widget.session['payment_method'] as String?) ?? '—';

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 4),
              // Sparkle icon
              const Icon(
                PhosphorIconsFill.sparkle,
                color: AppColors.gold,
                size: 32,
              )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .scale(
                    begin: const Offset(0.5, 0.5),
                    duration: 500.ms,
                    curve: Curves.easeOutBack,
                  ),
              const SizedBox(height: 6),
              // Title — personalised with kid's name(s) when available.
              Text(
                _buildGreeting(),
                style: AppTextStyles.h2(context, color: Colors.white),
                textAlign: TextAlign.center,
              )
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 400.ms)
                  .slideY(
                    begin: 0.3,
                    duration: 400.ms,
                    curve: Curves.easeOutCubic,
                  ),
              const SizedBox(height: 2),
              Text(
                'Show this at the desk to check in.',
                style: AppTextStyles.body(context, color: Colors.white70),
                textAlign: TextAlign.center,
              ).animate(delay: 300.ms).fadeIn(duration: 400.ms),
              const SizedBox(height: 12),
              // Pulsing QR card
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) {
                  final glow = _pulse.value;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.gold,
                        width: 2 + glow * 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.2 + 0.3 * glow),
                          blurRadius: 20 + 30 * glow,
                          spreadRadius: 2 + 6 * glow,
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: widget.qrPayload,
                      size: 220,
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
                  );
                },
              ),
              const SizedBox(height: 16),
          if (widget.isPending) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.10),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.40),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    PhosphorIconsFill.timer,
                    color: AppColors.gold,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Auto-cancels in ${_formatRemaining(widget.remaining)}',
                      style: AppTextStyles.body(context).copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
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
                  '${Money.fromPaise(amount)} · ${widget.isPending ? 'on hold' : paymentMethod}',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (widget.isPending) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(PhosphorIconsRegular.xCircle),
                label: Text(widget.cancelling ? 'Cancelling…' : 'Cancel session'),
                onPressed: widget.cancelling ? null : widget.onCancelNow,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.adminRed,
                  side: const BorderSide(color: AppColors.adminRed),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
          if (!widget.iAmOwner)
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
          const SizedBox(height: 24),
        ],
      ),
    ),
    // Confetti floats over everything without pushing content down.
    Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 180,
      child: ConfettiWidget(
        confettiController: _confetti,
        blastDirectionality: BlastDirectionality.explosive,
        maxBlastForce: 15,
        minBlastForce: 3,
        emissionFrequency: 0.03,
        numberOfParticles: 20,
        gravity: 0.4,
        colors: const [
          AppColors.gold,
          AppColors.rafiCoral,
          AppColors.ellieBlue,
          AppColors.gerryAmber,
          AppColors.zenaGreen,
        ],
      ),
    ),
  ],
);
  }
}

class _CancelledBody extends StatelessWidget {
  final VoidCallback onHome;
  const _CancelledBody({required this.onHome});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          const Icon(
            PhosphorIconsFill.xCircle,
            color: AppColors.adminRed,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'Session cancelled',
            style: AppTextStyles.h2(context, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            "We didn't get a scan in time, so your wallet hold has been "
            'released. Start a new session whenever you like.',
            style: AppTextStyles.body(
              context,
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton(onPressed: onHome, child: const Text('Back to Home')),
        ],
      ),
    );
  }
}
