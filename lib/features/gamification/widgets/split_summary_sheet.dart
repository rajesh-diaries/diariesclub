import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Sheet shown after `reflection_submit` succeeds (and any stage-transition
/// cinematic has finished). 5s auto-dismiss with tap-to-skip. Two CTAs:
/// "Continue" (close → /home) and "See {child}'s adventure" (→ /adventure).
///
/// Renders the per-trait XP split. Untapped traits show as "+0 XP
/// (untapped)" so the parent can see what their selections shaped.
class SplitSummarySheet extends StatefulWidget {
  final Map<String, int> split;
  final String childName;
  final String childId;

  const SplitSummarySheet({
    super.key,
    required this.split,
    required this.childName,
    required this.childId,
  });

  @override
  State<SplitSummarySheet> createState() => _SplitSummarySheetState();
}

class _SplitSummarySheetState extends State<SplitSummarySheet> {
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _autoDismiss = Timer(const Duration(seconds: 5), _dismiss);
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted) return;
    Navigator.of(context).pop();
    context.go('/home');
  }

  void _seeAdventure() {
    _autoDismiss?.cancel();
    Navigator.of(context).pop();
    context.go('/adventure');
  }

  @override
  Widget build(BuildContext context) {
    final order = ['rafi', 'ellie', 'gerry', 'zena'];

    return GestureDetector(
      onTap: _dismiss, // tap-to-skip the auto-dismiss wait.
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Icon(
              PhosphorIconsFill.sparkle,
              color: AppColors.gold,
              size: 36,
            ),
            const SizedBox(height: 8),
            Text(
              'Saved!',
              textAlign: TextAlign.center,
              style: AppTextStyles.h2(context),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.childName} earned:',
              textAlign: TextAlign.center,
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 16),
            for (final trait in order) ...[
              _SplitRow(trait: trait, xp: widget.split[trait] ?? 0),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _dismiss,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Continue'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _seeAdventure,
              child: Text(
                "See ${widget.childName}'s adventure →",
                style: AppTextStyles.button(context, color: AppColors.navy),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  final String trait;
  final int xp;
  const _SplitRow({required this.trait, required this.xp});

  @override
  Widget build(BuildContext context) {
    final color = _heroColor(trait);
    final dimmed = xp == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: dimmed ? AppColors.lightBackground : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.20),
            ),
            child: Icon(_heroIcon(trait), color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_heroName(trait), style: AppTextStyles.body(context)),
                Text(
                  _traitLabel(trait),
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            xp == 0 ? '+0 XP (untapped)' : '+$xp XP',
            style: AppTextStyles.bodyLarge(
              context,
              color: dimmed ? AppColors.lightTextSecondary : color,
            ),
          ),
        ],
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

  static String _traitLabel(String t) => switch (t) {
        'rafi' => 'Brave',
        'ellie' => 'Kind',
        'gerry' => 'Curious',
        'zena' => 'Creative',
        _ => '',
      };

  static Color _heroColor(String t) => switch (t) {
        'rafi' => AppColors.rafiCoral,
        'ellie' => AppColors.ellieBlue,
        'gerry' => AppColors.gerryAmber,
        'zena' => AppColors.zenaGreen,
        _ => AppColors.gold,
      };

  static IconData _heroIcon(String t) => switch (t) {
        'rafi' => PhosphorIconsFill.shieldStar,
        'ellie' => PhosphorIconsFill.heart,
        'gerry' => PhosphorIconsFill.magnifyingGlass,
        'zena' => PhosphorIconsFill.palette,
        _ => PhosphorIconsFill.circle,
      };
}
