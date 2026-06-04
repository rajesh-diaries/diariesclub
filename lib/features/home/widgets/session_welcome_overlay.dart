import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Full-screen welcome overlay shown once when a session freshly starts.
/// Plays a short 4-5s hero video clip (MP4). Falls back to a waving
/// static hero PNG if the video fails to load or hasn't been uploaded yet.
///
/// Place clips at: assets/welcome_clips/{hero}_1.mp4, {hero}_2.mp4, etc.
/// The picker randomly selects one each time for variety.
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
  VideoPlayerController? _videoController;
  bool _videoReady = false;

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

    _initVideo();
  }

  Future<void> _initVideo() async {
    final hero = widget.favouriteHero ?? 'rafi';
    // Pick a random clip (max 1 clip per hero for now — bump when you add more).
    final clipPath = HeroClipPicker.randomClip(hero, maxClips: 1);

    try {
      final controller = VideoPlayerController.asset(clipPath);
      _videoController = controller;

      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }

      controller.setLooping(false);
      controller.setVolume(0); // Mute — no audio distraction at check-in

      // Auto-dismiss when video ends.
      controller.addListener(_onVideoStateChanged);

      setState(() => _videoReady = true);
      controller.play();
    } catch (_) {
      // Asset not found or unsupported — fall back to static image.
      if (mounted) setState(() => _videoReady = false);
    }
  }

  void _onVideoStateChanged() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;

    // Video finished playing — dismiss overlay.
    if (controller.value.position >= controller.value.duration) {
      controller.removeListener(_onVideoStateChanged);
      widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _videoController?.removeListener(_onVideoStateChanged);
    _videoController?.dispose();
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
              // Hero avatar — video if available, else waving static image
              if (_videoReady && _videoController != null)
                _VideoAvatar(
                  controller: _videoController!,
                  heroColor: _heroColor,
                )
              else
                _StaticAvatar(
                  waveController: _waveController,
                  heroAsset: _heroAsset,
                  heroColor: _heroColor,
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

// ---------------------------------------------------------------------------
//  Video avatar — plays the MP4 clip inside a circular container.
// ---------------------------------------------------------------------------
class _VideoAvatar extends StatelessWidget {
  final VideoPlayerController controller;
  final Color heroColor;

  const _VideoAvatar({required this.controller, required this.heroColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: heroColor.withValues(alpha: 0.20),
        border: Border.all(
          color: heroColor.withValues(alpha: 0.50),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: heroColor.withValues(alpha: 0.30),
            blurRadius: 40,
            spreadRadius: 8,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
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
        .fadeIn(duration: 400.ms);
  }
}

// ---------------------------------------------------------------------------
//  Static avatar fallback — waving PNG with flutter_animate.
// ---------------------------------------------------------------------------
class _StaticAvatar extends StatelessWidget {
  final AnimationController waveController;
  final String heroAsset;
  final Color heroColor;

  const _StaticAvatar({
    required this.waveController,
    required this.heroAsset,
    required this.heroColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: waveController,
      builder: (context, child) {
        final angle = -0.15 + (waveController.value * 0.3);
        return Transform.rotate(
          angle: angle,
          origin: const Offset(0, 40),
          child: child,
        );
      },
      child: Container(
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: heroColor.withValues(alpha: 0.20),
          border: Border.all(
            color: heroColor.withValues(alpha: 0.50),
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: heroColor.withValues(alpha: 0.30),
              blurRadius: 40,
              spreadRadius: 8,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Image.asset(
            heroAsset,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.face,
              size: 80,
              color: Colors.white,
            ),
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
        .fadeIn(duration: 400.ms);
  }
}

// ---------------------------------------------------------------------------
//  Random clip selector.
// ---------------------------------------------------------------------------
class HeroClipPicker {
  static final _random = Random();

  /// Returns a random clip path for the given hero.
  /// `maxClips` = how many clips exist for this hero (e.g. 1, 5, or 10).
  static String randomClip(String hero, {int maxClips = 1}) {
    final idx = _random.nextInt(maxClips) + 1;
    return 'assets/welcome_clips/${hero}_$idx.mp4';
  }
}
