import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';

/// Prominent "Let's Play!" card on idle home. Uses a four-hero-color
/// moving gradient, places the hero character inside the card, and keeps
/// the primary CTA large and readable.
class BigStartSessionCard extends StatefulWidget {
  const BigStartSessionCard({super.key});

  @override
  State<BigStartSessionCard> createState() => _BigStartSessionCardState();
}

class _BigStartSessionCardState extends State<BigStartSessionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _gradientController;
  late final String _hero;

  @override
  void initState() {
    super.initState();
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    // Random hero each time home loads — persisted for this session
    const heroes = ['rafi', 'ellie', 'gerry', 'zena'];
    _hero = heroes[DateTime.now().millisecond % heroes.length];
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
        return SizedBox(
          height: 142,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
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
              boxShadow: [
                BoxShadow(
                  color: AppColors.rafiCoral.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Left side text, kept high so it doesn't overlap the hero
                const Align(
                  alignment: Alignment(-1.0, -0.35),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Let's Play!",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                          shadows: [
                            Shadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Tap to start a session',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Hero sitting at the bottom centre of the card
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Image.asset(
                    'assets/hero/$_hero.png',
                    height: 72,
                    fit: BoxFit.contain,
                  ),
                ),
                // PLAY button bottom-right, slightly larger
                Align(
                  alignment: Alignment.bottomRight,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => context.push('/session/start'),
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
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'PLAY!',
                              style: TextStyle(
                                color: Color(0xFF1A1A2E),
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(
                              PhosphorIconsFill.rocketLaunch,
                              color: Color(0xFF1A1A2E),
                              size: 18,
                            ),
                          ],
                        ),
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
