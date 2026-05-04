import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Small "BRAVE / KIND / CURIOUS / CREATIVE" pill used on workshop cards
/// + workshop detail header. Shared widget so the colors and labels stay
/// in one place.
class TraitPill extends StatelessWidget {
  final String trait;
  final bool light;
  const TraitPill({super.key, required this.trait, this.light = false});

  @override
  Widget build(BuildContext context) {
    final color = _color(trait);
    final bg = light
        ? Colors.white.withValues(alpha: 0.18)
        : color.withValues(alpha: 0.18);
    final fg = light ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: light ? Colors.white54 : color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon(trait), size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            _label(trait),
            style: AppTextStyles.caption(context, color: fg).copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  static String _label(String t) => switch (t) {
        'rafi' => 'BRAVE',
        'ellie' => 'KIND',
        'gerry' => 'CURIOUS',
        'zena' => 'CREATIVE',
        _ => t.toUpperCase(),
      };

  static Color _color(String t) => switch (t) {
        'rafi' => AppColors.rafiCoral,
        'ellie' => AppColors.ellieBlue,
        'gerry' => AppColors.gerryAmber,
        'zena' => AppColors.zenaGreen,
        _ => AppColors.gold,
      };

  static IconData _icon(String t) => switch (t) {
        'rafi' => PhosphorIconsFill.shieldStar,
        'ellie' => PhosphorIconsFill.heart,
        'gerry' => PhosphorIconsFill.magnifyingGlass,
        'zena' => PhosphorIconsFill.palette,
        _ => PhosphorIconsFill.sparkle,
      };
}
