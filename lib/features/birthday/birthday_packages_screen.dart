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
import '../../core/widgets/error_screen.dart';
import '../../core/widgets/skeleton_card.dart';
import 'providers/birthday_packages_provider.dart';
import 'providers/saved_packages_provider.dart';
import 'widgets/inquiry_bottom_sheet.dart';
import 'widgets/whatsapp_helpers.dart';

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

/// Birthday packages screen — the conversion surface.
///
/// Photo-led package cards, experience info ahead of menu, brochure PDF
/// + WhatsApp share + heart-save per card, "hosted N parties so far"
/// social proof banner, and a floating WhatsApp "talk to our team"
/// CTA. Tapping "Inquire — it's free" opens [InquiryBottomSheet] on
/// the same screen (no second-page redundancy).
class BirthdayPackagesScreen extends ConsumerWidget {
  const BirthdayPackagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pkgsAsync = ref.watch(birthdayPackagesProvider);
    final venueCfg = ref.watch(venueConfigProvider).valueOrNull;

    final teamPhone =
        (venueCfg?['birthday_whatsapp_phone'] as String?)?.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Birthday packages'),
        leading: IconButton(
          icon: const Icon(PhosphorIconsRegular.arrowLeft),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      bottomNavigationBar: (teamPhone != null && teamPhone.isNotEmpty)
          ? _TalkToTeamBar(teamPhone: teamPhone)
          : null,
      body: SafeArea(
        child: pkgsAsync.when(
          loading: () => const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: SkeletonList(),
          ),
          error: (e, _) => FriendlyErrorScreen(
            code: 'E-PKGS',
            userMessage: "Couldn't load packages",
            technicalDetails: e.toString(),
          ),
          data: (packages) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(birthdayPackagesProvider);
              ref.invalidate(savedBirthdayPackageIdsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
              children: [
                _TopBrochureRow(
                  brochureUrl:
                      (venueCfg?['birthday_brochure_url'] as String?)
                          ?.trim(),
                  teamPhone: teamPhone,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Text(
                    'All packages include hall, play and food.',
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ),
                for (final p in packages) _PackageCard(package: p),
                const SizedBox(height: 16),
                _GrandHallNote(),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '5% GST extra',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PackageCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> package;
  const _PackageCard({required this.package});

  @override
  ConsumerState<_PackageCard> createState() => _PackageCardState();
}

class _PackageCardState extends ConsumerState<_PackageCard> {
  bool _menuExpanded = false;

  void _openInquirySheet() {
    final children =
        ref.read(familyChildrenProvider).valueOrNull ?? const [];
    final preselectedChildId = children.isEmpty
        ? null
        : children.first['id'] as String?;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InquiryBottomSheet(
        package: widget.package,
        preselectedChildId: preselectedChildId,
      ),
    );
  }

  // Per-card brochure handlers retired with the layout change — see
  // _TopBrochureRow at the screen level.

  Future<void> _toggleSave() async {
    final pkgId = widget.package['id'] as String;
    final isNowSaved =
        await toggleBirthdayPackageSaved(ref, pkgId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(isNowSaved
            ? 'Saved — you can come back to compare later.'
            : 'Removed from saved.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.package;
    final id = p['id'] as String;
    final name = (p['name'] as String?) ?? '';
    final cover = p['cover_image_url'] as String?;
    final priceVeg = (p['price_per_pax_veg_paise'] as int?) ?? 0;
    final priceNonVeg = (p['price_per_pax_non_veg_paise'] as int?) ?? 0;
    final hallName = (p['hall_name'] as String?) ?? '';
    final minGuests = (p['min_guests'] as int?) ?? 0;
    final maxGuests = (p['max_guests'] as int?) ?? 0;
    // Per-package pdf_url retired; brochure is now a single venue-level
    // PDF rendered at the top of the screen via _TopBrochureRow.

    final inclusions = [
      ...((p['inclusions'] as List?) ?? const []).whereType<String>(),
      ...((p['experience_inclusions'] as List?) ?? const [])
          .whereType<String>(),
      ...((p['non_food_offerings'] as List?) ?? const [])
          .whereType<String>(),
    ];

    final accentColor = _resolveAccentColor(p, name);
    final badgeText = _resolveBadgeText(p);
    final tagline = _resolveTagline(p);
    final badge = badgeText != null
        ? _Badge(text: badgeText, color: accentColor)
        : null;
    final topInclusions = inclusions.take(3).toList();
    final remainingInclusions = inclusions.skip(3).toList();

    final savedIds =
        ref.watch(savedBirthdayPackageIdsProvider).valueOrNull ??
            const <String>{};
    final isSaved = savedIds.contains(id);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lightBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tier accent bar.
          Container(
            height: 6,
            color: accentColor,
          ),

          // Hero photo — only when an actual cover is uploaded.
          if (cover != null && cover.isNotEmpty)
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _HeroImage(coverUrl: cover),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: _HeartButton(
                    saved: isSaved,
                    onTap: _toggleSave,
                  ),
                ),
              ],
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (badge != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: badge,
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: AppTextStyles.h2(context)),
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
                        ],
                      ),
                    ),
                    _HeartButton(
                      saved: isSaved,
                      onTap: _toggleSave,
                    ),
                  ],
                ),
                if (hallName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$hallName · $minGuests–$maxGuests guests',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 14),

                // Price row.
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _PriceChip(
                      label: 'Veg',
                      pricePaise: priceVeg,
                      color: accentColor,
                    ),
                    _PriceChip(
                      label: 'Non-Veg',
                      pricePaise: priceNonVeg,
                      color: accentColor,
                    ),
                  ],
                ),
                // Top inclusions — always visible so the card has value even
                // when collapsed.
                if (topInclusions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _InclusionsGrid(lines: topInclusions, iconColor: accentColor),
                ],

                // Remaining inclusions — collapsed by default.
                if (remainingInclusions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () =>
                        setState(() => _menuExpanded = !_menuExpanded),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Text(
                            _menuExpanded
                                ? 'Show less'
                                : 'Show all inclusions',
                            style: AppTextStyles.bodyLarge(context)
                                .copyWith(color: AppColors.navy),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _menuExpanded
                                ? PhosphorIconsRegular.caretUp
                                : PhosphorIconsRegular.caretDown,
                            color: AppColors.navy,
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 180),
                    crossFadeState: _menuExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox.shrink(),
                    secondChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        _InclusionsGrid(
                          lines: remainingInclusions,
                          iconColor: accentColor,
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // Inquire CTA.
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _openInquirySheet,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Inquire',
                      style: AppTextStyles.button(context),
                    ),
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
  final Color color;
  const _PriceChip({
    required this.label,
    required this.pricePaise,
    this.color = AppColors.gold,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '$label ${Money.fromPaise(pricePaise)}',
        style: AppTextStyles.body(context).copyWith(
          fontWeight: FontWeight.w800,
          color: color,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

class _HeartButton extends StatelessWidget {
  final bool saved;
  final VoidCallback onTap;
  const _HeartButton({required this.saved, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            saved
                ? PhosphorIconsFill.heart
                : PhosphorIconsRegular.heart,
            color: saved
                ? AppColors.rafiCoral
                : AppColors.lightTextSecondary,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  final String? coverUrl;
  const _HeroImage({required this.coverUrl});

  @override
  Widget build(BuildContext context) {
    final hasUrl = coverUrl != null && coverUrl!.isNotEmpty;

    Widget buildPlaceholder(BuildContext _) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.gold.withValues(alpha: 0.25),
                AppColors.rafiCoral.withValues(alpha: 0.15),
              ],
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsFill.cake,
                color: AppColors.navy.withValues(alpha: 0.35),
                size: 48,
              ),
              const SizedBox(height: 8),
              Text(
                'Birthday package',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.navy.withValues(alpha: 0.45),
                ).copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6),
              ),
            ],
          ),
        );

    if (!hasUrl) return buildPlaceholder(context);

    return CachedNetworkImage(
      imageUrl: coverUrl!,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (ctx, _) => buildPlaceholder(ctx),
      errorWidget: (_, __, ___) => buildPlaceholder(context),
    );
  }
}

class _InclusionsGrid extends StatelessWidget {
  final List<String> lines;
  final Color iconColor;
  const _InclusionsGrid({
    required this.lines,
    this.iconColor = AppColors.activeGreen,
  });

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
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(
                        PhosphorIconsRegular.check,
                        size: 16,
                        color: iconColor,
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

class _GrandHallNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.08),
          border: Border.all(
            color: AppColors.gold.withValues(alpha: 0.30),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              PhosphorIconsRegular.info,
              size: 18,
              color: AppColors.navy,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Hosting more than 45 guests? Little Joy and Happy Tales '
                'packages can also be booked in Hall — The Grand (45-guest '
                'minimum).',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sticky bottom bar that opens WhatsApp with the team. Replaces the old
/// floating button: it never overlaps scrollable content because it lives
/// in the scaffold's bottom slot.
class _TalkToTeamBar extends ConsumerWidget {
  final String teamPhone;
  const _TalkToTeamBar({required this.teamPhone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: AppColors.lightBorder),
          ),
        ),
        child: FilledButton.icon(
          onPressed: () async {
            final family = ref.read(currentFamilyProvider).valueOrNull;
            final parentName = (family?['name'] as String?)?.trim();
            final children =
                ref.read(familyChildrenProvider).valueOrNull ?? const [];
            final childName = children.isEmpty
                ? null
                : (children.first['name'] as String?)?.trim();
            await openTalkToTeamWhatsapp(
              teamPhone: teamPhone,
              childName: childName,
              parentName: parentName,
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.activeGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(PhosphorIconsFill.whatsappLogo, size: 22),
          label: Text(
            'Talk to our team',
            style: AppTextStyles.button(context),
          ),
        ),
      ),
    );
  }
}

/// Screen-level brochure row. Shows "Brochure (PDF)" + "Send to WhatsApp"
/// side-by-side above the package cards. The PDF lives at
/// venue_config.birthday_brochure_url (one shared brochure for all
/// packages); the WhatsApp button drops the same link into a soft
/// message to the team. Hidden entirely if no brochure URL is set.
class _TopBrochureRow extends ConsumerWidget {
  final String? brochureUrl;
  final String? teamPhone;
  const _TopBrochureRow({required this.brochureUrl, required this.teamPhone});

  Future<void> _openPdf(BuildContext context) async {
    final url = brochureUrl;
    if (url == null || url.isEmpty) return;
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open the brochure.")),
      );
    }
  }

  Future<void> _sendToWhatsapp(BuildContext context, WidgetRef ref) async {
    final phone = teamPhone;
    if (phone == null || phone.isEmpty) return;
    final family = ref.read(currentFamilyProvider).valueOrNull;
    final children = ref.read(familyChildrenProvider).valueOrNull;
    final parentName = (family?['name'] as String?)?.trim();
    final childName = (children == null || children.isEmpty)
        ? null
        : (children.first['name'] as String?)?.trim();
    await openBrochureWhatsapp(
      teamPhone: phone,
      packageName: 'your birthday packages',
      childName: childName,
      parentName: parentName,
      brochurePdfUrl: brochureUrl,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPdf = brochureUrl != null && brochureUrl!.isNotEmpty;
    final hasPhone = teamPhone != null && teamPhone!.isNotEmpty;
    if (!hasPdf && !hasPhone) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          if (hasPdf) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openPdf(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.navy,
                  side: BorderSide(
                    color: AppColors.navy.withValues(alpha: 0.40),
                  ),
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
                onPressed: () => _sendToWhatsapp(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.activeGreen,
                  side: BorderSide(
                    color: AppColors.activeGreen.withValues(alpha: 0.60),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(PhosphorIconsRegular.whatsappLogo, size: 18),
                label: const Text('Send to WhatsApp'),
              ),
            ),
        ],
      ),
    );
  }
}
