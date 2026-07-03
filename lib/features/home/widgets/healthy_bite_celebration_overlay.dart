import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Mini celebration shown the moment staff hands over a complimentary Healthy
/// Bite (session.healthy_bite_claimed_at flips non-null via Realtime). A short,
/// delightful "thank you / enjoy your treat" beat — confetti, a gift pop, and
/// the XP the child just earned. Auto-dismisses or dismisses on tap.
class HealthyBiteCelebrationOverlay extends StatefulWidget {
  final String childName;
  final int xpEarned;
  final VoidCallback onDismissed;
  final Duration autoDismissDuration;

  const HealthyBiteCelebrationOverlay({
    super.key,
    required this.childName,
    required this.xpEarned,
    required this.onDismissed,
    this.autoDismissDuration = const Duration(milliseconds: 3600),
  });

  @override
  State<HealthyBiteCelebrationOverlay> createState() =>
      _HealthyBiteCelebrationOverlayState();
}

class _HealthyBiteCelebrationOverlayState
    extends State<HealthyBiteCelebrationOverlay> {
  late final ConfettiController _confetti;
  late final Timer _autoDismissTimer;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    _playHaptics();
    _confetti.play();
    _autoDismissTimer = Timer(widget.autoDismissDuration, _startDismiss);
  }

  Future<void> _playHaptics() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await HapticFeedback.mediumImpact();
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
        duration: const Duration(milliseconds: 350),
        onEnd: _onFadeComplete,
        child: Container(
          color: Colors.black.withValues(alpha: 0.88),
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    _buildContent(context),
                    const SizedBox(height: 40),
                    Text(
                      'Tap to continue',
                      style: AppTextStyles.caption(context,
                          color: Colors.white38),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
                Positioned.fill(
                  child: ConfettiWidget(
                    confettiController: _confetti,
                    blastDirectionality: BlastDirectionality.explosive,
                    maxBlastForce: 16,
                    minBlastForce: 4,
                    emissionFrequency: 0.03,
                    numberOfParticles: 22,
                    gravity: 0.3,
                    colors: const [
                      AppColors.gold,
                      AppColors.zenaGreen,
                      AppColors.rafiCoral,
                      AppColors.ellieBlue,
                    ],
                  ),
                ),
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
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            PhosphorIconsFill.gift,
            color: AppColors.gold,
            size: 56,
          ),
        )
            .animate()
            .fadeIn(duration: 350.ms)
            .scale(
              begin: const Offset(0.4, 0.4),
              duration: 500.ms,
              curve: Curves.easeOutBack,
            ),
        const SizedBox(height: 24),
        Text(
          'Healthy Bite unlocked!',
          textAlign: TextAlign.center,
          style: AppTextStyles.h1(context, color: Colors.white),
        )
            .animate(delay: 150.ms)
            .fadeIn(duration: 350.ms)
            .slideY(begin: 0.3, duration: 350.ms, curve: Curves.easeOutCubic),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Enjoy your treat, ${widget.childName} — our compliments!',
            textAlign: TextAlign.center,
            style: AppTextStyles.body(context, color: Colors.white70),
          ),
        ).animate(delay: 300.ms).fadeIn(duration: 350.ms),
        if (widget.xpEarned > 0) ...[
          const SizedBox(height: 24),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              '+${widget.xpEarned} XP',
              style: AppTextStyles.h2(context, color: AppColors.gold).copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          )
              .animate(delay: 450.ms)
              .fadeIn(duration: 350.ms)
              .scale(
                begin: const Offset(0.6, 0.6),
                duration: 400.ms,
                curve: Curves.easeOutBack,
              ),
        ],
      ],
    );
  }
}
