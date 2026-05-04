import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../providers/hero_cards_providers.dart';

/// Bottom-sheet modal opened when the parent taps an earned card in the
/// grid. Shows the card art big + name + rarity + description (placeholder
/// copy, TODO for founder wordsmith) + earned-on metadata.
///
/// Only earned cards open this sheet; uncollected cards are non-interactive.
class CardDetailSheet extends StatelessWidget {
  final HeroCardRow row;
  const CardDetailSheet({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final earnedAt = row.earnedAt;
    final isBirthday = row.isBirthdayExclusive;

    return Container(
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
          Center(
            child: AspectRatio(
              aspectRatio: 5 / 7,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: row.imageUrl == null || row.imageUrl!.isEmpty
                      ? Container(color: AppColors.gold.withValues(alpha: 0.20))
                      : CachedNetworkImage(
                          imageUrl: row.imageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: AppColors.gold.withValues(alpha: 0.20),
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            row.name,
            style: AppTextStyles.h2(context),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              _Chip(
                label: row.isRare ? 'Rare' : 'Common',
                color: row.isRare ? AppColors.gold : AppColors.lightTextSecondary,
                icon: row.isRare
                    ? PhosphorIconsFill.star
                    : PhosphorIconsRegular.circle,
              ),
              if (isBirthday)
                const _Chip(
                  label: 'Birthday Edition',
                  color: AppColors.rafiCoral,
                  icon: PhosphorIconsFill.cake,
                ),
            ],
          ),
          const SizedBox(height: 16),
          // TODO(founder): wordsmith pass on card description copy.
          Text(
            row.description == null || row.description!.isEmpty
                ? 'A piece of the adventure.'
                : row.description!,
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (earnedAt != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.lightBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EARNED ON',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ).copyWith(
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('EEEE, MMMM d, yyyy')
                        .format(earnedAt.toLocal()),
                    style: AppTextStyles.body(context),
                  ),
                  if (isBirthday) ...[
                    const SizedBox(height: 4),
                    Text(
                      'During a birthday celebration.',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ] else if (row.sessionId != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'During a play session.',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _Chip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.caption(context, color: color)
                .copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
