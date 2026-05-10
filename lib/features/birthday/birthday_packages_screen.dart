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
                    _PriceChip(
                      label: 'Veg',
                      pricePaise: priceVeg,
                    ),
                    _PriceChip(
                      label: 'Non-Veg',
                      pricePaise: priceNonVeg,
                    ),
                    Text(
                      'per pax · 18% GST extra',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
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
                ...inclusionLines.take(6).map((line) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check,
                            size: 16,
                            color: AppColors.activeGreen,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(line,
                                style: AppTextStyles.body(context)),
                          ),
                        ],
                      ),
                    )),
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
