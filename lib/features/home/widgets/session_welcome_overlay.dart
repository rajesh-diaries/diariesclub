import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import 'welcome_video_js.dart'
    if (dart.library.html) 'welcome_video_js_web.dart';

/// Full-screen welcome overlay shown once when a session freshly starts.
///
/// Web: uses HtmlElementView with a native <video> element injected via JS.
/// Mobile: uses video_player package.
///
/// Place clips at: assets/welcome_clips/{hero}_1.mp4, {hero}_2.mp4, etc.
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

class _SessionWelcomeOverlayState extends State<SessionWelcomeOverlay> {
  VideoPlayerController? _videoController;
  bool _videoReady = false;

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

  String get _videoUrl {
    final hero = widget.favouriteHero ?? 'rafi';
    return 'assets/assets/welcome_clips/${hero}_1.mp4';
  }

  @override
  void initState() {
    super.initState();

    if (!kIsWeb) {
      _initMobileVideo();
    }

    // Auto-dismiss after 5 seconds max.
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) widget.onDismissed();
    });
  }

  Future<void> _initMobileVideo() async {
    try {
      final clipPath = HeroClipPicker.randomClip(
        widget.favouriteHero ?? 'rafi',
        maxClips: 1,
      );
      final controller = VideoPlayerController.asset(clipPath);
      await controller.initialize();
      if (!mounted) return;
      controller.setLooping(false);
      controller.setVolume(0);
      controller.play();
      setState(() => _videoReady = true);
    } catch (e) {
      debugPrint('[SessionWelcomeOverlay] mobile video failed: $e');
    }
  }

  @override
  void dispose() {
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
              // Hero avatar — flat square, no rotation
              if (kIsWeb)
                _WebVideoBox(
                  videoUrl: _videoUrl,
                  heroColor: _heroColor,
                  onEnded: widget.onDismissed,
                )
              else if (_videoReady && _videoController != null)
                _MobileVideoBox(
                  controller: _videoController!,
                  heroColor: _heroColor,
                )
              else
                _StaticBox(
                  heroAsset: _heroAsset,
                  heroColor: _heroColor,
                ),
              const SizedBox(height: 32),
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
//  Web native video — flat square, uses JS-injected <video> element.
// ---------------------------------------------------------------------------
class _WebVideoBox extends StatefulWidget {
  final String videoUrl;
  final Color heroColor;
  final VoidCallback onEnded;

  const _WebVideoBox({
    required this.videoUrl,
    required this.heroColor,
    required this.onEnded,
  });

  @override
  State<_WebVideoBox> createState() => _WebVideoBoxState();
}

class _WebVideoBoxState extends State<_WebVideoBox> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 100), () {
      jsInjectVideo(widget.videoUrl, widget.onEnded);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: widget.heroColor.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: widget.heroColor.withValues(alpha: 0.50),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.heroColor.withValues(alpha: 0.30),
            blurRadius: 40,
            spreadRadius: 8,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: const HtmlElementView(viewType: 'welcome-video-view'),
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
//  Mobile video — flat square, no rotation.
// ---------------------------------------------------------------------------
class _MobileVideoBox extends StatelessWidget {
  final VideoPlayerController controller;
  final Color heroColor;

  const _MobileVideoBox({required this.controller, required this.heroColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: heroColor.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(24),
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
//  Static fallback — flat square, NO rotation/tilt.
// ---------------------------------------------------------------------------
class _StaticBox extends StatelessWidget {
  final String heroAsset;
  final Color heroColor;

  const _StaticBox({required this.heroAsset, required this.heroColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        color: heroColor.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(24),
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
        padding: const EdgeInsets.all(12),
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

  static String randomClip(String hero, {int maxClips = 1}) {
    final idx = _random.nextInt(maxClips) + 1;
    return 'assets/welcome_clips/${hero}_$idx.mp4';
  }
}
