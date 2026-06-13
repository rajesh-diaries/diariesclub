import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/haptics.dart';

/// Prominent "Let's Play!" card on idle home. Uses a four-hero-color
/// moving gradient, places the hero character inside the card, and keeps
/// the primary CTA large and readable.
class BigStartSessionCard extends StatefulWidget {
  const BigStartSessionCard({super.key});

  @override
  State<BigStartSessionCard> createState() => _BigStartSessionCardState();
}

class _BigStartSessionCardState extends State<BigStartSessionCard>
    with TickerProviderStateMixin {
  late final AnimationController _gradientController;
  late final AnimationController _bounceController;
  late final String _hero;

  @override
  void initState() {
    super.initState();
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    // Random hero each time home loads — persisted for this session
    const heroes = ['rafi', 'ellie', 'gerry', 'zena'];
    _hero = heroes[DateTime.now().millisecond % heroes.length];
  }

  @override
  void dispose() {
    _gradientController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _gradientController,
      builder: (context, _) {
        final angle = _gradientController.value * 2 * math.pi;
        return SizedBox(
          height: 132,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kHomeCardRadius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                transform: GradientRotation(angle),
                colors: const [
                  AppColors.rafiCoral,
                  AppColors.ellieBlue,
                  AppColors.gerryAmber,
                  AppColors.zenaGreen,
                  AppColors.rafiCoral,
                ],
                stops: const [0.0, 0.30, 0.55, 0.80, 1.0],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.40),
                width: 2,
              ),
              boxShadow: [kHomeCardShadow(context)],
            ),
            child: Row(
              children: [
                // Left side text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Let's Play!",
                        style: AppTextStyles.cardTitle(context, color: Colors.white)
                            .copyWith(fontSize: 26),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to start a session',
                        style: AppTextStyles.cardSubtitle(
                          context,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                  ),
                ),
                // Hero centred vertically with a subtle idle bounce.
                AnimatedBuilder(
                  animation: _bounceController,
                  builder: (context, child) {
                    final t = _bounceController.value;
                    final offset = math.sin(t * math.pi) * 4.0;
                    final scale = 1.0 + math.sin(t * math.pi) * 0.04;
                    return Transform.translate(
                      offset: Offset(0, -offset),
                      child: Transform.scale(
                        scale: scale,
                        child: child,
                      ),
                    );
                  },
                  child: Image.asset(
                    'assets/hero/$_hero.png',
                    height: 64,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 8),
                // PLAY button on the right, vertically centred
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      AppHaptics.light();
                      context.push('/session/start');
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.40),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'PLAY!',
                            style: AppTextStyles.pillLabel(
                              context,
                              color: const Color(0xFF1A1A2E),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            PhosphorIconsFill.rocketLaunch,
                            color: Color(0xFF1A1A2E),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
