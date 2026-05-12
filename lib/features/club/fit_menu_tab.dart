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
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final fitAppUrl = (cfg['fit_app_url'] as String?)?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openFitWhatsApp(context, ref),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.fitGreen.withValues(alpha: 0.95),
                    AppColors.fitGreen.withValues(alpha: 0.75),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(PhosphorIconsFill.forkKnife,
                      color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FIT meal subscriptions — delivered home',
                          style: AppTextStyles.h3(context, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Daily, weekly, monthly plans · '
                          'Tap to chat on WhatsApp →',
                          style: AppTextStyles.body(
                            context,
                            color: Colors.white.withValues(alpha: 0.92),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (fitAppUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Already use the FIT app?',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    onPressed: () => launchUrl(
                      Uri.parse(fitAppUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(
                      'Open it →',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.fitGreen,
                      ).copyWith(fontWeight: FontWeight.w800),
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
    final templates = async.valueOrNull ?? const [];
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
            if (photo != null && photo.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 8,
                child: Image.network(
                  photo,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.fitGreen.withValues(alpha: 0.15),
                  ),
                ),
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
                  if (desc != null && desc.isNotEmpty) ...[
                    const SizedBox(height: 4),
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

/// À la carte legacy menu_items where brand='fit'. Rendered inline as
/// flat MenuItemCard widgets — never as its own scrollable — so it
/// nests safely inside the parent ListView.
class _AlaCarteSection extends ConsumerWidget {
  const _AlaCarteSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(menuItemsByBrandProvider('fit'));
    final items = async.valueOrNull ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();

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
          for (final i in items) MenuItemCard(item: i),
        ],
      ),
    );
  }
}

/// Customer-visible templates: only published+available, ordered by sort.
final fitTemplatesCustomerProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('fit_meal_templates')
      .select('id, name, description, base_price_paise, photo_url, sort_order')
      .order('sort_order', ascending: true);
  return List<Map<String, dynamic>>.from(rows);
});
