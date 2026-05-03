import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/server_clock_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Live session countdown driven by the server-clock offset (not device clock).
/// Switches to grace state once expiresAt is in the past.
class SessionTimerWidget extends ConsumerStatefulWidget {
  final DateTime expiresAt;
  const SessionTimerWidget({super.key, required this.expiresAt});

  @override
  ConsumerState<SessionTimerWidget> createState() => _SessionTimerState();
}

class _SessionTimerState extends ConsumerState<SessionTimerWidget> {
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  bool _isGrace = false;

  @override
  void initState() {
    super.initState();
    // Fire and forget — the first tick uses whatever offset we have (likely 0
    // pre-sync); subsequent ticks pick up the synced offset.
    unawaited(ref.read(serverClockProvider.notifier).sync());
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final now = ref.read(serverClockProvider.notifier).serverNow;
    final diff = widget.expiresAt.difference(now);
    setState(() {
      if (diff.isNegative) {
        _isGrace = true;
        _remaining = diff.abs();
      } else {
        _isGrace = false;
        _remaining = diff;
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          _format(_remaining),
          style: AppTextStyles.timer(
            context,
            color: _isGrace ? AppColors.warningYellow : null,
          ),
          semanticsLabel: _semanticsLabel(),
        ),
        Text(
          _isGrace ? 'Planning to extend?' : 'time remaining',
          style: AppTextStyles.caption(
            context,
            color: _isGrace ? AppColors.warningYellow : null,
          ),
        ),
      ],
    );
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _semanticsLabel() => _isGrace
      ? 'Session in grace period, ${_remaining.inMinutes} minutes overrun'
      : '${_remaining.inMinutes} minutes ${_remaining.inSeconds.remainder(60)} seconds remaining';
}
