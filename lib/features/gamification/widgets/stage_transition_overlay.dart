import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// One stage-transition step (rafi: explorer → adventurer, etc.). Built
/// from the JSON returned by `reflection_submit` / `xp_credit_with_split`.
class StageTransition {
  final String trait;
  final String fromStage;
  final String toStage;

  /// Admin-uploaded artwork for the stage card (Adventure cards). Same
  /// asset doubles as the cinematic image, the card-collection art, and
  /// the physical sticker. Null until admin uploads → cinematic falls
  /// back to a Phosphor icon for the trait.
  final String? cardImageUrl;
  const StageTransition({
    required this.trait,
    required this.fromStage,
    required this.toStage,
    this.cardImageUrl,
  });

  factory StageTransition.fromJson(Map<String, dynamic> j) => StageTransition(
        trait: j['trait'] as String,
        fromStage: j['from'] as String,
        toStage: j['to'] as String,
        cardImageUrl: j['card_image_url'] as String?,
      );
}

/// Plays the trait stage-transition cinematic. Pure Flutter — no Lottie
/// dependency. Designed to swap in a Lottie file later by replacing the
/// `_HeroReveal` body without touching the orchestration.
///
/// Reduced-motion: callers should check
/// `MediaQuery.disableAnimationsOf(context)` before pushing this overlay
/// and skip straight to the split summary if true.
///
/// Each transition runs ~3.5s, advances on tap or auto-advance. After
/// the last transition fires `onComplete`.
class StageTransitionOverlay extends StatefulWidget {
  final List<StageTransition> transitions;
  final String childName;
  final VoidCallback onComplete;

  const StageTransitionOverlay({
    super.key,
    required this.transitions,
    required this.childName,
    required this.onComplete,
  });

  @override
  State<StageTransitionOverlay> createState() => _StageTransitionOverlayState();
}

class _StageTransitionOverlayState extends State<StageTransitionOverlay>
    with TickerProviderStateMixin {
  static const _stepDuration = Duration(milliseconds: 3500);

  int _currentIndex = 0;
  late final AnimationController _controller;
  Timer? _autoAdvanceTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: _stepDuration, vsync: this);
    _start();
  }

  void _start() {
    _controller
      ..reset()
      ..forward();
    HapticFeedback.mediumImpact();
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(_stepDuration, _advance);
  }

  void _advance() {
    if (!mounted) return;
    if (_currentIndex >= widget.transitions.length - 1) {
      widget.onComplete();
      return;
    }
    setState(() => _currentIndex++);
    _start();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.transitions[_currentIndex];
    final color = _heroColor(t.trait);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _advance,
      child: Container(
        color: Colors.black.withValues(alpha: 0.92),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              _Confetti(color: color, controller: _controller),
              const SizedBox(height: 8),
              _HeroReveal(
                trait: t.trait,
                color: color,
                controller: _controller,
                imageUrl: t.cardImageUrl,
              ),
              const SizedBox(height: 32),
              FadeTransition(
                opacity: CurvedAnimation(
                  parent: _controller,
                  curve: const Interval(0.30, 0.70, curve: Curves.easeOut),
                ),
                child: Column(
                  children: [
                    Text(
                      '${_heroName(t.trait)} grew up!',
                      style: AppTextStyles.h1(context, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.childName,
                      style: AppTextStyles.body(
                        context,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: color, width: 2),
                      ),
                      child: Text(
                        '${_stageLabel(t.fromStage)} → ${_stageLabel(t.toStage)}',
                        style: AppTextStyles.body(context, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (widget.transitions.length > 1)
                Text(
                  '${_currentIndex + 1} of ${widget.transitions.length}',
                  style: AppTextStyles.caption(context, color: Colors.white54),
                ),
              const SizedBox(height: 8),
              Text(
                'Tap to continue',
                style: AppTextStyles.caption(context, color: Colors.white38),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  static String _heroName(String t) => switch (t) {
        'rafi' => 'Rafi',
        'ellie' => 'Ellie',
        'gerry' => 'Gerry',
        'zena' => 'Zena',
        _ => '?',
      };

  static String _stageLabel(String s) =>
      s.isEmpty ? '?' : s[0].toUpperCase() + s.substring(1);

  static Color _heroColor(String t) => switch (t) {
        'rafi' => AppColors.rafiCoral,
        'ellie' => AppColors.ellieBlue,
        'gerry' => AppColors.gerryAmber,
        'zena' => AppColors.zenaGreen,
        _ => AppColors.gold,
      };
}

/// Hero icon scaling-in with a pop curve. Tween-based; swap with a Lottie
/// asset later by changing this widget body — the rest of the orchestration
/// is stable.
class _HeroReveal extends StatelessWidget {
  final String trait;
  final Color color;
  final AnimationController controller;
  final String? imageUrl;
  const _HeroReveal({
    required this.trait,
    required this.color,
    required this.controller,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        // Pop curve: rises from 0 → 1.15 by 0.35, settles to 1.0 by 0.55.
        final t = controller.value;
        final scale = t < 0.35
            ? Curves.easeOutBack.transform(t / 0.35) * 1.15
            : t < 0.55
                ? 1.15 - 0.15 * ((t - 0.35) / 0.20)
                : 1.0;
        final glow = (1 - (t - 0.55).abs() * 2).clamp(0.0, 1.0);
        return Container(
          width: 200,
          height: 200,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.18),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35 * glow),
                blurRadius: 60 * glow,
                spreadRadius: 8 * glow,
              ),
            ],
          ),
          child: Transform.scale(
            scale: scale,
            child: _revealChild(),
          ),
        );
      },
    );
  }

  Widget _revealChild() {
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: 160,
          height: 160,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _iconFallback(),
          loadingBuilder: (ctx, child, prog) =>
              prog == null ? child : _iconFallback(),
        ),
      );
    }
    return _iconFallback();
  }

  Widget _iconFallback() => Icon(_heroIcon(trait), color: color, size: 92);

  static IconData _heroIcon(String t) => switch (t) {
        'rafi' => PhosphorIconsFill.shieldStar,
        'ellie' => PhosphorIconsFill.heart,
        'gerry' => PhosphorIconsFill.magnifyingGlass,
        'zena' => PhosphorIconsFill.palette,
        _ => PhosphorIconsFill.circle,
      };
}

/// Minimal particle-confetti. ≤24 particles per spec — keeps low-end
/// Android smooth. Each particle is one Transform with an offset + scale.
class _Confetti extends StatefulWidget {
  final Color color;
  final AnimationController controller;
  const _Confetti({required this.color, required this.controller});

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> {
  static const _count = 24;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final r = math.Random(0xC0FFEE);
    _particles = List.generate(_count, (i) {
      final angle = r.nextDouble() * math.pi * 2;
      final distance = 60 + r.nextDouble() * 80;
      return _Particle(
        dx: math.cos(angle) * distance,
        dy: math.sin(angle) * distance - 20,
        size: 6 + r.nextDouble() * 6,
        delay: r.nextDouble() * 0.30,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 240,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (_, __) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final p in _particles) _renderParticle(p),
            ],
          );
        },
      ),
    );
  }

  Widget _renderParticle(_Particle p) {
    final raw = (widget.controller.value - p.delay) / (1 - p.delay);
    final t = raw.clamp(0.0, 1.0);
    final ease = Curves.easeOutCubic.transform(t);
    final fade = (1 - (t - 0.6).clamp(0.0, 1.0) / 0.4).clamp(0.0, 1.0);
    return Transform.translate(
      offset: Offset(p.dx * ease, p.dy * ease),
      child: Opacity(
        opacity: fade,
        child: Container(
          width: p.size,
          height: p.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

class _Particle {
  final double dx;
  final double dy;
  final double size;
  final double delay;
  const _Particle({
    required this.dx,
    required this.dy,
    required this.size,
    required this.delay,
  });
}
