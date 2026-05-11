import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../home/widgets/combo_purchase_sheet.dart';
import '../providers/cart_provider.dart';
import '../providers/combos_provider.dart';

/// Combo card on the Combos tab. Replaces the cart on "Add" — shows a
/// confirm dialog if the cart already has items.
class ComboCard extends ConsumerWidget {
  final Map<String, dynamic> combo;
  const ComboCard({super.key, required this.combo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final id = combo['id'] as String;
    final name = (combo['name'] as String?) ?? '';
    final description = combo['description'] as String?;
    final cover = combo['cover_image_url'] as String?;
    final price = (combo['price_paise'] as int?) ?? 0;
    final inclusions = (combo['inclusions'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final isInCart = cart.lines.any(
      (l) => l is ComboLine && l.comboId == id,
    );
    final menuItemIds = ((inclusions['menu_item_ids'] as List?) ?? const [])
        .cast<String>();
    final sessionMinutes = inclusions['session_minutes'] as int?;
    final marketing = inclusions['description'] as String?;

    final menuItemsAsync = ref.watch(comboMenuItemsProvider(menuItemIds));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF6E5), Color(0xFFFEFCF8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.40),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: cover == null
                ? Container(color: AppColors.gold.withValues(alpha: 0.30))
                : CachedNetworkImage(
                    imageUrl: cover,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        Container(color: AppColors.gold.withValues(alpha: 0.30)),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: AppTextStyles.h3(context),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          Money.fromPaise(price),
                          style: AppTextStyles.h2(
                            context,
                            color: AppColors.navy,
                          ),
                        ),
                        // GST shown at billing — see cart breakdown.
                      ],
                    ),
                  ],
                ),
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text('Includes',
                    style: AppTextStyles.caption(context).copyWith(
                      letterSpacing: 1.0,
                      color: AppColors.lightTextSecondary,
                      fontWeight: FontWeight.w800,
                    )),
                const SizedBox(height: 4),
                if (sessionMinutes != null)
                  _IncludedRow(
                    icon: PhosphorIconsRegular.timer,
                    text: '$sessionMinutes min play session (redeem at desk)',
                  ),
                ...menuItemsAsync.when(
                  data: (items) => items
                      .map((it) => _IncludedRow(
                            icon: it['brand'] == 'fit'
                                ? PhosphorIconsRegular.carrot
                                : PhosphorIconsRegular.coffee,
                            text: (it['name'] as String?) ?? '—',
                          ))
                      .toList(),
                  loading: () => const [
                    _IncludedRow(
                      icon: PhosphorIconsRegular.dotsThree,
                      text: 'Loading items…',
                    ),
                  ],
                  error: (_, __) => const [],
                ),
                if (marketing != null && marketing.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    marketing,
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (sessionMinutes != null)
                  // Session combos must go through the modal sheet so the
                  // kid picker is unmissable. Cart-add is BLOCKED for these
                  // — without a kid pick, no session_create fires and the
                  // customer pays for play they never receive.
                  FilledButton.icon(
                    onPressed: () => _openSheet(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(PhosphorIconsRegular.playCircle),
                    label: const Text('Pick a kid · Place order'),
                  )
                else if (isInCart)
                  OutlinedButton.icon(
                    onPressed: () => ref
                        .read(cartProvider.notifier)
                        .removeLineById('combo:$id'),
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Remove from bag'),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => _addCombo(
                      context,
                      ref,
                      menuItems: menuItemsAsync.valueOrNull ?? const [],
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Add combo to bag'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (_) => ComboPurchaseSheet(combo: combo),
    );
  }

  Future<void> _addCombo(
    BuildContext context,
    WidgetRef ref, {
    required List<Map<String, dynamic>> menuItems,
  }) async {
    // Module 2.5/2.6 follow-up: combos are now regular line items that
    // coexist freely with à-la-carte and FIT meals. No more "replace bag"
    // confirmation; addCombo merges by combo_id (quantity stack).
    HapticFeedback.mediumImpact();
    final names = menuItems
        .map((it) => (it['name'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    ref.read(cartProvider.notifier).addCombo(
          ComboLine.create(
            comboId: combo['id'] as String,
            name: (combo['name'] as String?) ?? 'Combo',
            unitPricePaise: (combo['price_paise'] as int?) ?? 0,
            quantity: 1,
            imageUrl: combo['cover_image_url'] as String?,
            includedItemNames: names,
          ),
        );
  }
}

class _IncludedRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _IncludedRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.activeGreen),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppTextStyles.body(context))),
        ],
      ),
    );
  }
}
