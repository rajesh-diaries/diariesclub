import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/family_children_provider.dart';
import '../../core/providers/venue_config_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../birthday/providers/birthday_packages_provider.dart';

/// Birthdays tab in the Club section. Distinct from the transactional
/// /birthday discovery flow: this surface is personal (kids' upcoming
/// birthday countdown) + emotional (brand stats, testimonials) + a
/// curated packages preview that defers to /birthday for the actual
/// inquire/reserve flow.
class BirthdaysTab extends ConsumerWidget {
  const BirthdaysTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
      children: const [
        _Hero(),
        _UpcomingBirthdaysSection(),
        _StatsSection(),
        _TestimonialsSection(),
        _PackagesPreviewSection(),
        _BottomCta(),
      ],
    );
  }
}

// =====================================================================
// Hero
// =====================================================================
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      color: AppColors.gold,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsFill.cake,
                  color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                'Birthdays at Play Diaries',
                style: AppTextStyles.h2(context, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Make their next one unforgettable.',
            style: AppTextStyles.body(context, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Upcoming birthdays (per-kid countdown). Hidden if no kids or none
// within 365 days (the next birthday is always within a year).
// =====================================================================
class _UpcomingBirthdaysSection extends ConsumerWidget {
  const _UpcomingBirthdaysSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    if (children.isEmpty) return const SizedBox.shrink();

    final today = DateTime.now();
    final upcoming = children
        .map((c) => _UpcomingBirthday.from(c, today))
        .whereType<_UpcomingBirthday>()
        .toList()
      ..sort((a, b) => a.daysUntil.compareTo(b.daysUntil));

    if (upcoming.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Coming up in your family',
              style: AppTextStyles.h3(context)),
          const SizedBox(height: 8),
          for (final u in upcoming) ...[
            _UpcomingCard(item: u),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _UpcomingBirthday {
  final String childName;
  final int turningAge;
  final int daysUntil;
  final DateTime nextBirthday;

  const _UpcomingBirthday({
    required this.childName,
    required this.turningAge,
    required this.daysUntil,
    required this.nextBirthday,
  });

  static _UpcomingBirthday? from(
      Map<String, dynamic> child, DateTime today) {
    final dobRaw = child['date_of_birth'];
    if (dobRaw == null) return null;
    final dob = DateTime.tryParse(dobRaw.toString());
    if (dob == null) return null;
    // Next anniversary on/after today.
    var next = DateTime(today.year, dob.month, dob.day);
    if (next.isBefore(DateTime(today.year, today.month, today.day))) {
      next = DateTime(today.year + 1, dob.month, dob.day);
    }
    final days = next.difference(
            DateTime(today.year, today.month, today.day))
        .inDays;
    final age = next.year - dob.year;
    return _UpcomingBirthday(
      childName: (child['name'] as String?) ?? 'Your kid',
      turningAge: age,
      daysUntil: days,
      nextBirthday: next,
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  final _UpcomingBirthday item;
  const _UpcomingCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final daysLabel = item.daysUntil == 0
        ? 'Today!'
        : item.daysUntil == 1
            ? 'Tomorrow'
            : item.daysUntil < 30
                ? 'in ${item.daysUntil} days'
                : item.daysUntil < 60
                    ? 'in ~${(item.daysUntil / 7).round()} weeks'
                    : 'in ${(item.daysUntil / 30).round()} months';
    final showCta = item.daysUntil <= 90;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.10),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsFill.cake,
              color: AppColors.gold, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.childName} turns ${item.turningAge} $daysLabel',
                  style: AppTextStyles.bodyLarge(context).copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (showCta) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Most families book us 6–8 weeks ahead.',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showCta)
            TextButton(
              onPressed: () => context.push('/birthday'),
              child: const Text('Plan now'),
            ),
        ],
      ),
    );
  }
}

// =====================================================================
// Brand stats (founder-authored)
// =====================================================================
class _StatsSection extends ConsumerWidget {
  const _StatsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final celebrations =
        (cfg['birthday_celebrations_count'] as int?) ?? 0;
    final kids = (cfg['birthday_happy_kids_count'] as int?) ?? 0;
    if (celebrations == 0 && kids == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            if (celebrations > 0)
              Expanded(child: _StatTile(value: celebrations, label: 'Celebrations')),
            if (celebrations > 0 && kids > 0)
              Container(
                width: 1, height: 36,
                color: Colors.white.withValues(alpha: 0.20),
              ),
            if (kids > 0)
              Expanded(child: _StatTile(value: kids, label: 'Happy kids')),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final int value;
  final String label;
  const _StatTile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          _format(value),
          style: AppTextStyles.h2(context, color: Colors.white)
              .copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTextStyles.caption(context, color: Colors.white70),
        ),
      ],
    );
  }

  static String _format(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k+';
    }
    return '$n+';
  }
}

// =====================================================================
// Testimonials (founder-authored quotes from Google reviews)
// =====================================================================
class _TestimonialsSection extends ConsumerWidget {
  const _TestimonialsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final raw = cfg['birthday_testimonials'];
    final items = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) items.add(Map<String, dynamic>.from(e));
      }
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('What parents say', style: AppTextStyles.h3(context)),
          const SizedBox(height: 10),
          for (final t in items) ...[
            _TestimonialCard(item: t),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _TestimonialCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _TestimonialCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final quote = (item['quote'] as String?)?.trim() ?? '';
    final author = (item['author'] as String?)?.trim() ?? '';
    if (quote.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.format_quote, color: AppColors.gold, size: 18),
          const SizedBox(height: 4),
          Text(quote, style: AppTextStyles.body(context)),
          if (author.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '— $author',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =====================================================================
// Packages preview (visual grid)
// =====================================================================
class _PackagesPreviewSection extends ConsumerWidget {
  const _PackagesPreviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(birthdayPackagesProvider);
    final packages = async.valueOrNull ?? const [];
    if (packages.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Explore packages',
                    style: AppTextStyles.h3(context)),
              ),
              TextButton(
                onPressed: () => context.push('/birthday'),
                child: const Text('See all'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final p in packages.take(3)) ...[
            _PackageCard(pkg: p),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final Map<String, dynamic> pkg;
  const _PackageCard({required this.pkg});

  @override
  Widget build(BuildContext context) {
    final id = pkg['id'] as String? ?? '';
    final name = (pkg['name'] as String?) ?? '—';
    final tier = (pkg['tier'] as String?)?.toUpperCase();
    final cover = pkg['cover_image_url'] as String?;
    final pricePaise = (pkg['price_paise'] as int?) ?? 0;
    final maxGuests = pkg['max_guests'] as int?;
    final durationHours = pkg['duration_hours'] as int?;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => id.isEmpty
          ? context.push('/birthday')
          : context.push('/birthday/reserve/$id'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cover != null && cover.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 8,
                child: CachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.gold.withValues(alpha: 0.18),
                  ),
                  placeholder: (_, __) => Container(
                    color: AppColors.gold.withValues(alpha: 0.10),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tier != null && tier.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        tier,
                        style: AppTextStyles.caption(context,
                                color: AppColors.gold)
                            .copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(name, style: AppTextStyles.bodyLarge(context)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (maxGuests != null)
                        _Chip(
                            icon: PhosphorIconsRegular.users,
                            label: 'Up to $maxGuests guests'),
                      if (durationHours != null)
                        _Chip(
                            icon: PhosphorIconsRegular.clock,
                            label: '$durationHours hr'),
                      if (pricePaise > 0)
                        _Chip(
                            icon: PhosphorIconsRegular.tag,
                            label: 'from ${Money.fromPaise(pricePaise)}'),
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
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.lightTextSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTextStyles.caption(
            context,
            color: AppColors.lightTextSecondary,
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// Bottom CTA — always present
// =====================================================================
class _BottomCta extends StatelessWidget {
  const _BottomCta();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: () => context.push('/birthday'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            children: [
              const Icon(PhosphorIconsFill.cake,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Host a birthday with us',
                  style: AppTextStyles.body(context, color: Colors.white)
                      .copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
