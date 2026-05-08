import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/venue_config_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../club/providers/combos_provider.dart';

/// Horizontal scroll of active combos on the home tab. Each card shows
/// cover + name + bundled price + 'Save ₹X' badge (computed from the
/// combo's inclusions vs. à-la-carte sum). Tap → /club (combos tab).
class HomeCombosStrip extends ConsumerWidget {
  const HomeCombosStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final combos = ref.watch(combosProvider).valueOrNull ?? const [];
    if (combos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Quick combos', style: AppTextStyles.h3(context)),
            ),
            TextButton(
              onPressed: () => context.go('/club'),
              child: const Text('See all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: combos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _ComboMiniCard(combo: combos[i]),
          ),
        ),
      ],
    );
  }
}

class _ComboMiniCard extends ConsumerWidget {
  final Map<String, dynamic> combo;
  const _ComboMiniCard({required this.combo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = (combo['name'] as String?) ?? '';
    final cover = combo['cover_image_url'] as String?;
    final price = (combo['price_paise'] as int?) ?? 0;
    final inclusions = (combo['inclusions'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final menuItemIds = ((inclusions['menu_item_ids'] as List?) ?? const [])
        .cast<String>();
    final sessionMinutes = inclusions['session_minutes'] as int?;

    final menuItemsAsync = ref.watch(comboMenuItemsProvider(menuItemIds));
    final cfg = ref.watch(venueConfigProvider).valueOrNull;

    int? alacarte;
    menuItemsAsync.whenData((items) {
      var sum = 0;
      for (final mi in items) {
        sum += (mi['price_paise'] as int?) ?? 0;
      }
      if (sessionMinutes != null && cfg != null) {
        sum += sessionMinutes == 60
            ? (cfg['session_1hr_price_paise'] as int?) ?? 80000
            : sessionMinutes == 120
                ? (cfg['session_2hr_price_paise'] as int?) ?? 110000
                : 0;
      }
      alacarte = sum;
    });
    final savings =
        (alacarte != null && alacarte! > price) ? alacarte! - price : 0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.go('/club'),
      child: SizedBox(
        width: 220,
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
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 10,
                    child: cover == null || cover.isEmpty
                        ? Container(
                            color: AppColors.gold.withValues(alpha: 0.20),
                            alignment: Alignment.center,
                            child: const Icon(
                              PhosphorIconsFill.gift,
                              color: AppColors.navy,
                              size: 36,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: cover,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.gold.withValues(alpha: 0.20),
                            ),
                          ),
                  ),
                  if (savings > 0)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.activeGreen,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          'Save ${Money.fromPaise(savings)}',
                          style: AppTextStyles.caption(
                            context,
                            color: Colors.white,
                          ).copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTextStyles.body(context).copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          Money.fromPaise(price),
                          style: AppTextStyles.h3(
                            context,
                            color: AppColors.navy,
                          ),
                        ),
                        if (alacarte != null && alacarte! > price) ...[
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              Money.fromPaise(alacarte!),
                              style: AppTextStyles.caption(
                                context,
                                color: AppColors.lightTextSecondary,
                              ).copyWith(
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                        ],
                      ],
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
