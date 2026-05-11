import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/error_screen.dart';
import 'providers/birthday_packages_provider.dart';

/// Birthday packages browse screen — vertical stack of package cards.
/// Hardcoded badge mapping (per locked decision):
/// `tier='hero_adventure'` → "Most Booked", `tier='legendary'` → "Premium".
class BirthdayPackagesScreen extends ConsumerWidget {
  const BirthdayPackagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(birthdayPackagesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a package'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => FriendlyErrorScreen(
            code: 'E-PKGS',
            userMessage: "Couldn't load packages",
            technicalDetails: e.toString(),
          ),
          data: (packages) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(birthdayPackagesProvider),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Text(
                    'All packages include exclusive play time, decor, food, and a host.',
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ),
                for (final p in packages) _PackageCard(package: p),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: Text(
                    'Not sure? Reach our team via WhatsApp from the help screen.',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final Map<String, dynamic> package;
  const _PackageCard({required this.package});

  @override
  Widget build(BuildContext context) {
    final id = package['id'] as String;
    final name = (package['name'] as String?) ?? '';
    final description = (package['description'] as String?) ?? '';
    final tier = package['tier'] as String?;
    final cover = package['cover_image_url'] as String?;
    final priceVeg = (package['price_per_pax_veg_paise'] as int?) ?? 0;
    final priceNonVeg = (package['price_per_pax_non_veg_paise'] as int?) ?? 0;
    final hallName = (package['hall_name'] as String?) ?? '';
    final minGuests = (package['min_guests'] as int?) ?? 0;
    final maxGuests = (package['max_guests'] as int?) ?? 0;
    // inclusions seeded as a JSON array of strings ("Min 20 guests", "1 Welcome Drink", …).
    final inclusionLines = ((package['inclusions'] as List?) ?? const [])
        .whereType<String>()
        .toList();
    final experienceLines =
        ((package['experience_inclusions'] as List?) ?? const [])
            .whereType<String>()
            .toList();
    final nonFoodOfferings =
        ((package['non_food_offerings'] as List?) ?? const [])
            .whereType<String>()
            .toList();

    final badge = tier == 'magical'
        ? const _Badge(text: 'Premium', color: AppColors.navy)
        : tier == 'happy_tales'
            ? const _Badge(text: 'Most Booked', color: AppColors.gold)
            : null;

    return Container(
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
                aspectRatio: 16 / 8,
                child: cover == null || cover.isEmpty
                    ? Container(
                        color: AppColors.gold.withValues(alpha: 0.30),
                        alignment: Alignment.center,
                        child: const Icon(
                          PhosphorIconsFill.cake,
                          color: AppColors.gold,
                          size: 48,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: cover,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.gold.withValues(alpha: 0.30),
                        ),
                      ),
              ),
              if (badge != null)
                Positioned(top: 12, right: 12, child: badge),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.h3(context)),
                if (hallName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$hallName · $minGuests–$maxGuests guests',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _PriceChip(label: 'Veg', pricePaise: priceVeg),
                    _PriceChip(label: 'Non-Veg', pricePaise: priceNonVeg),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'per pax · 18% GST extra',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  'MENU',
                  style: AppTextStyles.caption(
                    context, color: AppColors.lightTextSecondary,
                  ).copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                _InclusionsGrid(lines: inclusionLines),
                if (nonFoodOfferings.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'DECOR & EXTRAS',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ).copyWith(
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _InclusionsGrid(lines: nonFoodOfferings),
                ],
                if (experienceLines.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ExperienceBlock(lines: experienceLines),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => context.push('/birthday/reserve/$id'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Inquire about this package'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

class _PriceChip extends StatelessWidget {
  final String label;
  final int pricePaise;
  const _PriceChip({required this.label, required this.pricePaise});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '$label ${Money.fromPaise(pricePaise)}',
        style: AppTextStyles.caption(context).copyWith(
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: AppTextStyles.caption(context, color: Colors.white).copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// 2-column grid of inclusion bullets. Reads denser than a single
/// column when there are 4+ items but still wraps cleanly on narrow
/// devices (single column under ~360px).
class _InclusionsGrid extends StatelessWidget {
  final List<String> lines;
  const _InclusionsGrid({required this.lines});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final twoColumn = c.maxWidth >= 360;
        final colWidth = twoColumn ? (c.maxWidth - 12) / 2 : c.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final line in lines)
              SizedBox(
                width: colWidth,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.check,
                        size: 16,
                        color: AppColors.activeGreen,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        line,
                        style: AppTextStyles.body(context),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Per-package experience block — admin-authored bullet list of venue
/// benefits (e.g. '2.5 hours play time', '3 hours hall booking',
/// 'Food buffet'). Sourced from birthday_packages.experience_inclusions
/// so each package can advertise its own set.
class _ExperienceBlock extends StatelessWidget {
  final List<String> lines;
  const _ExperienceBlock({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EXPERIENCE',
            style: AppTextStyles.caption(
              context, color: AppColors.lightTextSecondary,
            ).copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final label in lines)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle,
                        size: 14, color: AppColors.navy),
                    const SizedBox(width: 4),
                    Text(label, style: AppTextStyles.caption(context)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
