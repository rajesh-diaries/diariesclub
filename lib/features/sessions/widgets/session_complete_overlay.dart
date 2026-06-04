import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Full-screen celebration overlay shown when a session completes.
/// Plays confetti, haptics, staggered text reveal, and an animated XP counter.
/// Auto-dismisses after [autoDismissDuration] or on tap.
class SessionCompleteOverlay extends StatefulWidget {
  final String childName;
  final int xpEarned;
  final VoidCallback onDismissed;
  final Duration autoDismissDuration;

  const SessionCompleteOverlay({
    super.key,
    required this.childName,
    required this.xpEarned,
    required this.onDismissed,
    this.autoDismissDuration = const Duration(seconds: 4),
  });

  @override
  State<SessionCompleteOverlay> createState() =>
      _SessionCompleteOverlayState();
}

class _SessionCompleteOverlayState extends State<SessionCompleteOverlay>
    with SingleTickerProviderStateMixin {
  late final ConfettiController _confetti;
  late final Timer _autoDismissTimer;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(
      duration: const Duration(seconds: 3),
    );

    _playHaptics();
    _confetti.play();

    _autoDismissTimer = Timer(widget.autoDismissDuration, _startDismiss);
  }

  Future<void> _playHaptics() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await HapticFeedback.heavyImpact();
  }

  void _startDismiss() {
    if (_isDismissing || !mounted) return;
    setState(() => _isDismissing = true);
  }

  void _onFadeComplete() {
    if (_isDismissing) widget.onDismissed();
  }

  @override
  void dispose() {
    _confetti.dispose();
    _autoDismissTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _startDismiss,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: _isDismissing ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 400),
        onEnd: _onFadeComplete,
        child: Container(
          color: Colors.black.withValues(alpha: 0.88),
          child: SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 240,
                  child: ConfettiWidget(
                    confettiController: _confetti,
                    blastDirectionality: BlastDirectionality.explosive,
                    maxBlastForce: 20,
                    minBlastForce: 5,
                    emissionFrequency: 0.02,
                    numberOfParticles: 30,
                    gravity: 0.3,
                    colors: const [
                      AppColors.gold,
                      AppColors.rafiCoral,
                      AppColors.ellieBlue,
                      AppColors.gerryAmber,
                      AppColors.zenaGreen,
                    ],
                  ),
                ),
                const Spacer(),
                _buildContent(context),
                const Spacer(),
                Text(
                  'Tap to continue',
                  style: AppTextStyles.caption(
                    context,
                    color: Colors.white38,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          PhosphorIconsFill.sparkle,
          color: AppColors.gold,
          size: 64,
        )
            .animate()
            .fadeIn(duration: 400.ms)
            .scale(
              begin: const Offset(0.4, 0.4),
              duration: 500.ms,
              curve: Curves.easeOutBack,
            ),
        const SizedBox(height: 24),
        Text(
          'Mission Accomplished!',
          style: AppTextStyles.h1(context, color: Colors.white),
        )
            .animate(delay: 200.ms)
            .fadeIn(duration: 400.ms)
            .slideY(
              begin: 0.3,
              duration: 400.ms,
              curve: Curves.easeOutCubic,
            ),
        const SizedBox(height: 8),
        Text(
          '${widget.childName} had an amazing time',
          style: AppTextStyles.body(context, color: Colors.white70),
        ).animate(delay: 400.ms).fadeIn(duration: 400.ms),
        const SizedBox(height: 32),
        _XpCounter(targetXp: widget.xpEarned),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _startDismiss,
          icon: const Icon(PhosphorIconsFill.playCircle),
          label: const Text('See the recap'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: AppColors.navy,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          ),
        )
            .animate(delay: 800.ms)
            .fadeIn(duration: 400.ms)
            .slideY(
              begin: 0.2,
              duration: 400.ms,
              curve: Curves.easeOutCubic,
            ),
      ],
    );
  }
}

class _XpCounter extends StatefulWidget {
  final int targetXp;
  const _XpCounter({required this.targetXp});

  @override
  State<_XpCounter> createState() => _XpCounterState();
}

class _XpCounterState extends State<_XpCounter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final eased = Curves.easeOutCubic.transform(_ctrl.value);
        final current = (widget.targetXp * eased).round();
        return Text(
          '+$current XP',
          style: AppTextStyles.h2(context, color: AppColors.gold).copyWith(
            fontWeight: FontWeight.w900,
            fontSize: 48,
          ),
        );
      },
    );
  }
}
