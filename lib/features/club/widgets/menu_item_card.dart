import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
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
    final id = item['id'] as String;
    final name = item['name'] as String? ?? '';
    final description = item['description'] as String?;
    final pricePaise = (item['price_paise'] as int?) ?? 0;
    final offerPricePaise = (item['offer_price_paise'] as int?) ?? 0;
    final offerLabel = item['offer_label'] as String?;
    final prepTimeMinutes = (item['prep_time_minutes'] as int?) ?? 0;
    final dietaryType = item['dietary_type'] as String?;
    final brand = item['brand'] as String? ?? 'coffee';
    final imageUrl = item['image_url'] as String?;
    final disabled = item['is_available'] != true;

    final quantity = ref.watch(
      cartProvider.select(
        (cart) =>
            cart.lines
                .whereType<MenuItemLine>()
                .where((l) => l.menuItemId == id)
                .firstOrNull
                ?.quantity ??
            0,
      ),
    );

    final effectivePricePaise =
        (offerPricePaise > 0 && offerPricePaise < pricePaise)
        ? offerPricePaise
        : pricePaise;
    final hasOffer = effectivePricePaise < pricePaise;

    final tags = _parseStringList(item['tags']);
    final symbols = _parseStringList(item['symbols']);

    final brandColor = brand == 'coffee'
        ? AppColors.coffeeBrown
        : AppColors.fitGreen;

    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          borderRadius: BorderRadius.circular(kHomeCardRadius),
          border: Border.all(color: AppColors.lightBorder),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dietaryType != null && dietaryType.isNotEmpty) ...[
                        _DietaryDot(type: dietaryType),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          name,
                          style: AppTextStyles.bodyLarge(context),
                        ),
                      ),
                      if (symbols.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _SymbolRow(symbols: symbols),
                      ],
                    ],
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _TagPills(tags: tags),
                  ],
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 4),
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
                  const SizedBox(height: 10),
                  if (hasOffer &&
                      offerLabel != null &&
                      offerLabel.isNotEmpty &&
                      !disabled) ...[
                    _OfferLabelBadge(label: offerLabel),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (hasOffer)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              Money.fromPaise(effectivePricePaise),
                              style: AppTextStyles.bodyLarge(
                                context,
                                color: AppColors.navy,
                              ),
                            ),
                            Text(
                              Money.fromPaise(pricePaise),
                              style:
                                  AppTextStyles.caption(
                                    context,
                                    color: AppColors.lightTextSecondary,
                                  ).copyWith(
                                    decoration: TextDecoration.lineThrough,
                                  ),
                            ),
                          ],
                        )
                      else
                        Text(
                          Money.fromPaise(pricePaise),
                          style: AppTextStyles.bodyLarge(
                            context,
                            color: AppColors.navy,
                          ),
                        ),
                      const Spacer(),
                      if (prepTimeMinutes > 0 && !disabled) ...[
                        _PrepTimeBadge(minutes: prepTimeMinutes),
                        const SizedBox(width: 8),
                      ],
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
                      else if (quantity > 0)
                        QuantityStepper(menuItemId: id, currentQty: quantity)
                      else
                        SizedBox(
                          height: 36,
                          child: FilledButton(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              ref
                                  .read(cartProvider.notifier)
                                  .addMenuItem(
                                    MenuItemLine.create(
                                      menuItemId: id,
                                      name: name,
                                      brand: brand,
                                      unitPricePaise: effectivePricePaise,
                                      quantity: 1,
                                      imageUrl: imageUrl,
                                    ),
                                  );
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.navy,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(64, 36),
                              maximumSize: const Size(120, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                            child: Text(
                              'Add',
                              style: AppTextStyles.body(
                                context,
                                color: Colors.white,
                              ).copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
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

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value.whereType<String>().where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }
}

class _SymbolRow extends StatelessWidget {
  final List<String> symbols;
  const _SymbolRow({required this.symbols});

  @override
  Widget build(BuildContext context) {
    final icons = symbols.map(_symbolToIcon).whereType<IconData>().toList();
    if (icons.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final icon in icons)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(icon, size: 16, color: AppColors.lightTextSecondary),
          ),
      ],
    );
  }

  IconData? _symbolToIcon(String symbol) {
    switch (symbol.toLowerCase()) {
      case 'chilli':
      case 'spicy':
        return PhosphorIconsFill.pepper;
      case 'leaf':
      case 'healthy':
      case 'vegetarian':
        return PhosphorIconsFill.leaf;
      case 'star':
      case 'bestseller':
        return PhosphorIconsFill.star;
      case 'flame':
      case 'new':
        return PhosphorIconsFill.fire;
      case 'heart':
      case 'popular':
        return PhosphorIconsFill.heart;
      case 'timer':
        return PhosphorIconsFill.timer;
      default:
        return null;
    }
  }
}

class _DietaryDot extends StatelessWidget {
  final String type;
  const _DietaryDot({required this.type});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (type.toLowerCase()) {
      'veg' => (Colors.green, 'Veg'),
      'non_veg' => (Colors.red, 'Non-veg'),
      'egg' => (Colors.amber, 'Egg'),
      'customizable' => (Colors.blue, 'Customizable'),
      _ => (AppColors.lightTextSecondary, type),
    };

    return Tooltip(
      message: label,
      child: Container(
        width: 12,
        height: 12,
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.lightSurface,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagPills extends StatelessWidget {
  final List<String> tags;
  const _TagPills({required this.tags});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final t in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.lightBorder.withValues(alpha: 0.60),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              t,
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

class _PrepTimeBadge extends StatelessWidget {
  final int minutes;
  const _PrepTimeBadge({required this.minutes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.lightBorder.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            PhosphorIconsRegular.timer,
            size: 13,
            color: AppColors.lightTextSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            '$minutes min',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferLabelBadge extends StatelessWidget {
  final String label;
  const _OfferLabelBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption(
          context,
          color: AppColors.coffeeBrownDeep,
        ).copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}
