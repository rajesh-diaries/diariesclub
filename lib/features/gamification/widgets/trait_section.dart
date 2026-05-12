import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/reflection_moments_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import 'reflection_card.dart';
import 'reflection_more_moments_sheet.dart';

/// Trait header + grid of preset moments on the reflection screen.
///
/// Layout: 5 preset cards in a 3-column grid, with slot 6 (bottom-right)
/// reserved for a "+ More moments" tile that opens the parent-log sheet
/// pre-pinned to this trait — giving the parent access to the wider pool
/// of moments plus a free-text "write our own" entry.
class TraitSection extends StatelessWidget {
  final String trait;
  final List<ReflectionMoment> cards;
  final Set<String> selectedTags;
  final ValueChanged<String> onToggle;
  final String childId;
  final String childName;
  final Set<String> customMoments;
  final ValueChanged<Set<String>> onCustomMomentsChanged;

  const TraitSection({
    super.key,
    required this.trait,
    required this.cards,
    required this.selectedTags,
    required this.onToggle,
    required this.childId,
    required this.childName,
    required this.customMoments,
    required this.onCustomMomentsChanged,
  });

  static const _presetSlots = 5;

  @override
  Widget build(BuildContext context) {
    final color = _heroColor(trait);
    final iconData = _heroIcon(trait);
    // First N cards as presets; slot N+1 is the "+ More" tile.
    final presets = cards.take(_presetSlots).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.18),
                ),
                child: Icon(iconData, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                _heroName(trait).toUpperCase(),
                style: AppTextStyles.caption(context, color: color)
                    .copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 6),
              Text(
                '· ${_traitLabel(trait).toLowerCase()}',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Total tiles to render = presets + 1 "+ More" tile. Chunked
          // into rows of 3. IntrinsicHeight per row keeps card heights
          // aligned without forcing infinite vertical constraints.
          for (int start = 0; start < _presetSlots + 1; start += 3) ...[
            if (start > 0) const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List<Widget>.generate(3, (i) {
                  final tileIndex = start + i;
                  final spacer = i > 0
                      ? const SizedBox(width: 10)
                      : const SizedBox.shrink();
                  // The very last tile in the grid is the "+ More" CTA.
                  final isMoreTile = tileIndex == _presetSlots;

                  if (tileIndex > _presetSlots) {
                    return Expanded(
                      child: Row(children: [spacer, const Spacer()]),
                    );
                  }
                  if (isMoreTile) {
                    return Expanded(
                      child: Row(children: [
                        spacer,
                        Expanded(
                          child: _MoreMomentsTile(
                            accent: color,
                            onTap: () => _openMoreSheet(context),
                          ),
                        ),
                      ]),
                    );
                  }
                  if (tileIndex >= presets.length) {
                    return Expanded(
                      child: Row(children: [spacer, const Spacer()]),
                    );
                  }
                  final card = presets[tileIndex];
                  return Expanded(
                    child: Row(children: [
                      spacer,
                      Expanded(
                        child: ReflectionCardWidget(
                          moment: card,
                          selected: selectedTags.contains(card.tag),
                          onTap: () => onToggle(card.tag),
                        ),
                      ),
                    ]),
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openMoreSheet(BuildContext context) async {
    final result = await showModalBottomSheet<Set<String>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (_) => ReflectionMoreMomentsSheet(
        trait: trait,
        initialSelections: customMoments,
      ),
    );
    if (result != null) {
      onCustomMomentsChanged(result);
    }
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

class _MoreMomentsTile extends StatelessWidget {
  final Color accent;
  final VoidCallback onTap;
  const _MoreMomentsTile({required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accent.withValues(alpha: 0.45),
            style: BorderStyle.solid,
            width: 1.4,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(PhosphorIconsRegular.plus, color: accent, size: 18),
            ),
            const SizedBox(height: 10),
            Text(
              'More moments',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption(context, color: accent).copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'or write our own',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
