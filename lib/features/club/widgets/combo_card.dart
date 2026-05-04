import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
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
    final isInCart = cart.comboId == id;
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
                        Text(
                          'incl. GST',
                          style: AppTextStyles.caption(
                            context,
                            color: AppColors.lightTextSecondary,
                          ),
                        ),
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
                if (isInCart)
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(cartProvider.notifier).removeCombo(),
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

  Future<void> _addCombo(
    BuildContext context,
    WidgetRef ref, {
    required List<Map<String, dynamic>> menuItems,
  }) async {
    final cart = ref.read(cartProvider);
    if (!cart.isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Replace bag?'),
          content: const Text(
            'Adding a combo replaces what you have in the bag right now.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep bag'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    HapticFeedback.mediumImpact();
    final cartItems = menuItems
        .map((it) => CartItem(
              menuItemId: it['id'] as String,
              name: (it['name'] as String?) ?? '',
              brand: (it['brand'] as String?) ?? 'coffee',
              unitPricePaise: (it['price_paise'] as int?) ?? 0,
              quantity: 1,
              imageUrl: it['image_url'] as String?,
            ))
        .toList();
    ref.read(cartProvider.notifier).applyCombo(
          comboId: combo['id'] as String,
          comboName: (combo['name'] as String?) ?? 'Combo',
          comboPricePaise: (combo['price_paise'] as int?) ?? 0,
          comboItems: cartItems,
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
