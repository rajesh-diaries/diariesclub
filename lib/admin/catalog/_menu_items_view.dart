import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../widgets/admin_list_scaffold.dart';

/// Shared list view for Coffee/FIT menus. Both surfaces read from the same
/// menu_items table filtered by menus.brand. Splitting them into two
/// screens keeps the URLs and admin nav clean while reusing the table
/// rendering. Module 2.4 will replace the Coffee variant with full CRUD.
class MenuItemsView extends ConsumerWidget {
  final String brand; // 'coffee' or 'fit'
  final String title;
  final String? subtitle;
  final String placeholderBanner;
  final String emptyMessage;
  final String? emptySubtitle;
  final IconData emptyIcon;

  const MenuItemsView({
    super.key,
    required this.brand,
    required this.title,
    required this.placeholderBanner,
    required this.emptyMessage,
    required this.emptyIcon,
    this.subtitle,
    this.emptySubtitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(menuItemsByBrandProvider(brand));
    return AdminListScaffold(
      title: title,
      subtitle: subtitle,
      placeholderBanner: placeholderBanner,
      isEmpty: async.maybeWhen(
        data: (rows) => rows.isEmpty,
        orElse: () => false,
      ),
      emptyState: AdminListEmptyState(
        icon: emptyIcon,
        message: emptyMessage,
        subtitle: emptySubtitle,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) => _Table(rows: rows),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _Table({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('')),
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Category')),
              DataColumn(label: Text('Price'), numeric: true),
              DataColumn(label: Text('Sort'), numeric: true),
              DataColumn(label: Text('Available')),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(_thumb(r['image_url'] as String?)),
                  DataCell(Text((r['name'] as String?) ?? '—')),
                  DataCell(Text(
                    (r['category'] as String?) ?? '—',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  )),
                  DataCell(Text(
                    Money.fromPaise((r['price_paise'] as int?) ?? 0),
                  )),
                  DataCell(Text('${r['sort_order'] ?? 0}')),
                  DataCell(_AvailabilityBadge(
                    isAvailable: (r['is_available'] as bool?) ?? true,
                  )),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb(String? url) {
    if (url == null || url.isEmpty) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.lightBackground,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(
          PhosphorIconsRegular.image,
          size: 16,
          color: AppColors.lightTextSecondary,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        url,
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 32,
          height: 32,
          color: AppColors.lightBackground,
        ),
      ),
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  final bool isAvailable;
  const _AvailabilityBadge({required this.isAvailable});
  @override
  Widget build(BuildContext context) {
    final color =
        isAvailable ? AppColors.activeGreen : AppColors.lightTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isAvailable ? 'Available' : 'Sold out',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Joins menu_items to menus on menu_id and filters by brand. Postgrest's
/// nested-select syntax handles the join in one round-trip.
final menuItemsByBrandProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, brand) async {
    final rows = await Supabase.instance.client
        .from('menu_items')
        .select(
          'id, name, description, price_paise, image_url, category, '
          'is_available, sort_order, menu:menus!inner(brand)',
        )
        .eq('menu.brand', brand)
        .order('sort_order', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  },
);
