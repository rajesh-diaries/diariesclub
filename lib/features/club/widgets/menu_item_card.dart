import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../providers/cart_provider.dart';
import 'quantity_stepper.dart';

/// One row in a brand menu list. Photo, name, description, GST-inclusive
/// price ("incl. GST" caption is universal — every price in-app is
/// inclusive). Sold-out items render dimmed with a "Sold out" badge.
class MenuItemCard extends ConsumerWidget {
  final Map<String, dynamic> item;
  const MenuItemCard({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final id = item['id'] as String;
    final name = item['name'] as String? ?? '';
    final description = item['description'] as String?;
    final pricePaise = (item['price_paise'] as int?) ?? 0;
    final brand = item['brand'] as String? ?? 'coffee';
    final imageUrl = item['image_url'] as String?;
    final disabled = item['is_available'] != true;

    final inCart =
        cart.items.where((i) => i.menuItemId == id).cast<CartItem?>().firstOrNull;
    final brandColor =
        brand == 'coffee' ? AppColors.coffeeBrown : AppColors.fitGreen;

    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.lightBorder),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 80,
                height: 80,
                child: imageUrl == null || imageUrl.isEmpty
                    ? Container(
                        color: brandColor.withValues(alpha: 0.20),
                        child: Icon(
                          brand == 'coffee'
                              ? PhosphorIconsFill.coffee
                              : PhosphorIconsFill.carrot,
                          color: brandColor,
                          size: 32,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: AppColors.lightBorder),
                        errorWidget: (_, __, ___) => Container(
                          color: brandColor.withValues(alpha: 0.20),
                          alignment: Alignment.center,
                          child: Icon(
                            brand == 'coffee'
                                ? PhosphorIconsFill.coffee
                                : PhosphorIconsFill.carrot,
                            color: brandColor,
                            size: 28,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppTextStyles.bodyLarge(context)),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Money.fromPaise(pricePaise),
                            style: AppTextStyles.bodyLarge(
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
                      const Spacer(),
                      if (disabled)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.adminRed.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Sold out',
                            style: AppTextStyles.caption(
                              context,
                              color: AppColors.adminRed,
                            ),
                          ),
                        )
                      else if (inCart != null)
                        QuantityStepper(
                          menuItemId: id,
                          currentQty: inCart.quantity,
                        )
                      else
                        OutlinedButton(
                          onPressed: cart.isCombo
                              ? null
                              : () {
                                  HapticFeedback.lightImpact();
                                  ref.read(cartProvider.notifier).addItem(
                                        CartItem(
                                          menuItemId: id,
                                          name: name,
                                          brand: brand,
                                          unitPricePaise: pricePaise,
                                          quantity: 1,
                                          imageUrl: imageUrl,
                                        ),
                                      );
                                },
                          child: const Text('Add'),
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
