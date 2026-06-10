import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Compact "Let's Play!" card on idle home. Warm coral-amber gradient
/// with a hero character jumping above the GO button and sparkle stars.
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
    final heroes = const ['rafi', 'ellie', 'gerry', 'zena'];
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
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Main card
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  transform: GradientRotation(angle),
                  colors: const [
                    Color(0xFFFF8A65), // warm coral
                    Color(0xFFFFB74D), // amber
                    Color(0xFFFFD54F), // soft gold
                    Color(0xFFFFB74D),
                  ],
                  stops: const [0.0, 0.35, 0.7, 1.0],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.40),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF8A65).withValues(alpha: 0.30),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Left side text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Let's Play!",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap to start a session',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Action button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => context.push('/session/start'),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
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
                                color: Color(0xFFE85D3F),
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(
                              PhosphorIconsFill.rocketLaunch,
                              color: Color(0xFFE85D3F),
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
            // Hero standing on the top-right corner of the card
            Positioned(
              top: -34,
              right: 8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Sparkle stars going up above the hero
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _sparkle(10, -8),
                      const SizedBox(width: 20),
                      _sparkle(8, 4),
                    ],
                  ),
                  // Hero standing upright on the corner
                  Image.asset(
                    'assets/hero/$_hero.png',
                    height: 48,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sparkle(double size, double offsetX) {
    return Transform.translate(
      offset: Offset(offsetX, 0),
      child: Icon(
        PhosphorIconsFill.sparkle,
        color: Colors.white.withValues(alpha: 0.90),
        size: size,
      ),
    );
  }
}
