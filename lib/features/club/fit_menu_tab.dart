import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/current_family_provider.dart';
import '../../core/providers/venue_config_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton_card.dart';
import 'providers/club_search_provider.dart';
import 'providers/menu_items_provider.dart';
import 'widgets/menu_item_card.dart';

/// FIT customer tab. Three sections, all rendered inline (no nested
/// scrollables — that previously crashed with 'Vertical viewport was
/// given unbounded height'):
///   1. Subscription waitlist banner.
///   2. "Build your meal" — fit_meal_templates from admin.
///   3. À la carte — menu_items where brand='fit', from admin.
class FitMenuTab extends ConsumerWidget {
  const FitMenuTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: const [
        _SubscriptionBanner(),
        _FitTemplatesSection(),
        _AlaCarteSection(),
        SizedBox(height: 32),
      ],
    );
  }
}

class _SubscriptionBanner extends ConsumerWidget {
  const _SubscriptionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: () => _openFitWhatsApp(context, ref),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.fitGreen,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            children: [
              const Icon(PhosphorIconsFill.whatsappLogo,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Subscription plans at home',
                  style: AppTextStyles.body(context, color: Colors.white)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(PhosphorIconsRegular.arrowRight, color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openFitWhatsApp(BuildContext context, WidgetRef ref) async {
  final cfg = ref.read(venueConfigProvider).valueOrNull ?? const {};
  // Prefer the dedicated FIT line; fall back to the main venue WhatsApp.
  final phone = (cfg['fit_whatsapp_phone'] as String?)?.trim().isNotEmpty == true
      ? cfg['fit_whatsapp_phone'] as String
      : (cfg['whatsapp_support_phone'] as String?) ?? '';
  if (phone.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('FIT subscription channel not configured yet.')),
    );
    return;
  }
  final familyName = ref
          .read(currentFamilyProvider)
          .valueOrNull?['name'] as String? ??
      '';
  final greeting = familyName.isEmpty ? 'Hi!' : 'Hi! I\'m $familyName.';
  final msg =
      "$greeting I'd like to know about FIT meal subscription plans "
      "(daily / weekly / monthly). What's the best fit for my family?";
  final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
  final uri = Uri.parse(
      'https://wa.me/$digits?text=${Uri.encodeComponent(msg)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _FitTemplatesSection extends ConsumerWidget {
  const _FitTemplatesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fitTemplatesCustomerProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: SkeletonList(itemCount: 2, itemHeight: 220),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: BrandedErrorState(
          message: "Couldn't load meal templates",
          onRetry: () => ref.invalidate(fitTemplatesCustomerProvider),
        ),
      ),
      data: (templates) {
        if (templates.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Build your meal', style: AppTextStyles.h2(context)),
              const SizedBox(height: 4),
              Text(
                'Pick a base, then customize the way you like.',
                style: AppTextStyles.body(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 12),
              for (final t in templates) ...[
                _TemplateCard(template: t),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final Map<String, dynamic> template;
  const _TemplateCard({required this.template});

  @override
  Widget build(BuildContext context) {
    final photo = template['photo_url'] as String?;
    final name = (template['name'] as String?) ?? '—';
    final desc = template['description'] as String?;
    final basePrice = (template['base_price_paise'] as int?) ?? 0;
    final showVeg = (template['_showVeg'] as bool?) ?? false;
    final showNonVeg = (template['_showNonVeg'] as bool?) ?? false;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () =>
          context.push('/club/fit/builder/${template['id']}'),
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
            AspectRatio(
              aspectRatio: 1 / 1,
              child: photo != null && photo.isNotEmpty
                  ? Container(
                      color: AppColors.lightSurface,
                      child: CachedNetworkImage(
                        imageUrl: photo,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => _ImagePlaceholder(),
                        errorWidget: (_, __, ___) => _ImagePlaceholder(),
                      ),
                    )
                  : _ImagePlaceholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name, style: AppTextStyles.h3(context)),
                      ),
                      Text(
                        'from ${Money.fromPaise(basePrice)}',
                        style: AppTextStyles.bodyLarge(
                          context,
                          color: AppColors.fitGreen,
                        ).copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  if (showVeg || showNonVeg) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (showVeg) _DietaryBadge(type: 'veg'),
                        if (showNonVeg) _DietaryBadge(type: 'non_veg'),
                      ],
                    ),
                  ],
                  if (desc != null && desc.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      desc,
                      style: AppTextStyles.body(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Spacer(),
                      Text(
                        'Customize →',
                        style: AppTextStyles.body(
                          context,
                          color: AppColors.fitGreen,
                        ).copyWith(fontWeight: FontWeight.w700),
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
}

class _ImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.fitGreen.withValues(alpha: 0.12),
            AppColors.gold.withValues(alpha: 0.08),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        PhosphorIconsFill.bowlFood,
        size: 40,
        color: AppColors.fitGreen.withValues(alpha: 0.35),
      ),
    );
  }
}

class _DietaryBadge extends StatelessWidget {
  final String type;
  const _DietaryBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final isVeg = type == 'veg';
    final label = isVeg ? 'Veg' : 'Non-Veg';
    final color = isVeg ? AppColors.activeGreen : AppColors.rafiCoral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.40)),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
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

/// À la carte legacy menu_items where brand='fit'. Rendered inline as
/// flat MenuItemCard widgets — never as its own scrollable — so it
/// nests safely inside the parent ListView.
class _AlaCarteSection extends ConsumerWidget {
  const _AlaCarteSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(menuItemsByBrandProvider('fit'));
    final query = ref.watch(clubSearchQueryProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: SkeletonList(itemCount: 3, itemHeight: 96),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: BrandedErrorState(
          message: "Couldn't load FIT menu",
          onRetry: () => ref.invalidate(menuItemsByBrandProvider('fit')),
        ),
      ),
      data: (items) {
        final filtered = query.isEmpty
            ? items
            : items.where((i) => _matchesQuery(i, query)).toList();
        if (filtered.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('À la carte', style: AppTextStyles.h2(context)),
              const SizedBox(height: 4),
              Text(
                'Quick picks from the FIT menu.',
                style: AppTextStyles.body(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 12),
              for (final i in filtered) MenuItemCard(item: i),
            ],
          ),
        );
      },
    );
  }

  bool _matchesQuery(Map<String, dynamic> item, String query) {
    final haystack = [
      item['name']?.toString() ?? '',
      item['description']?.toString() ?? '',
      item['category']?.toString() ?? '',
      ...(item['tags'] as List<dynamic>? ?? []).map((t) => t.toString()),
      ...(item['symbols'] as List<dynamic>? ?? []).map((s) => s.toString()),
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }
}

/// Customer-visible templates: only published+available, ordered by sort.
/// Also computes Veg / Non-Veg badge visibility: admin override wins,
/// otherwise we look at the dietary_type of published, available options.
final fitTemplatesCustomerProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;
  final rows = await supabase
      .from('fit_meal_templates')
      .select(
        'id, name, description, base_price_paise, photo_url, sort_order, veg_available, non_veg_available',
      )
      .order('sort_order', ascending: true);
  final templates = List<Map<String, dynamic>>.from(rows);
  if (templates.isEmpty) return templates;

  final templateIds = templates.map((t) => t['id'] as String).toList();

  // Pull the category links for these templates.
  final links = await supabase
      .from('fit_meal_template_categories')
      .select('template_id, category_id, fit_meal_categories!inner(slug)')
      .inFilter('template_id', templateIds);

  final categoryIds = <String>{};
  final linksByTemplate = <String, List<Map<String, dynamic>>>{};
  for (final l in links) {
    final tid = l['template_id'] as String;
    final cid = l['category_id'] as String;
    categoryIds.add(cid);
    linksByTemplate.putIfAbsent(tid, () => []).add(l);
  }

  // Fetch the options for those categories.
  final options = categoryIds.isEmpty
      ? <Map<String, dynamic>>[]
      : await supabase
          .from('fit_meal_options')
          .select('category_id, dietary_type, is_available, is_published')
          .inFilter('category_id', categoryIds.toList());

  final optionsByCategory = <String, List<Map<String, dynamic>>>{};
  for (final o in options) {
    final cid = o['category_id'] as String;
    optionsByCategory.putIfAbsent(cid, () => []).add(o);
  }

  for (final t in templates) {
    final tid = t['id'] as String;
    final overrideVeg = t['veg_available'] as bool?;
    final overrideNonVeg = t['non_veg_available'] as bool?;

    bool autoVeg = false;
    bool autoNonVeg = false;
    for (final l in linksByTemplate[tid] ?? []) {
      final cid = l['category_id'] as String;
      for (final opt in optionsByCategory[cid] ?? []) {
        if ((opt['is_available'] as bool? ?? true) == false) continue;
        if ((opt['is_published'] as bool? ?? true) == false) continue;
        final dt = opt['dietary_type'] as String?;
        if (dt == 'veg') autoVeg = true;
        if (dt == 'non_veg') autoNonVeg = true;
      }
    }

    t['_showVeg'] = overrideVeg ?? autoVeg;
    t['_showNonVeg'] = overrideNonVeg ?? autoNonVeg;
  }

  return templates;
});
