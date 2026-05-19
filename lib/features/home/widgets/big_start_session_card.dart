import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';

/// Premium "Start playing" banner pinned at the top of idle home.
/// Stacked layout: gold "READY WHEN YOU ARE" eyebrow on top, full-width
/// gold "Start playing" pill below. The full width gives the eyebrow
/// room to render without ellipsizing on narrow phones, and makes the
/// CTA — the most important tap target in the app — visually dominant.
/// Background is a navy gradient that slowly rotates (12s cycle) so the
/// surface feels alive without being noisy.
class BigStartSessionCard extends StatefulWidget {
  const BigStartSessionCard({super.key});

  @override
  State<BigStartSessionCard> createState() => _BigStartSessionCardState();
}

class _BigStartSessionCardState extends State<BigStartSessionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _gradientController;

  @override
  void initState() {
    super.initState();
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _gradientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _gradientController,
      builder: (context, _) {
        final angle = _gradientController.value * 2 * math.pi;
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              transform: GradientRotation(angle),
              colors: const [
                Color(0xFF2A4A92),
                AppColors.navy,
                Color(0xFF152C5C),
                AppColors.navy,
              ],
              stops: const [0.0, 0.4, 0.7, 1.0],
            ),
            border: Border.all(
              color: AppColors.gold.withValues(alpha: 0.30),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Eyebrow(),
              const SizedBox(height: 14),
              _StartButton(onTap: () => context.push('/session/start')),
            ],
          ),
        );
      },
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(PhosphorIconsFill.sparkle, color: AppColors.gold, size: 18),
        SizedBox(width: 10),
        Text(
          'READY WHEN YOU ARE',
          style: TextStyle(
            color: AppColors.gold,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),
      ],
    );
  }
}

class _StartButton extends StatelessWidget {
  final VoidCallback onTap;
  const _StartButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withValues(alpha: 0.50),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Start playing',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(width: 10),
              Icon(
                PhosphorIconsFill.playCircle,
                color: AppColors.navy,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
