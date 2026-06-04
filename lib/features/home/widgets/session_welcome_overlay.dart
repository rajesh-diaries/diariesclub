import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Full-screen welcome overlay shown once when a session freshly starts
/// (within 30s of started_at). Displays the child's favourite hero with a
/// waving animation and a personalised greeting.
///
/// Placeholder: uses flutter_animate on the static hero PNG. When custom
/// 4-5s animated clips are ready, swap the Image.asset for a VideoPlayer.
/// Supports 5-10 clips per hero; a random one is picked each time.
class SessionWelcomeOverlay extends StatefulWidget {
  final String childName;
  final String? favouriteHero;
  final VoidCallback onDismissed;

  const SessionWelcomeOverlay({
    super.key,
    required this.childName,
    this.favouriteHero,
    required this.onDismissed,
  });

  @override
  State<SessionWelcomeOverlay> createState() => _SessionWelcomeOverlayState();
}

class _SessionWelcomeOverlayState extends State<SessionWelcomeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  static const _heroAssets = <String, String>{
    'rafi': 'assets/hero/rafi.png',
    'ellie': 'assets/hero/ellie.png',
    'gerry': 'assets/hero/gerry.png',
    'zena': 'assets/hero/zena.png',
  };

  static const _heroColors = <String, Color>{
    'rafi': AppColors.rafiCoral,
    'ellie': AppColors.ellieBlue,
    'gerry': AppColors.gerryAmber,
    'zena': AppColors.zenaGreen,
  };

  static const _greetings = [
    "Let's play!",
    'Adventure time!',
    'Ready to explore?',
    "Let's have fun!",
  ];

  String get _heroAsset =>
      _heroAssets[widget.favouriteHero] ?? 'assets/hero/rafi.png';

  Color get _heroColor =>
      _heroColors[widget.favouriteHero] ?? AppColors.rafiCoral;

  String get _greeting {
    final name = widget.childName.trim();
    if (name.isEmpty) return "Let's play!";
    // Deterministic but seemingly random per session.
    final idx = name.hashCode.abs() % _greetings.length;
    return _greetings[idx];
  }

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    // Auto-dismiss after 4 seconds.
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismissed,
      child: Container(
        color: AppColors.navy.withValues(alpha: 0.92),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Hero avatar with wave animation
              AnimatedBuilder(
                animation: _waveController,
                builder: (context, child) {
                  final angle =
                      -0.15 + (_waveController.value * 0.3); // -15° to +15°
                  return Transform.rotate(
                    angle: angle,
                    origin: const Offset(0, 40), // pivot from bottom
                    child: child,
                  );
                },
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _heroColor.withValues(alpha: 0.20),
                    border: Border.all(
                      color: _heroColor.withValues(alpha: 0.50),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _heroColor.withValues(alpha: 0.30),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Image.asset(
                      _heroAsset,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.face,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
                    .animate()
                    .scale(
                      begin: const Offset(0.6, 0.6),
                      end: const Offset(1.0, 1.0),
                      duration: 600.ms,
                      curve: Curves.elasticOut,
                    )
                    .fadeIn(duration: 400.ms),
              ),
              const SizedBox(height: 32),
              // Greeting text
              Text(
                'Welcome, ${widget.childName}!',
                style: AppTextStyles.h1(context).copyWith(
                  color: Colors.white,
                  fontSize: 32,
                ),
                textAlign: TextAlign.center,
              )
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 500.ms)
                  .slideY(begin: 0.3, end: 0, duration: 500.ms),
              const SizedBox(height: 8),
              Text(
                _greeting,
                style: AppTextStyles.bodyLarge(context).copyWith(
                  color: _heroColor,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              )
                  .animate()
                  .fadeIn(delay: 400.ms, duration: 500.ms)
                  .slideY(begin: 0.2, end: 0, duration: 500.ms),
              const SizedBox(height: 48),
              // Skip hint
              Text(
                'Tap anywhere to skip',
                style: AppTextStyles.caption(
                  context,
                  color: Colors.white.withValues(alpha: 0.50),
                ),
              ).animate().fadeIn(delay: 1200.ms, duration: 600.ms),
            ],
          ),
        ),
      ),
    );
  }
}

/// Random clip selector for future video assets.
/// When clips are uploaded, place them at:
///   assets/welcome_clips/{hero}_{1..n}.mp4
/// and this helper picks a random one per session.
class HeroClipPicker {
  static final _random = Random();

  /// Returns a random clip path for the given hero.
  /// `maxClips` = how many clips exist for this hero (e.g. 5 or 10).
  static String randomClip(String hero, {int maxClips = 5}) {
    final idx = _random.nextInt(maxClips) + 1;
    return 'assets/welcome_clips/${hero}_$idx.mp4';
  }
}
