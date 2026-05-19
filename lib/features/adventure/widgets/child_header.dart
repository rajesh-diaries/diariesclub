import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/family_children_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/child_avatar.dart';
import '../providers/selected_adventure_child_id_provider.dart';

/// Top of the dashboard: avatar + name + Lvl badge + overall stage.
/// In multi-child families, shows a "Switch" pill that clears the
/// selectedAdventureChildId so the screen pops back to the multi-child
/// picker.
class ChildHeader extends ConsumerWidget {
  final Map<String, dynamic> child;
  const ChildHeader({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familyChildren =
        ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    final canSwitch = familyChildren.length > 1;

    final name = (child['name'] as String?) ?? '—';
    final favouriteHero = (child['favourite_hero'] as String?) ?? 'ellie';
    final level = (child['current_level'] as int?) ?? 1;
    final stage = (child['current_overall_stage'] as String?) ?? 'seedling';
    final ringColor = _heroColor(favouriteHero);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ringColor, width: 2),
            ),
            child: ChildAvatar(
              name: name,
              size: 56,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("$name's adventure", style: AppTextStyles.h2(context)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.navy.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        'Level $level',
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.navy,
                        ).copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        _stageLabel(stage),
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.gold,
                        ).copyWith(
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (canSwitch)
            TextButton.icon(
              onPressed: () => ref
                  .read(selectedAdventureChildIdProvider.notifier)
                  .clear(),
              icon: const Icon(PhosphorIconsRegular.usersThree, size: 16),
              label: const Text('Switch'),
            ),
        ],
      ),
    );
  }

  static String _stageLabel(String s) =>
      s.isEmpty ? '?' : s[0].toUpperCase() + s.substring(1);

  static Color _heroColor(String h) => switch (h) {
        'rafi' => AppColors.rafiCoral,
        'ellie' => AppColors.ellieBlue,
        'gerry' => AppColors.gerryAmber,
        'zena' => AppColors.zenaGreen,
        _ => AppColors.gold,
      };
}
