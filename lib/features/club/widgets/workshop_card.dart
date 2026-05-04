import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import 'trait_pill.dart';

/// Workshop list card. Hero image with trait pill overlay, then date/title/
/// meta + spots-remaining state. Tap → /club/workshop/:id.
class WorkshopCard extends ConsumerWidget {
  final Map<String, dynamic> workshop;
  const WorkshopCard({super.key, required this.workshop});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = workshop['id'] as String;
    final title = (workshop['title'] as String?) ?? '';
    final cover = workshop['cover_image_url'] as String?;
    final scheduled = DateTime.parse(workshop['scheduled_at'] as String);
    final duration = (workshop['duration_minutes'] as int?) ?? 0;
    final price = (workshop['price_paise'] as int?) ?? 0;
    final ageMin = workshop['age_group_min'] as int?;
    final ageMax = workshop['age_group_max'] as int?;
    final capacity = (workshop['capacity'] as int?) ?? 0;
    final spots = (workshop['spots_remaining'] as int?) ?? 0;
    final trait = workshop['primary_trait'] as String?;
    final xp = (workshop['xp_award'] as int?) ?? 0;

    final isFull = spots == 0;
    final isLow = spots > 0 && spots <= 3;

    return InkWell(
      onTap: () => context.push('/club/workshop/$id'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.lightBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: cover == null
                      ? Container(color: AppColors.gold.withValues(alpha: 0.20))
                      : CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: AppColors.gold.withValues(alpha: 0.20),
                          ),
                        ),
                ),
                if (trait != null)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: TraitPill(trait: trait, light: true),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEE MMM d · h:mm a').format(scheduled.toLocal()),
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(title, style: AppTextStyles.h3(context)),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (ageMin != null && ageMax != null)
                        'Ages $ageMin–$ageMax',
                      '$duration min',
                      Money.fromPaise(price),
                    ].join(' · '),
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                  if (trait != null && xp > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '+$xp XP to ${_heroName(trait)}',
                      style: AppTextStyles.caption(
                        context,
                        color: _heroColor(trait),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SpotsLabel(
                          isFull: isFull,
                          isLow: isLow,
                          spots: spots,
                          capacity: capacity,
                        ),
                      ),
                      FilledButton(
                        onPressed: isFull
                            ? null
                            : () => context.push('/club/workshop/$id'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: Text(isFull ? 'Full' : 'Register'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _heroName(String t) => switch (t) {
        'rafi' => 'Rafi',
        'ellie' => 'Ellie',
        'gerry' => 'Gerry',
        'zena' => 'Zena',
        _ => '?',
      };

  Color _heroColor(String t) => switch (t) {
        'rafi' => AppColors.rafiCoral,
        'ellie' => AppColors.ellieBlue,
        'gerry' => AppColors.gerryAmber,
        'zena' => AppColors.zenaGreen,
        _ => AppColors.gold,
      };
}

class _SpotsLabel extends StatelessWidget {
  final bool isFull;
  final bool isLow;
  final int spots;
  final int capacity;
  const _SpotsLabel({
    required this.isFull,
    required this.isLow,
    required this.spots,
    required this.capacity,
  });

  @override
  Widget build(BuildContext context) {
    Widget icon(IconData i, Color c) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(i, size: 14, color: c),
        );

    if (isFull) {
      return Row(
        children: [
          icon(PhosphorIconsRegular.users, AppColors.adminRed),
          Text(
            'Workshop full',
            style: AppTextStyles.caption(context, color: AppColors.adminRed),
          ),
        ],
      );
    }
    final color = isLow ? AppColors.warningYellow : AppColors.lightTextSecondary;
    return Row(
      children: [
        icon(PhosphorIconsRegular.users, color),
        Text(
          '$spots of $capacity spots left',
          style: AppTextStyles.caption(context, color: color),
        ),
      ],
    );
  }
}
