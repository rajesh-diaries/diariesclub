import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../providers/menu_items_provider.dart';
import 'menu_item_card.dart';

/// Shared layout for Coffee + FIT tabs. Hero strip + horizontal category
/// pills + vertical menu list. Categories come from the seeded items —
/// pulled live so adding a new category in admin lights up automatically.
class BrandMenuTab extends ConsumerWidget {
  final String brand; // 'coffee' | 'fit'
  final String title;
  final String tagline;
  /// Optional remote hero image. When null/empty the hero falls back to a
  /// brand-colored gradient — no placeholder URL is ever shown.
  final String? heroImage;
  final Color brandColor;
  final IconData brandIcon;

  const BrandMenuTab({
    super.key,
    required this.brand,
    required this.title,
    required this.tagline,
    this.heroImage,
    required this.brandColor,
    required this.brandIcon,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(menuItemsByBrandProvider(brand));
    final selectedCategory = ref.watch(menuCategoryFilterProvider(brand));

    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Empty(
        icon: brandIcon,
        message: "Couldn't load the menu. Pull to retry.",
        color: brandColor,
      ),
      data: (items) {
        final categories = _categoriesFrom(items);
        final filtered = selectedCategory == null
            ? items
            : items.where((i) => i['category'] == selectedCategory).toList();

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(menuItemsByBrandProvider(brand)),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Hero(
                  title: title,
                  tagline: tagline,
                  image: heroImage,
                  color: brandColor,
                  icon: brandIcon,
                ),
              ),
              if (categories.length > 1)
                SliverToBoxAdapter(
                  child: _CategoryPills(
                    brand: brand,
                    categories: categories,
                    selected: selectedCategory,
                  ),
                ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Empty(
                    icon: brandIcon,
                    color: brandColor,
                    message: items.isEmpty
                        ? '$title menu is coming soon.'
                        : 'Nothing here for that filter.',
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => MenuItemCard(item: filtered[i]),
                    childCount: filtered.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        );
      },
    );
  }

  List<String> _categoriesFrom(List<Map<String, dynamic>> items) {
    final seen = <String>{};
    for (final i in items) {
      final c = i['category'] as String?;
      if (c != null && c.isNotEmpty) seen.add(c);
    }
    final list = seen.toList()..sort();
    return list;
  }
}

class _Hero extends StatelessWidget {
  final String title;
  final String tagline;
  /// Null/empty → no network call; just renders a brand-colored gradient.
  final String? image;
  final Color color;
  final IconData icon;
  const _Hero({
    required this.title,
    required this.tagline,
    required this.image,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = image != null && image!.isNotEmpty;
    return SizedBox(
      height: 140,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasImage)
            CachedNetworkImage(
              imageUrl: image!,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  Container(color: color.withValues(alpha: 0.20)),
              errorWidget: (_, __, ___) =>
                  Container(color: color.withValues(alpha: 0.30)),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.55),
                    color.withValues(alpha: 0.20),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          if (hasImage)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.10),
                  ],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: AppTextStyles.h2(context, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  tagline,
                  style: AppTextStyles.body(context, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPills extends ConsumerWidget {
  final String brand;
  final List<String> categories;
  final String? selected;
  const _CategoryPills({
    required this.brand,
    required this.categories,
    required this.selected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => ref
                  .read(menuCategoryFilterProvider(brand).notifier)
                  .state = null,
            ),
          ),
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(_label(c)),
                selected: selected == c,
                onSelected: (v) => ref
                    .read(menuCategoryFilterProvider(brand).notifier)
                    .state = v ? c : null,
              ),
            ),
        ],
      ),
    );
  }

  String _label(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  const _Empty({
    required this.icon,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color.withValues(alpha: 0.40)),
            const SizedBox(height: 12),
            Text(
              message,
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
