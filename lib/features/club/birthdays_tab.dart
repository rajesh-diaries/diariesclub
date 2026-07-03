import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/current_family_provider.dart';
import '../../core/providers/family_children_provider.dart';
import '../../core/providers/venue_config_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton_card.dart';
import '../birthday/providers/birthday_packages_provider.dart';
import '../birthday/widgets/whatsapp_helpers.dart';

/// Birthdays tab in the Club section. This is a conversion surface that
/// surfaces all birthday packages up front, plus the brochure and WhatsApp
/// connect CTAs at the top of the package list.
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
        _ExplorePackagesSection(),
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.ellieBlue, AppColors.rafiCoral],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  PhosphorIconsFill.cake,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Birthdays at Play Diaries',
                    style: AppTextStyles.h2(
                      context,
                      color: Colors.white,
                    ).copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Make their next one unforgettable.',
              style: AppTextStyles.bodyLarge(
                context,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
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
    final upcoming =
        children
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
          Text('Coming up in your family', style: AppTextStyles.h3(context)),
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

  static _UpcomingBirthday? from(Map<String, dynamic> child, DateTime today) {
    final dobRaw = child['date_of_birth'];
    if (dobRaw == null) return null;
    final dob = DateTime.tryParse(dobRaw.toString());
    if (dob == null) return null;
    // Next anniversary on/after today.
    var next = DateTime(today.year, dob.month, dob.day);
    if (next.isBefore(DateTime(today.year, today.month, today.day))) {
      next = DateTime(today.year + 1, dob.month, dob.day);
    }
    final days = next
        .difference(DateTime(today.year, today.month, today.day))
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
          const Icon(PhosphorIconsFill.cake, color: AppColors.gold, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.childName} turns ${item.turningAge} $daysLabel',
                  style: AppTextStyles.bodyLarge(
                    context,
                  ).copyWith(fontWeight: FontWeight.w800),
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
    final celebrations = (cfg['birthday_celebrations_count'] as int?) ?? 0;
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
              Expanded(
                child: _StatTile(value: celebrations, label: 'Celebrations'),
              ),
            if (celebrations > 0 && kids > 0)
              Container(
                width: 1,
                height: 36,
                color: Colors.white.withValues(alpha: 0.20),
              ),
            if (kids > 0)
              Expanded(
                child: _StatTile(value: kids, label: 'Happy kids'),
              ),
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
          style: AppTextStyles.h2(
            context,
            color: Colors.white,
          ).copyWith(fontWeight: FontWeight.w900),
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
          const Icon(
            PhosphorIconsRegular.quotes,
            color: AppColors.gold,
            size: 18,
          ),
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
// Package styling helpers
// =====================================================================
Color? _parseHexColor(String hex) {
  final buffer = StringBuffer();
  if (hex.length == 4) {
    final r = hex[1];
    final g = hex[2];
    final b = hex[3];
    buffer.write('FF$r$r$g$g$b$b');
  } else if (hex.length == 7) {
    buffer.write('FF${hex.substring(1)}');
  } else if (hex.length == 9) {
    buffer.write(hex.substring(1));
  } else {
    return null;
  }
  final value = int.tryParse(buffer.toString(), radix: 16);
  if (value == null) return null;
  return Color(value);
}

Color _staticAccentColor(String name) => switch (name) {
  'Happy Tales' => AppColors.rafiCoral,
  'Grand' => AppColors.navy,
  'Magical' => AppColors.gold,
  _ => AppColors.fitGreen,
};

String? _staticBadgeText(String name) => switch (name) {
  'Happy Tales' => 'Most Booked',
  'Grand' => 'Big celebration',
  'Magical' => 'Premium',
  _ => null,
};

String? _staticTagline(String name) => switch (name) {
  'Little Joy' => 'Perfect for intimate celebrations',
  'Happy Tales' => 'Our most loved package',
  'Grand' => 'Grand scale, seamless fun',
  'Magical' => 'The full enchanted experience',
  _ => null,
};

Color _resolveAccentColor(Map<String, dynamic> package, String name) {
  final hex = (package['accent_color_hex'] as String?)?.trim();
  if (hex != null && hex.isNotEmpty) {
    final parsed = _parseHexColor(hex);
    if (parsed != null) return parsed;
  }
  return _staticAccentColor(name);
}

String? _resolveBadgeText(Map<String, dynamic> package) {
  final text = (package['badge_text'] as String?)?.trim();
  if (text != null && text.isNotEmpty) return text;
  final name = (package['name'] as String?) ?? '';
  return _staticBadgeText(name);
}

String? _resolveTagline(Map<String, dynamic> package) {
  final text = (package['tagline'] as String?)?.trim();
  if (text != null && text.isNotEmpty) return text;
  final name = (package['name'] as String?) ?? '';
  return _staticTagline(name);
}

// =====================================================================
// Explore packages — all packages up front, with brochure + WhatsApp
// CTAs placed at the top of the section.
// =====================================================================
class _ExplorePackagesSection extends ConsumerWidget {
  const _ExplorePackagesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(birthdayPackagesProvider);
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final brochureUrl = (cfg['birthday_brochure_url'] as String?)?.trim();
    final teamPhone = (cfg['birthday_whatsapp_phone'] as String?)?.trim();

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: SkeletonList(itemCount: 3, itemHeight: 220),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: BrandedErrorState(
          message: "Couldn't load birthday packages",
          onRetry: () => ref.invalidate(birthdayPackagesProvider),
        ),
      ),
      data: (packages) {
        if (packages.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Explore packages', style: AppTextStyles.h3(context)),
              const SizedBox(height: 10),
              _PackageActionRow(brochureUrl: brochureUrl, teamPhone: teamPhone),
              const SizedBox(height: 4),
              for (final p in packages) _PackageCard(pkg: p),
            ],
          ),
        );
      },
    );
  }
}

class _PackageActionRow extends ConsumerWidget {
  final String? brochureUrl;
  final String? teamPhone;
  const _PackageActionRow({required this.brochureUrl, required this.teamPhone});

  Future<void> _openPdf(BuildContext context) async {
    final url = brochureUrl;
    if (url == null || url.isEmpty) return;
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the brochure.")),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open the brochure.")),
      );
    }
  }

  Future<void> _openWhatsapp(BuildContext context, WidgetRef ref) async {
    final phone = teamPhone;
    if (phone == null || phone.isEmpty) return;
    final family = ref.read(currentFamilyProvider).valueOrNull;
    final children = ref.read(familyChildrenProvider).valueOrNull ?? const [];
    final parentName = (family?['name'] as String?)?.trim();
    final childName = children.isEmpty
        ? null
        : (children.first['name'] as String?)?.trim();
    try {
      final ok = await openTalkToTeamWhatsapp(
        teamPhone: phone,
        childName: childName,
        parentName: parentName,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't open WhatsApp. Is it installed?"),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't open WhatsApp. Is it installed?"),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPdf = brochureUrl != null && brochureUrl!.isNotEmpty;
    final hasPhone = teamPhone != null && teamPhone!.isNotEmpty;
    if (!hasPdf && !hasPhone) return const SizedBox.shrink();

    return Row(
      children: [
        if (hasPdf) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _openPdf(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navy,
                side: BorderSide(color: AppColors.navy.withValues(alpha: 0.40)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(PhosphorIconsRegular.filePdf, size: 18),
              label: const Text('Brochure (PDF)'),
            ),
          ),
          if (hasPhone) const SizedBox(width: 8),
        ],
        if (hasPhone)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _openWhatsapp(context, ref),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.activeGreen,
                side: BorderSide(
                  color: AppColors.activeGreen.withValues(alpha: 0.60),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(PhosphorIconsRegular.whatsappLogo, size: 18),
              label: const Text('Connect on WhatsApp'),
            ),
          ),
      ],
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
    final cover = pkg['cover_image_url'] as String?;
    final priceVeg = (pkg['price_per_pax_veg_paise'] as int?) ?? 0;
    final priceNonVeg = (pkg['price_per_pax_non_veg_paise'] as int?) ?? 0;
    final hallName = (pkg['hall_name'] as String?) ?? '';
    final minGuests = (pkg['min_guests'] as int?) ?? 0;
    final maxGuests = (pkg['max_guests'] as int?) ?? 0;

    final accentColor = _resolveAccentColor(pkg, name);
    final badgeText = _resolveBadgeText(pkg);
    final tagline = _resolveTagline(pkg);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => id.isEmpty
          ? context.push('/birthday')
          : context.push('/birthday/reserve/$id'),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.lightBorder),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tier accent bar.
            Container(height: 5, color: accentColor),
            if (cover != null && cover.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 8,
                child: CachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: accentColor.withValues(alpha: 0.12)),
                  errorWidget: (_, __, ___) =>
                      Container(color: accentColor.withValues(alpha: 0.12)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (badgeText != null) ...[
                    _Badge(text: badgeText, color: accentColor),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    name,
                    style: AppTextStyles.bodyLarge(
                      context,
                    ).copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (tagline != null && tagline.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      tagline,
                      style: AppTextStyles.body(
                        context,
                        color: accentColor,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                  if (hallName.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '$hallName · $minGuests–$maxGuests guests',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (priceVeg > 0)
                              _PriceChip(
                                label: 'Veg',
                                pricePaise: priceVeg,
                                color: accentColor,
                              ),
                            if (priceNonVeg > 0)
                              _PriceChip(
                                label: 'Non-Veg',
                                pricePaise: priceNonVeg,
                                color: accentColor,
                              ),
                          ],
                        ),
                      ),
                      _ExploreChip(color: accentColor),
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
        style: AppTextStyles.caption(
          context,
          color: Colors.white,
        ).copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.5),
      ),
    );
  }
}

class _PriceChip extends StatelessWidget {
  final String label;
  final int pricePaise;
  final Color color;
  const _PriceChip({
    required this.label,
    required this.pricePaise,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '$label ${Money.fromPaise(pricePaise)}',
        style: AppTextStyles.body(
          context,
        ).copyWith(fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

class _ExploreChip extends StatelessWidget {
  final Color color;
  const _ExploreChip({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Explore',
            style: AppTextStyles.body(
              context,
            ).copyWith(fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(width: 2),
          Icon(PhosphorIconsRegular.caretRight, size: 14, color: color),
        ],
      ),
    );
  }
}
