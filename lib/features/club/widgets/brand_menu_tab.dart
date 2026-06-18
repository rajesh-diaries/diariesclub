import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../providers/club_search_provider.dart';
import '../providers/menu_items_provider.dart';
import 'menu_item_card.dart';

/// Shared layout for Coffee + FIT tabs. Horizontal category pills + vertical
/// menu list. Categories come from the seeded items — pulled live so adding a
/// new category in admin lights up automatically.
class BrandMenuTab extends ConsumerStatefulWidget {
  final String brand; // 'coffee' | 'fit'
  final String title;
  final Color brandColor;
  final IconData brandIcon;

  const BrandMenuTab({
    super.key,
    required this.brand,
    required this.title,
    required this.brandColor,
    required this.brandIcon,
  });

  @override
  ConsumerState<BrandMenuTab> createState() => _BrandMenuTabState();
}

class _BrandMenuTabState extends ConsumerState<BrandMenuTab> {
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(menuItemsByBrandProvider(widget.brand));
    final query = ref.watch(clubSearchQueryProvider);

    return itemsAsync.when(
      loading: () => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.navy),
            const SizedBox(height: 12),
            Text(
              'Loading ${widget.title}...',
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
      error: (e, _) => Center(
        child: BrandedErrorState(
          message: "Couldn't load the menu.",
          onRetry: () => ref.invalidate(menuItemsByBrandProvider(widget.brand)),
        ),
      ),
      data: (items) {
        final categories = _categoriesFrom(items);
        var filtered = items;
        if (_selectedCategory != null) {
          filtered = filtered.where((i) => i['category'] == _selectedCategory).toList();
        }
        if (query.isNotEmpty) {
          filtered = filtered.where((i) => _matchesQuery(i, query)).toList();
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(menuItemsByBrandProvider(widget.brand)),
          color: AppColors.navy,
          backgroundColor: Colors.white,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (categories.length > 1)
                SliverToBoxAdapter(
                  child: _CategoryPills(
                    categories: categories,
                    selected: _selectedCategory,
                    onSelected: (c) => setState(() => _selectedCategory = c),
                  ),
                ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: BrandedEmptyState(
                      icon: widget.brandIcon,
                      title: items.isEmpty
                          ? '${widget.title} menu is coming soon.'
                          : 'Nothing here for that filter.',
                    ),
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

class _CategoryPills extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _CategoryPills({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(
                'All',
                style: AppTextStyles.body(
                  context,
                  color: selected == null ? Colors.white : AppColors.navy,
                ),
              ),
              selected: selected == null,
              selectedColor: AppColors.navy,
              backgroundColor: AppColors.lightSurface,
              side: BorderSide(
                color: selected == null ? AppColors.navy : AppColors.lightBorder,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              showCheckmark: false,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(
                  _label(c),
                  style: AppTextStyles.body(
                    context,
                    color: selected == c ? Colors.white : AppColors.navy,
                  ),
                ),
                selected: selected == c,
                selectedColor: AppColors.navy,
                backgroundColor: AppColors.lightSurface,
                side: BorderSide(
                  color: selected == c ? AppColors.navy : AppColors.lightBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                showCheckmark: false,
                onSelected: (v) => onSelected(v ? c : null),
              ),
            ),
        ],
      ),
    );
  }

  String _label(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
