import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../widgets/admin_list_scaffold.dart';

/// Coffee Diaries menu CRUD (Module 2.4). Per-row quick actions:
///   - Toggle sold-out (admin_menu_item_toggle_available)
///   - Move ↑ / ↓ (admin_menu_item_reorder — swaps sort_order with
///     neighbour in same category)
///   - Edit (routes to /admin/catalog/coffee/:id/edit)
///   - Hide (admin_menu_item_delete — soft via is_published=false)
///
/// Drag-to-reorder UX deferred — ↑/↓ buttons are functionally equivalent
/// against the swap RPC and avoid the DataTable→ReorderableListView shell
/// switch. Underlying RPC accepts drag-driven sort_order writes when a
/// future polish pass introduces full drag UI.
class CoffeeListScreen extends ConsumerWidget {
  const CoffeeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(coffeeMenuItemsProvider);
    return AdminListScaffold(
      title: 'Coffee Diaries',
      subtitle:
          'Edit, sold-out toggle, reorder. Customer app reflects changes via Realtime.',
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FilledButton.icon(
            icon: const Icon(PhosphorIconsRegular.plus, size: 16),
            label: const Text('New item'),
            onPressed: () async {
              final menuId = await coffeeMenuId();
              if (!context.mounted) return;
              if (menuId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Coffee menu missing — seed first.')),
                );
                return;
              }
              context.go('/admin/catalog/coffee/new?menu_id=$menuId');
            },
          ),
        ),
      ],
      isEmpty: async.maybeWhen(
        data: (rows) => rows.isEmpty,
        orElse: () => false,
      ),
      emptyState: const AdminListEmptyState(
        icon: PhosphorIconsRegular.coffee,
        message: 'No items yet.',
        subtitle: "Tap 'New item' to add the first.",
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) => _Table(rows: rows, ref: ref),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final WidgetRef ref;
  const _Table({required this.rows, required this.ref});

  Future<void> _toggle(BuildContext context, String id, bool to) async {
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_menu_item_toggle_available',
        params: {'p_id': id, 'p_available': to},
      );
      if (!context.mounted) return;
      ref.invalidate(coffeeMenuItemsProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not toggle: $e')),
      );
    }
  }

  Future<void> _reorder(BuildContext context, String id, String dir) async {
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_menu_item_reorder',
        params: {'p_id': id, 'p_direction': dir},
      );
      if (!context.mounted) return;
      ref.invalidate(coffeeMenuItemsProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reorder: $e')),
      );
    }
  }

  Future<void> _hide(BuildContext context, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hide item?'),
        content: Text('Hides "$name" from customers. Edit to re-publish.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.adminRed),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Hide'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_menu_item_delete',
        params: {'p_id': id},
      );
      if (!context.mounted) return;
      ref.invalidate(coffeeMenuItemsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item hidden')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not hide: $e')),
      );
    }
  }

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
              DataColumn(label: Text('Available')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Actions')),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(_thumb(r['image_url'] as String?)),
                  DataCell(Text(
                    (r['name'] as String?) ?? '—',
                    style: TextStyle(
                      decoration: (r['is_published'] as bool? ?? true)
                          ? null
                          : TextDecoration.lineThrough,
                      color: (r['is_published'] as bool? ?? true)
                          ? null
                          : AppColors.lightTextSecondary,
                    ),
                  )),
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
                  DataCell(Switch(
                    value: (r['is_available'] as bool?) ?? true,
                    onChanged: (r['is_published'] as bool? ?? true)
                        ? (v) => _toggle(context, r['id'] as String, v)
                        : null,
                  )),
                  DataCell(_StatusBadge(
                    isPublished: (r['is_published'] as bool?) ?? true,
                    isAvailable: (r['is_available'] as bool?) ?? true,
                  )),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Move up',
                        icon: const Icon(PhosphorIconsRegular.arrowUp,
                            size: 16),
                        onPressed: () =>
                            _reorder(context, r['id'] as String, 'up'),
                      ),
                      IconButton(
                        tooltip: 'Move down',
                        icon: const Icon(PhosphorIconsRegular.arrowDown,
                            size: 16),
                        onPressed: () =>
                            _reorder(context, r['id'] as String, 'down'),
                      ),
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(PhosphorIconsRegular.pencilSimple,
                            size: 16),
                        onPressed: () => context.go(
                          '/admin/catalog/coffee/${r['id']}/edit',
                        ),
                      ),
                      if (r['is_published'] as bool? ?? true)
                        IconButton(
                          tooltip: 'Hide',
                          icon: const Icon(PhosphorIconsRegular.eyeSlash,
                              size: 16, color: AppColors.adminRed),
                          onPressed: () => _hide(
                            context,
                            r['id'] as String,
                            (r['name'] as String?) ?? 'this item',
                          ),
                        ),
                    ],
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

class _StatusBadge extends StatelessWidget {
  final bool isPublished;
  final bool isAvailable;
  const _StatusBadge({required this.isPublished, required this.isAvailable});
  @override
  Widget build(BuildContext context) {
    if (!isPublished) return _badge('Hidden', AppColors.lightTextSecondary);
    if (!isAvailable) return _badge('Sold out', AppColors.adminRed);
    return _badge('Live', AppColors.activeGreen);
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      );
}

/// All coffee items (published + hidden), ordered by category then sort.
final coffeeMenuItemsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('menu_items')
      .select(
        'id, name, description, price_paise, image_url, category, '
        'is_available, is_published, sort_order, menu_id, '
        'menu:menus!inner(brand)',
      )
      .eq('menu.brand', 'coffee')
      .order('category', ascending: true)
      .order('sort_order', ascending: true);
  return List<Map<String, dynamic>>.from(rows);
});

/// Helper: resolve the coffee menu's id (one row per venue).
Future<String?> coffeeMenuId() async {
  final rows = await Supabase.instance.client
      .from('menus')
      .select('id')
      .eq('brand', 'coffee')
      .limit(1);
  if (rows.isEmpty) return null;
  return rows.first['id'] as String?;
}
