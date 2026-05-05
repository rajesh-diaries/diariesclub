import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import 'widgets/brand_menu_tab.dart';

/// FIT customer tab. Three sections stacked:
///   1. Subscription waitlist banner (capture email for the upcoming
///      weekly-delivery flow).
///   2. "Build your meal" — fit_meal_templates as cards. Tap → builder.
///   3. Legacy menu_items list (brand='fit') for backward compat with
///      pre-Module-2.5 seed data.
class FitMenuTab extends ConsumerWidget {
  const FitMenuTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: const [
        _SubscriptionBanner(),
        _FitTemplatesSection(),
        // Legacy menu_items section.
        _LegacyMenuSection(),
      ],
    );
  }
}

class _SubscriptionBanner extends ConsumerWidget {
  const _SubscriptionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showWaitlistModal(context, ref),
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
              const Icon(PhosphorIconsFill.calendarCheck,
                  color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Coming soon: FIT meals delivered weekly',
                      style: AppTextStyles.h3(context, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to join the waitlist →',
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
    );
  }
}

Future<void> _showWaitlistModal(BuildContext context, WidgetRef ref) async {
  final emailCtrl = TextEditingController();
  bool busy = false;
  String? error;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (_, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Join the FIT waitlist', style: AppTextStyles.h2(sheetCtx)),
            const SizedBox(height: 8),
            Text(
              "We'll email you when weekly delivery launches in your area. "
              'No spam.',
              style: AppTextStyles.body(
                sheetCtx,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'you@example.com',
                border: OutlineInputBorder(),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: AppTextStyles.caption(
                sheetCtx, color: AppColors.adminRed,
              )),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim();
                      if (email.isEmpty || !email.contains('@')) {
                        setSt(() => error = 'Please enter a valid email.');
                        return;
                      }
                      setSt(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await Supabase.instance.client.rpc<dynamic>(
                          'fit_subscription_waitlist_join',
                          params: {'p_email': email},
                        );
                        if (!sheetCtx.mounted) return;
                        Navigator.of(sheetCtx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('You\'re on the list — thanks!'),
                          ),
                        );
                      } catch (e) {
                        if (!sheetCtx.mounted) return;
                        setSt(() {
                          busy = false;
                          error = 'Could not save: $e';
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Text('Join waitlist'),
            ),
          ],
        ),
      ),
    ),
  );
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

class _LegacyMenuSection extends StatelessWidget {
  const _LegacyMenuSection();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 16),
      child: BrandMenuTab(
        brand: 'fit',
        title: 'À la carte',
        tagline: 'Quick picks from the FIT menu.',
        heroImage:
            'https://placehold.co/1200x600/0D4A2E/FFFFFF.png?text=FIT+Diaries',
        brandColor: AppColors.fitGreen,
        brandIcon: PhosphorIconsFill.carrot,
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
