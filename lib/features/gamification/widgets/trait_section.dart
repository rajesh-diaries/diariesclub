import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/reflection_moments_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import 'reflection_card.dart';

/// Trait header + 3-card row used inside the reflection screen. The cards
/// always come in trios (3 per trait, RPC-enforced) so a fixed `Row` is
/// safe; if the seed ever drops below 3 the row gracefully fills with
/// SizedBox spacers.
class TraitSection extends StatelessWidget {
  final String trait;
  final List<ReflectionMoment> cards;
  final Set<String> selectedTags;
  final ValueChanged<String> onToggle;

  const TraitSection({
    super.key,
    required this.trait,
    required this.cards,
    required this.selectedTags,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    debugPrint('[BUG-039a] TraitSection.build trait=$trait '
        'cards=${cards.length} selectedSize=${selectedTags.length}');
    final color = _heroColor(trait);
    debugPrint('[BUG-039a] TraitSection trait=$trait color resolved');
    final iconData = _heroIcon(trait);
    debugPrint('[BUG-039a] TraitSection trait=$trait icon resolved');

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
              Builder(builder: (_) {
                debugPrint('[BUG-039a] TraitSection trait=$trait '
                    'building hero-name Text');
                return Text(
                  _heroName(trait).toUpperCase(),
                  style: AppTextStyles.caption(context, color: color)
                      .copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w800),
                );
              }),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List<Widget>.generate(3, (i) {
              debugPrint('[BUG-039a] TraitSection trait=$trait '
                  'building card slot i=$i (cards.length=${cards.length})');
              final spacer = i > 0
                  ? const SizedBox(width: 10)
                  : const SizedBox.shrink();
              if (i >= cards.length) {
                return Expanded(
                  child: Row(children: [spacer, const Spacer()]),
                );
              }
              final card = cards[i];
              debugPrint('[BUG-039a] TraitSection trait=$trait card[$i]: '
                  'tag=${card.tag} primaryTrait=${card.primaryTrait} '
                  'icon=${card.icon} displayText.len=${card.displayText.length}');
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
