import 'package:flutter/material.dart';

import '../../../core/widgets/trait_progress_bar.dart';

/// 2×2 grid of `TraitProgressBar` for a single child. Each tile is
/// passed pre-fetched XP + stage from the children row, so this widget
/// stays presentation-only (no Riverpod fetches).
class TraitProgressGrid extends StatelessWidget {
  final Map<String, dynamic> child;
  final bool compact;

  const TraitProgressGrid({
    super.key,
    required this.child,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget bar(String trait) => TraitProgressBar(
          trait: trait,
          currentXp: (child['xp_$trait'] as int?) ?? 0,
          currentStage: (child['stage_$trait'] as String?) ?? 'seedling',
          compact: compact,
        );

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: bar('rafi')),
            const SizedBox(width: 12),
            Expanded(child: bar('ellie')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: bar('gerry')),
            const SizedBox(width: 12),
            Expanded(child: bar('zena')),
          ],
        ),
      ],
    );
  }
}
