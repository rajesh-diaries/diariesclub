import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/venue_config_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../club/providers/combos_provider.dart';

/// Horizontal scroll of active combos on the home tab. Each card shows
/// cover + name + bundled price + 'Save ₹X' badge + struck-through
/// à-la-carte total. Tap → /club (combos tab).
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
          height: 250,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: combos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) =>
                _ComboMiniCard(combo: combos[i], key: ValueKey(combos[i]['id'])),
          ),
        ),
      ],
    );
  }
}

/// StatefulWidget so we can fetch the menu_items + venue_config once
/// in initState and cache the savings result. Previous version watched
/// `comboMenuItemsProvider(menuItemIds)` directly — but the family key
/// (List<String>) doesn't have stable equality in Dart, so the family
/// re-keyed every rebuild and the lookup never settled.
class _ComboMiniCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> combo;
  const _ComboMiniCard({super.key, required this.combo});

  @override
  ConsumerState<_ComboMiniCard> createState() => _ComboMiniCardState();
}

class _ComboMiniCardState extends ConsumerState<_ComboMiniCard> {
  int? _alacartePaise; // null = still loading

  @override
  void initState() {
    super.initState();
    _computeSavings();
  }

  Future<void> _computeSavings() async {
    final inclusions =
        (widget.combo['inclusions'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final menuItemIds = ((inclusions['menu_item_ids'] as List?) ?? const [])
        .cast<String>();
    final sessionMinutes = inclusions['session_minutes'] as int?;

    var sum = 0;
    if (menuItemIds.isNotEmpty) {
      try {
        final rows = await Supabase.instance.client
            .from('menu_items_with_brand')
            .select('price_paise')
            .inFilter('id', menuItemIds);
        for (final r in (rows as List)) {
          sum += ((r as Map)['price_paise'] as int?) ?? 0;
        }
      } catch (_) {
        // Silent — savings just won't show.
      }
    }

    if (sessionMinutes != null) {
      final cfg = ref.read(venueConfigProvider).valueOrNull;
      if (cfg != null) {
        sum += sessionMinutes == 60
            ? (cfg['session_1hr_price_paise'] as int?) ?? 80000
            : sessionMinutes == 120
                ? (cfg['session_2hr_price_paise'] as int?) ?? 110000
                : 0;
      }
    }

    if (!mounted) return;
    setState(() => _alacartePaise = sum);
  }

  @override
  Widget build(BuildContext context) {
    final combo = widget.combo;
    final name = (combo['name'] as String?) ?? '';
    final cover = combo['cover_image_url'] as String?;
    final price = (combo['price_paise'] as int?) ?? 0;

    final showSavings =
        _alacartePaise != null && _alacartePaise! > price;
    final savings = showSavings ? _alacartePaise! - price : 0;

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
                  if (showSavings)
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
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                    const SizedBox(height: 4),
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
                        if (showSavings) ...[
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              Money.fromPaise(_alacartePaise!),
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
