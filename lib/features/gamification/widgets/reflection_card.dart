import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/reflection_moments_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// One tappable moment card in the reflection grid. Three visual states:
/// untapped (white + soft border + tinted icon), tapped (trait-color
/// background + white text + light haptic + scale bounce), disabled
/// (after submit). Trait color comes from [_traitColor].
class ReflectionCardWidget extends StatelessWidget {
  final ReflectionMoment moment;
  final bool selected;
  final VoidCallback onTap;
  const ReflectionCardWidget({
    super.key,
    required this.moment,
    required this.selected,
    required this.onTap,
  });

  void _handleTap() {
    HapticFeedback.lightImpact();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final color = _traitColor(moment.primaryTrait);
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: selected ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? color : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color : AppColors.lightBorder,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.20)
                      : color.withValues(alpha: 0.18),
                ),
                child: Icon(
                  _iconFor(moment.icon),
                  color: selected ? Colors.white : color,
                  size: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                moment.displayText,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption(
                  context,
                  color: selected ? Colors.white : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Maps the seed-data icon hint (a phosphor icon name) into the
  /// PhosphorIconsRegular set. Anything unknown falls back to a star so
  /// new seed entries don't crash the screen.
  static IconData _iconFor(String? name) {
    switch (name) {
      case 'rocket':           return PhosphorIconsRegular.rocket;
      case 'arrow-fat-up':     return PhosphorIconsRegular.arrowFatUp;
      case 'shield-check':     return PhosphorIconsRegular.shieldCheck;
      case 'flag':             return PhosphorIconsRegular.flag;
      case 'arrow-clockwise':  return PhosphorIconsRegular.arrowClockwise;
      case 'star':             return PhosphorIconsRegular.star;
      case 'gift':             return PhosphorIconsRegular.gift;
      case 'hand-heart':       return PhosphorIconsRegular.handHeart;
      case 'smiley':           return PhosphorIconsRegular.smiley;
      case 'users':            return PhosphorIconsRegular.users;
      case 'heart':            return PhosphorIconsRegular.heart;
      case 'sparkle':          return PhosphorIconsRegular.sparkle;
      case 'question':         return PhosphorIconsRegular.question;
      case 'compass':          return PhosphorIconsRegular.compass;
      case 'lightbulb':        return PhosphorIconsRegular.lightbulb;
      case 'eye':              return PhosphorIconsRegular.eye;
      case 'graph':            return PhosphorIconsRegular.graph;
      case 'book-open':        return PhosphorIconsRegular.bookOpen;
      case 'puzzle-piece':     return PhosphorIconsRegular.puzzlePiece;
      case 'palette':          return PhosphorIconsRegular.palette;
      case 'feather':          return PhosphorIconsRegular.feather;
      case 'shuffle':          return PhosphorIconsRegular.shuffle;
      case 'microphone':       return PhosphorIconsRegular.microphone;
      case 'recycle':          return PhosphorIconsRegular.recycle;
      default:                 return PhosphorIconsRegular.star;
    }
  }

  static Color _traitColor(String t) => switch (t) {
        'rafi' => AppColors.rafiCoral,
        'ellie' => AppColors.ellieBlue,
        'gerry' => AppColors.gerryAmber,
        'zena' => AppColors.zenaGreen,
        _ => AppColors.gold,
      };
}
