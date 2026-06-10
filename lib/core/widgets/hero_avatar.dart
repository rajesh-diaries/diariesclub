import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Displays a hero character image in a rounded-square "squircle" shape.
///
/// This is the canonical way to show hero avatars throughout the app.
/// We intentionally use a rounded square (not a circle) because the source
/// PNGs are square compositions with solid backgrounds — clipping them to
/// a circle cuts off the character art (e.g. Gerry's long neck, Rafi's
/// propeller). The rounded square preserves the full image while still
/// looking friendly and modern (iOS-app-icon style).
class HeroAvatar extends StatelessWidget {
  final String? heroId;
  final String? fallbackName;
  final double size;
  final bool selected;

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

  const HeroAvatar({
    super.key,
    this.heroId,
    this.fallbackName,
    this.size = 56,
    this.selected = false,
  });

  String? get _asset => _heroAssets[heroId];
  Color get _color => _heroColors[heroId] ?? AppColors.gold;

  String get _initial {
    final name = fallbackName?.trim() ?? '';
    if (name.isEmpty) return '?';
    return name.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    // Subtle rounding — like an iOS app icon, not a circle.
    // Circles clip the character art (Gerry's neck, Rafi's propeller).
    final radius = size * 0.18;
    final asset = _asset;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected ? _color : _color.withValues(alpha: 0.40),
          width: selected ? 3 : 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      // Small inset padding so the image doesn't touch the border.
      padding: EdgeInsets.all(size * 0.06),
      child: asset != null
          ? Image.asset(
              asset,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() {
    return Center(
      child: Text(
        _initial,
        style: TextStyle(
          color: _color,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}
