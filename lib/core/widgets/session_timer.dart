import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/server_clock_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Three target sizes for the session timer. Home picks one based on whether
/// any other prompts are competing for screen real estate.
enum TimerSize { compact, regular, dominant }

/// Live session countdown driven by the server-clock offset (not device
/// clock — a tampered device clock can't visually extend a session).
///
/// Switches to a grace presentation once expiresAt is in the past. The DB
/// status doesn't flip active → grace; that distinction is purely visual
/// and computed every second by this widget.
class SessionTimerWidget extends ConsumerStatefulWidget {
  final DateTime expiresAt;
  final TimerSize size;
  final String? childName;

  const SessionTimerWidget({
    super.key,
    required this.expiresAt,
    this.size = TimerSize.dominant,
    this.childName,
  });

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
    // First tick uses whatever offset we have (likely zero pre-sync);
    // subsequent ticks pick up the synced offset. The microtask delays
    // the sync RPC by one frame so it doesn't block initial paint.
    Future<void>.microtask(
      () => ref.read(serverClockProvider.notifier).sync(),
    );
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final now = ref.read(serverClockProvider.notifier).serverNow;
    final diff = widget.expiresAt.difference(now);
    setState(() {
      _isGrace = diff.isNegative;
      _remaining = _isGrace ? diff.abs() : diff;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _isGrace ? AppColors.warningYellow : AppColors.navy;
    final label = _format(_remaining, _isGrace);
    final semantics = _semanticsLabel();

    switch (widget.size) {
      case TimerSize.compact:
        return _Compact(
          label: label,
          color: color,
          isGrace: _isGrace,
          childName: widget.childName,
          semantics: semantics,
        );
      case TimerSize.regular:
        return _Regular(
          label: label,
          color: color,
          isGrace: _isGrace,
          semantics: semantics,
        );
      case TimerSize.dominant:
        return _Dominant(
          label: label,
          color: color,
          isGrace: _isGrace,
          semantics: semantics,
        );
    }
  }

  /// MM:SS for active, +MM:SS for grace. Hours show only past 1h.
  static String _format(Duration d, bool isGrace) {
    final hh = d.inHours;
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final body = hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';
    return isGrace ? '+$body' : body;
  }

  String _semanticsLabel() {
    final m = _remaining.inMinutes;
    final s = _remaining.inSeconds.remainder(60);
    return _isGrace
        ? 'Session in grace period, $m minutes $s seconds overrun'
        : '$m minutes $s seconds remaining';
  }
}

class _Compact extends StatelessWidget {
  final String label;
  final Color color;
  final bool isGrace;
  final String? childName;
  final String semantics;
  const _Compact({
    required this.label,
    required this.color,
    required this.isGrace,
    required this.childName,
    required this.semantics,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantics,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          if (childName != null) ...[
            Text(childName!, style: AppTextStyles.bodyLarge(context)),
            const SizedBox(width: 8),
            Text('·',
                style: AppTextStyles.bodyLarge(
                  context,
                  color: AppColors.lightTextSecondary,
                )),
            const SizedBox(width: 8),
          ],
          Text(label, style: AppTextStyles.bodyLarge(context, color: color)),
          if (isGrace) ...[
            const SizedBox(width: 8),
            Text('overtime',
                style: AppTextStyles.caption(context, color: color)),
          ],
        ],
      ),
    );
  }
}

class _Regular extends StatelessWidget {
  final String label;
  final Color color;
  final bool isGrace;
  final String semantics;
  const _Regular({
    required this.label,
    required this.color,
    required this.isGrace,
    required this.semantics,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantics,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTextStyles.h1(context, color: color)),
          const SizedBox(height: 4),
          Text(
            isGrace ? 'over time' : 'time remaining',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dominant extends StatelessWidget {
  final String label;
  final Color color;
  final bool isGrace;
  final String semantics;
  const _Dominant({
    required this.label,
    required this.color,
    required this.isGrace,
    required this.semantics,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantics,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.timer(context, color: color),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isGrace ? 'Planning to extend?' : 'time remaining',
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
