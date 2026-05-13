import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../providers/hero_cards_providers.dart';
import 'card_detail_sheet.dart';
import 'card_grid_item.dart';

const _heroOrder = ['rafi', 'ellie', 'gerry', 'zena'];

/// Master card collection on the dashboard. Two halves:
///   * Birthday Memories: cards from earned birthday-exclusive
///     definitions (or empty state if the child has none yet).
///   * Per-hero sections (Rafi → Ellie → Gerry → Zena), each a 3-column
///     grid of 6 cards. Cards are tinted greyscale until earned.
///
/// Tapping an earned card opens [CardDetailSheet]; uncollected cards
/// are non-interactive.
class HeroCardCollectionSection extends ConsumerWidget {
  final String childId;

  /// When true, shows section headers + intro. When false (used inside
  /// the per-trait detail screen), renders a single hero's grid only.
  final String? singleHero;

  const HeroCardCollectionSection({
    super.key,
    required this.childId,
    this.singleHero,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(heroCardsForChildProvider(childId));
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (singleHero != null) {
      final filtered = rows.where((r) => r.hero == singleHero).toList();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _HeroGrid(cards: filtered),
      );
    }

    final earnedCount = rows.where((r) => r.isEarned).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            title: 'CARD COLLECTION',
            trailing: '$earnedCount of ${rows.length} earned',
          ),
          const SizedBox(height: 12),
          // Birthday Memories shelf is parked — birthday cards still
          // earn + appear under each character's section below.
          if (earnedCount == 0) _CollectionEmpty(),
          for (final hero in _heroOrder) ...[
            _PerHeroSection(
              hero: hero,
              cards: rows.where((r) => r.hero == hero).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;
  const _SectionTitle({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ).copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w800),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
      ],
    );
  }
}

class _PerHeroSection extends StatelessWidget {
  final String hero;
  final List<HeroCardRow> cards;
  const _PerHeroSection({required this.hero, required this.cards});

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroDivider(hero: hero),
        const SizedBox(height: 8),
        _HeroGrid(cards: cards),
      ],
    );
  }
}

class _HeroDivider extends StatelessWidget {
  final String hero;
  const _HeroDivider({required this.hero});

  @override
  Widget build(BuildContext context) {
    final color = _heroColor(hero);
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.18),
          ),
          child: Icon(_heroIcon(hero), color: color, size: 12),
        ),
        const SizedBox(width: 8),
        Text(
          _heroLabel(hero).toUpperCase(),
          style: AppTextStyles.caption(context, color: color)
              .copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _HeroGrid extends StatelessWidget {
  final List<HeroCardRow> cards;
  const _HeroGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 5 / 7,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: [
        for (final c in cards)
          CardGridItem(
            row: c,
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => CardDetailSheet(row: c),
            ),
          ),
      ],
    );
  }
}

class _CollectionEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Row(
        children: [
          const Icon(
            PhosphorIconsFill.lockSimple,
            color: AppColors.lightTextSecondary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Earn cards by getting Healthy Bite tokens or completing birthday celebrations.',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _heroLabel(String h) => switch (h) {
      'rafi' => 'Rafi · Brave',
      'ellie' => 'Ellie · Kind',
      'gerry' => 'Gerry · Curious',
      'zena' => 'Zena · Creative',
      _ => h,
    };

Color _heroColor(String h) => switch (h) {
      'rafi' => AppColors.rafiCoral,
      'ellie' => AppColors.ellieBlue,
      'gerry' => AppColors.gerryAmber,
      'zena' => AppColors.zenaGreen,
      _ => AppColors.gold,
    };

IconData _heroIcon(String h) => switch (h) {
      'rafi' => PhosphorIconsFill.shieldStar,
      'ellie' => PhosphorIconsFill.heart,
      'gerry' => PhosphorIconsFill.magnifyingGlass,
      'zena' => PhosphorIconsFill.palette,
      _ => PhosphorIconsFill.sparkle,
    };
