import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../providers/venue_config_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// One trait's XP progress bar. Reads stage thresholds from
/// venue_config.stage_thresholds_per_trait — never hardcoded. Two sizes:
/// `compact` for grid use, default for solo display.
class TraitProgressBar extends ConsumerWidget {
  /// 'rafi' | 'ellie' | 'gerry' | 'zena'
  final String trait;
  final int currentXp;
  final String currentStage;
  final bool compact;

  const TraitProgressBar({
    super.key,
    required this.trait,
    required this.currentXp,
    required this.currentStage,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final thresholdsRaw =
        (cfg['stage_thresholds_per_trait'] as List?)?.cast<dynamic>() ??
            const [0, 50, 150, 350, 700];
    final thresholds =
        thresholdsRaw.map((e) => (e as num).toInt()).toList(growable: false);

    final color = _heroColor(trait);
    final next = _nextThreshold(thresholds, currentXp);
    final prev = _prevThreshold(thresholds, currentXp);
    final progress = next == null
        ? 1.0
        : ((currentXp - prev) / (next - prev)).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: compact ? 22 : 28,
              height: compact ? 22 : 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.18),
              ),
              child: Icon(_heroIcon(trait), color: color, size: compact ? 14 : 16),
            ),
            const SizedBox(width: 8),
            Text(
              _heroName(trait),
              style: compact
                  ? AppTextStyles.caption(context)
                  : AppTextStyles.body(context),
            ),
            const Spacer(),
            Text(
              '$currentXp XP',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.lightBorder,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: compact ? 6 : 10,
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 6),
          Text(
            next == null
                ? 'Stage: ${_stageLabel(currentStage)} • Max stage'
                : 'Stage: ${_stageLabel(currentStage)} • Next at $next XP',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ],
      ],
    );
  }

  int? _nextThreshold(List<int> thresholds, int xp) {
    for (final t in thresholds) {
      if (t > xp) return t;
    }
    return null;
  }

  int _prevThreshold(List<int> thresholds, int xp) {
    var prev = 0;
    for (final t in thresholds) {
      if (t > xp) break;
      prev = t;
    }
    return prev;
  }

  static String _heroName(String trait) => switch (trait) {
        'rafi' => 'Rafi',
        'ellie' => 'Ellie',
        'gerry' => 'Gerry',
        'zena' => 'Zena',
        _ => '?',
      };

  static String _stageLabel(String stage) {
    if (stage.isEmpty) return '?';
    return stage[0].toUpperCase() + stage.substring(1);
  }

  static Color _heroColor(String trait) => switch (trait) {
        'rafi' => AppColors.rafiCoral,
        'ellie' => AppColors.ellieBlue,
        'gerry' => AppColors.gerryAmber,
        'zena' => AppColors.zenaGreen,
        _ => AppColors.lightTextSecondary,
      };

  static IconData _heroIcon(String trait) => switch (trait) {
        'rafi' => PhosphorIconsFill.shieldStar,
        'ellie' => PhosphorIconsFill.heart,
        'gerry' => PhosphorIconsFill.magnifyingGlass,
        'zena' => PhosphorIconsFill.palette,
        _ => PhosphorIconsFill.circle,
      };
}
