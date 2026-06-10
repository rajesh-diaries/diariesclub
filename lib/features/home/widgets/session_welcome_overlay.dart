import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Full-screen welcome overlay shown once when a session freshly starts.
///
/// Tries to play a hero video clip. If the video fails or doesn't render
/// within 1.5s, falls back to an animated hero image (pulsing glow +
/// floating sparkles) which looks intentional and delightful.
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
  VideoPlayerController? _controller;
  bool _videoReady = false;
  Timer? _endPoller;
  Timer? _safetyDismiss;

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

  static final _random = Random();
  static const _videoExtensions = ['.mp4'];

  /// Actual clip counts per hero — keep this in sync with files in
  /// assets/welcome_clips/. Missing heroes default to 0 (always fallback).
  static const _clipCounts = <String, int>{
    'gerry': 1,
    'rafi': 5,
    'zena': 4,
    'ellie': 0,
  };

  @override
  void initState() {
    super.initState();
    _initVideo();

    // If video hasn't rendered within 4s, trigger rebuild so the
    // animated hero fallback appears while video keeps trying.
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && !_videoReady) setState(() {});
    });

    // Safety dismiss after 10 seconds.
    _safetyDismiss = Timer(const Duration(seconds: 10), () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() {
    _safetyDismiss?.cancel();
    _endPoller?.cancel();
    widget.onDismissed();
  }

  Future<void> _initVideo() async {
    final hero = widget.favouriteHero ?? 'rafi';
    final count = _clipCounts[hero] ?? 0;
    if (count == 0) {
      if (mounted) setState(() {});
      return;
    }
    final idx = _random.nextInt(count) + 1;

    for (final ext in _videoExtensions) {
      final path = kIsWeb
          ? 'welcome_clips/${hero}_$idx$ext'
          : 'assets/welcome_clips/${hero}_$idx$ext';

      try {
        final controller = VideoPlayerController.asset(path);
        await controller.initialize();
        if (!mounted) {
          controller.dispose();
          return;
        }
        final size = controller.value.size;
        if (size.width <= 0 || size.height <= 0) {
          controller.dispose();
          continue;
        }
        _controller = controller;
        controller.setLooping(false);
        controller.setVolume(0);
        await controller.play();
        setState(() => _videoReady = true);

        // Poll every 300ms to detect video end — more reliable than
        // a listener that can miss the exact frame.
        _endPoller = Timer.periodic(const Duration(milliseconds: 300), (_) {
          final c = _controller;
          if (c == null || !c.value.isInitialized) return;
          final pos = c.value.position;
          final dur = c.value.duration;
          final nearEnd = dur.inMilliseconds > 0 &&
              pos.inMilliseconds >= dur.inMilliseconds - 500;
          final stoppedPlaying = !c.value.isPlaying &&
              pos > const Duration(milliseconds: 500);
          if (nearEnd || stoppedPlaying) {
            _endPoller?.cancel();
            if (mounted) _dismiss();
          }
        });
        return;
      } catch (e) {
        debugPrint('Welcome clip failed: $path — $e');
      }
    }

    // all extensions failed
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _endPoller?.cancel();
    _safetyDismiss?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background + content
        Container(
          color: AppColors.navy.withValues(alpha: 0.92),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SparkleFrame(
                  heroColor: _heroColor,
                  child: _videoReady && _controller != null
                      ? _VideoBox(
                          controller: _controller!,
                          heroColor: _heroColor,
                        )
                      : _AnimatedHeroBox(
                          heroAsset: _heroAsset,
                          heroColor: _heroColor,
                        ),
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
                // Explicit skip button — more reliable than "tap anywhere".
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _dismiss,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Text(
                        'Skip welcome',
                        style: AppTextStyles.caption(
                          context,
                          color: Colors.white.withValues(alpha: 0.90),
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 800.ms, duration: 500.ms),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Video box — shown when video loads successfully.
// ---------------------------------------------------------------------------
class _VideoBox extends StatelessWidget {
  final VideoPlayerController controller;
  final Color heroColor;

  const _VideoBox({required this.controller, required this.heroColor});

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
      child: IgnorePointer(
        child: VideoPlayer(controller),
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
//  Animated hero image — pulsing glow + floating sparkles.
//  This is the fallback when video fails, and it looks intentional.
// ---------------------------------------------------------------------------
class _AnimatedHeroBox extends StatelessWidget {
  final String heroAsset;
  final Color heroColor;

  const _AnimatedHeroBox({
    required this.heroAsset,
    required this.heroColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulsing glow behind the image.
          _PulsingGlow(color: heroColor),
          // Hero image with elastic entrance.
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: heroColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: heroColor.withValues(alpha: 0.40),
                width: 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.all(10),
            child: Image.asset(
              heroAsset,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.face,
                size: 72,
                color: Colors.white,
              ),
            ),
          )
              .animate()
              .scale(
                begin: const Offset(0.5, 0.5),
                end: const Offset(1.0, 1.0),
                duration: 700.ms,
                curve: Curves.elasticOut,
              )
              .fadeIn(duration: 400.ms),
          // Floating sparkles.
          const _FloatingSparkle(delay: Duration.zero, top: 12, right: 20),
          const _FloatingSparkle(
            delay: Duration(milliseconds: 400),
            bottom: 20,
            left: 16,
          ),
          const _FloatingSparkle(
            delay: Duration(milliseconds: 800),
            top: 40,
            left: 24,
          ),
        ],
      ),
    );
  }
}

class _PulsingGlow extends StatelessWidget {
  final Color color;
  const _PulsingGlow({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scale(
          begin: const Offset(0.85, 0.85),
          end: const Offset(1.15, 1.15),
          duration: 1400.ms,
          curve: Curves.easeInOut,
        )
        .fadeIn(duration: 300.ms);
  }
}

// ---------------------------------------------------------------------------
//  Sparkle frame — wraps any child with pulsing glow + floating stars.
//  Used around both the video and the animated hero fallback.
// ---------------------------------------------------------------------------
class _SparkleFrame extends StatelessWidget {
  final Widget child;
  final Color heroColor;

  const _SparkleFrame({
    required this.child,
    required this.heroColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _PulsingGlow(color: heroColor),
          child,
          const _FloatingSparkle(delay: Duration.zero, top: 12, right: 20),
          const _FloatingSparkle(
            delay: Duration(milliseconds: 400),
            bottom: 20,
            left: 16,
          ),
          const _FloatingSparkle(
            delay: Duration(milliseconds: 800),
            top: 40,
            left: 24,
          ),
        ],
      ),
    );
  }
}

class _FloatingSparkle extends StatelessWidget {
  final Duration delay;
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;

  const _FloatingSparkle({
    required this.delay,
    this.top,
    this.bottom,
    this.left,
    this.right,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Icon(
        Icons.star,
        color: AppColors.gold.withValues(alpha: 0.80),
        size: 18,
      )
          .animate(delay: delay)
          .fadeIn(duration: 400.ms)
          .then()
          .scale(
            begin: const Offset(0.6, 0.6),
            end: const Offset(1.2, 1.2),
            duration: 800.ms,
            curve: Curves.easeInOut,
          )
          .then()
          .scale(
            begin: const Offset(1.2, 1.2),
            end: const Offset(0.6, 0.6),
            duration: 800.ms,
            curve: Curves.easeInOut,
          )
          .slideY(begin: 0, end: -12, duration: 1600.ms),
    );
  }
}
