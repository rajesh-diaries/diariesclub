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
import 'providers/birthday_packages_provider.dart';
import 'providers/birthday_stats_provider.dart';
import 'providers/saved_packages_provider.dart';
import 'widgets/inquiry_bottom_sheet.dart';
import 'widgets/whatsapp_helpers.dart';

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
    final completed = ref.watch(completedBirthdayCountProvider).valueOrNull;

    final teamPhone =
        (venueCfg?['birthday_whatsapp_phone'] as String?)?.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Birthday packages'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            pkgsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => FriendlyErrorScreen(
                code: 'E-PKGS',
                userMessage: "Couldn't load packages",
                technicalDetails: e.toString(),
              ),
              data: (packages) => RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(birthdayPackagesProvider);
                  ref.invalidate(completedBirthdayCountProvider);
                  ref.invalidate(savedBirthdayPackageIdsProvider);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
                  children: [
                    if (completed != null && completed > 0)
                      _HostedCounter(count: completed),
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
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            if (teamPhone != null && teamPhone.isNotEmpty)
              Positioned(
                right: 16,
                bottom: 20,
                child: _FloatingWhatsappCta(teamPhone: teamPhone),
              ),
          ],
        ),
      ),
    );
  }
}

/// Social-proof banner — "Hosted 247 parties so far" — at the top of
/// the screen. Pulled live from completed birthday_reservations count.
class _HostedCounter extends StatelessWidget {
  final int count;
  const _HostedCounter({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.20),
            AppColors.rafiCoral.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsFill.confetti, color: AppColors.navy),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Hosted $count happy birthdays so far ✨',
              style: AppTextStyles.bodyLarge(context),
            ),
          ),
        ],
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
    final description = (p['description'] as String?) ?? '';
    final tier = p['tier'] as String?;
    final cover = p['cover_image_url'] as String?;
    final priceVeg = (p['price_per_pax_veg_paise'] as int?) ?? 0;
    final priceNonVeg = (p['price_per_pax_non_veg_paise'] as int?) ?? 0;
    final hallName = (p['hall_name'] as String?) ?? '';
    final minGuests = (p['min_guests'] as int?) ?? 0;
    final maxGuests = (p['max_guests'] as int?) ?? 0;
    // Per-package pdf_url retired; brochure is now a single venue-level
    // PDF rendered at the top of the screen via _TopBrochureRow.

    final menuLines = ((p['inclusions'] as List?) ?? const [])
        .whereType<String>()
        .toList();
    final experienceLines =
        ((p['experience_inclusions'] as List?) ?? const [])
            .whereType<String>()
            .toList();
    final nonFoodOfferings =
        ((p['non_food_offerings'] as List?) ?? const [])
            .whereType<String>()
            .toList();

    final badge = tier == 'magical'
        ? const _Badge(text: 'Premium', color: AppColors.navy)
        : tier == 'happy_tales'
            ? const _Badge(text: 'Most Booked', color: AppColors.gold)
            : null;

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
          // Hero photo — the visual lead.
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: cover == null || cover.isEmpty
                    ? Container(
                        color: AppColors.gold.withValues(alpha: 0.30),
                        alignment: Alignment.center,
                        child: const Icon(
                          PhosphorIconsFill.cake,
                          color: AppColors.gold,
                          size: 56,
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
                Positioned(top: 12, left: 12, child: badge),
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
                Text(name, style: AppTextStyles.h2(context)),
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
                const SizedBox(height: 12),

                // Price row — clearer than "per pax".
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _PriceChip(label: 'Veg', pricePaise: priceVeg),
                    _PriceChip(label: 'Non-Veg', pricePaise: priceNonVeg),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'per guest · 18% GST extra',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),

                // Experience first — the headline benefit.
                if (experienceLines.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _ExperienceBlock(lines: experienceLines),
                ],

                if (description.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    description,
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],

                // Menu — collapsed by default. Expander keeps cards short.
                if (menuLines.isNotEmpty || nonFoodOfferings.isNotEmpty) ...[
                  const SizedBox(height: 16),
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
                                ? 'Hide menu & extras'
                                : 'See menu & extras',
                            style: AppTextStyles.bodyLarge(context)
                                .copyWith(color: AppColors.navy),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _menuExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
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
                        if (menuLines.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _SectionEyebrow(text: 'MENU'),
                          const SizedBox(height: 6),
                          _InclusionsGrid(lines: menuLines),
                        ],
                        if (nonFoodOfferings.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _SectionEyebrow(text: 'DECOR & EXTRAS'),
                          const SizedBox(height: 6),
                          _InclusionsGrid(lines: nonFoodOfferings),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // Inquire CTA — opens the bottom sheet, no new screen.
                // Brochure (PDF) + Send to WhatsApp moved to a screen-level
                // row at the top of BirthdayPackagesScreen — the PDF is a
                // single venue-wide brochure now, not per-package.
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
                    child: const Text(
                      'Inquire',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
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
  const _PriceChip({required this.label, required this.pricePaise});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '$label ${Money.fromPaise(pricePaise)}',
        style: AppTextStyles.body(context).copyWith(
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

class _SectionEyebrow extends StatelessWidget {
  final String text;
  const _SectionEyebrow({required this.text});
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.caption(
        context,
        color: AppColors.lightTextSecondary,
      ).copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w800),
    );
  }
}

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

class _ExperienceBlock extends StatelessWidget {
  final List<String> lines;
  const _ExperienceBlock({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EXPERIENCE',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ).copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 16,
                    color: AppColors.navy,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(line, style: AppTextStyles.body(context)),
                  ),
                ],
              ),
            ),
        ],
      ),
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

class _FloatingWhatsappCta extends ConsumerWidget {
  final String teamPhone;
  const _FloatingWhatsappCta({required this.teamPhone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton.extended(
      backgroundColor: AppColors.activeGreen,
      foregroundColor: Colors.white,
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
      icon: const Icon(PhosphorIconsFill.whatsappLogo),
      label: const Text(
        'Talk to our team',
        style: TextStyle(fontWeight: FontWeight.w700),
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
