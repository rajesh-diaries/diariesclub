import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../widgets/admin_buttons.dart';
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
        AdminSecondaryButton(
          icon: PhosphorIconsRegular.tag,
          label: 'Categories',
          onPressed: () => _openCategoriesDialog(context, ref, brand: 'coffee'),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: AdminPrimaryButton(
            icon: PhosphorIconsRegular.plus,
            label: 'New item',
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

class _Table extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final WidgetRef ref;
  const _Table({required this.rows, required this.ref});

  @override
  State<_Table> createState() => _TableState();
}

class _TableState extends State<_Table> {
  final Set<String> _selected = <String>{};

  List<Map<String, dynamic>> get rows => widget.rows;
  WidgetRef get ref => widget.ref;

  void _toggleSelected(String id, bool? on) {
    setState(() {
      if (on == true) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  void _toggleAll(bool? on) {
    setState(() {
      _selected.clear();
      if (on == true) {
        for (final r in rows) {
          final id = r['id'] as String?;
          if (id != null) _selected.add(id);
        }
      }
    });
  }

  Future<void> _bulkSet(BuildContext context, {
    bool? available, bool? published,
  }) async {
    if (_selected.isEmpty) return;
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_menu_items_bulk_set',
        params: {
          'p_ids': _selected.toList(),
          if (available != null) 'p_is_available': available,
          if (published != null) 'p_is_published': published,
        },
      );
      if (!context.mounted) return;
      setState(() => _selected.clear());
      ref.invalidate(coffeeMenuItemsProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bulk update failed: $e')),
      );
    }
  }

  Future<void> _editPrice(BuildContext context, Map<String, dynamic> r) async {
    final currentRupees = ((r['price_paise'] as int?) ?? 0) ~/ 100;
    final ctrl = TextEditingController(text: '$currentRupees');
    final newRupees = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Edit price · ${r['name']}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            prefixText: '₹ ',
            labelText: 'Price',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) =>
              Navigator.of(c).pop(int.tryParse(ctrl.text.trim())),
        ),
        actions: [
          AdminSecondaryButton(
            label: 'Cancel',
            ghost: true,
            onPressed: () => Navigator.pop(c),
          ),
          const SizedBox(width: 8),
          AdminPrimaryButton(
            label: 'Save',
            onPressed: () =>
                Navigator.pop(c, int.tryParse(ctrl.text.trim())),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newRupees == null || newRupees < 0) return;
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_menu_item_set_price',
        params: {
          'p_id': r['id'],
          'p_price_paise': newRupees * 100,
        },
      );
      if (!context.mounted) return;
      ref.invalidate(coffeeMenuItemsProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update price: $e')),
      );
    }
  }

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
          AdminSecondaryButton(
            label: 'Cancel',
            ghost: true,
            onPressed: () => Navigator.pop(c, false),
          ),
          const SizedBox(width: 8),
          AdminPrimaryButton.danger(
            label: 'Hide',
            onPressed: () => Navigator.pop(c, true),
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
    final allSelected = rows.isNotEmpty &&
        _selected.length == rows.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _BulkBar(
              count: _selected.length,
              onClear: () => setState(_selected.clear),
              onPublish: () =>
                  _bulkSet(context, published: true, available: true),
              onHide: () => _bulkSet(context, published: false),
              onMarkSoldOut: () => _bulkSet(context, available: false),
              onMarkAvailable: () => _bulkSet(context, available: true),
            ),
          ),
        Container(
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
                showCheckboxColumn: false,
                columns: [
                  DataColumn(
                    label: Checkbox(
                      value: allSelected,
                      tristate: true,
                      onChanged: _toggleAll,
                    ),
                  ),
                  const DataColumn(label: Text('')),
                  const DataColumn(label: Text('Name')),
                  const DataColumn(label: Text('Category')),
                  const DataColumn(label: Text('Price'), numeric: true),
                  const DataColumn(label: Text('Available')),
                  const DataColumn(label: Text('Status')),
                  const DataColumn(label: Text('Actions')),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(cells: [
                      DataCell(Checkbox(
                        value: _selected.contains(r['id']),
                        onChanged: (v) =>
                            _toggleSelected(r['id'] as String, v),
                      )),
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
                      DataCell(
                        InkWell(
                          onTap: () => _editPrice(context, r),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                Money.fromPaise((r['price_paise'] as int?) ?? 0),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                PhosphorIconsRegular.pencilSimple,
                                size: 12,
                                color: AppColors.lightTextSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
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
                      AdminIconButton(
                        tooltip: 'Move up',
                        icon: PhosphorIconsRegular.arrowUp,
                        size: 16,
                        onPressed: () =>
                            _reorder(context, r['id'] as String, 'up'),
                      ),
                      AdminIconButton(
                        tooltip: 'Move down',
                        icon: PhosphorIconsRegular.arrowDown,
                        size: 16,
                        onPressed: () =>
                            _reorder(context, r['id'] as String, 'down'),
                      ),
                      AdminIconButton(
                        tooltip: 'Edit',
                        icon: PhosphorIconsRegular.pencilSimple,
                        size: 16,
                        onPressed: () => context.go(
                          '/admin/catalog/coffee/${r['id']}/edit',
                        ),
                      ),
                      if (r['is_published'] as bool? ?? true)
                        AdminIconButton(
                          tooltip: 'Hide',
                          icon: PhosphorIconsRegular.eyeSlash,
                          size: 16,
                          color: AppColors.adminRed,
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
        ),
      ],
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

/// Bulk-action bar shown above the table when 1+ rows are checked.
class _BulkBar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final VoidCallback onPublish;
  final VoidCallback onHide;
  final VoidCallback onMarkSoldOut;
  final VoidCallback onMarkAvailable;
  const _BulkBar({
    required this.count,
    required this.onClear,
    required this.onPublish,
    required this.onHide,
    required this.onMarkSoldOut,
    required this.onMarkAvailable,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            '$count selected',
            style: AppTextStyles.body(context).copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(width: 16),
          AdminSecondaryButton(
            icon: PhosphorIconsRegular.eye,
            label: 'Publish',
            onPressed: onPublish,
          ),
          const SizedBox(width: 8),
          AdminSecondaryButton(
            icon: PhosphorIconsRegular.checkCircle,
            label: 'Mark available',
            onPressed: onMarkAvailable,
          ),
          const SizedBox(width: 8),
          AdminSecondaryButton(
            icon: PhosphorIconsRegular.xCircle,
            label: 'Mark sold-out',
            onPressed: onMarkSoldOut,
          ),
          const SizedBox(width: 8),
          AdminSecondaryButton(
            icon: PhosphorIconsRegular.eyeSlash,
            label: 'Hide',
            onPressed: onHide,
          ),
          const Spacer(),
          AdminIconButton(
            tooltip: 'Clear selection',
            icon: PhosphorIconsRegular.x,
            size: 16,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

/// Category management dialog — rename / merge categories for a brand.
/// Pulls the live category set from items, lets admin pick one and
/// type a new name. If the new name matches an existing category, items
/// get merged into it.
Future<void> _openCategoriesDialog(
  BuildContext context,
  WidgetRef ref, {
  required String brand,
}) async {
  final rows = brand == 'coffee'
      ? await ref.read(coffeeMenuItemsProvider.future)
      : <Map<String, dynamic>>[];
  final categories = <String>{};
  for (final r in rows) {
    final c = r['category'] as String?;
    if (c != null && c.isNotEmpty) categories.add(c);
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _CategoriesDialog(
      brand: brand,
      categories: categories.toList()..sort(),
      onChanged: () => ref.invalidate(coffeeMenuItemsProvider),
    ),
  );
}

class _CategoriesDialog extends StatefulWidget {
  final String brand;
  final List<String> categories;
  final VoidCallback onChanged;
  const _CategoriesDialog({
    required this.brand,
    required this.categories,
    required this.onChanged,
  });

  @override
  State<_CategoriesDialog> createState() => _CategoriesDialogState();
}

class _CategoriesDialogState extends State<_CategoriesDialog> {
  String? _editing;
  final _newNameCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _newNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    final from = _editing;
    final to = _newNameCtrl.text.trim();
    if (from == null || to.isEmpty) return;
    if (from == to) {
      setState(() => _editing = null);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_menu_category_rename',
        params: {'p_brand': widget.brand, 'p_from': from, 'p_to': to},
      );
      widget.onChanged();
      if (!mounted) return;
      setState(() {
        _editing = null;
        _newNameCtrl.clear();
        _busy = false;
        // Update local list to reflect change so dialog can stay open.
        widget.categories.remove(from);
        if (!widget.categories.contains(to)) widget.categories.add(to);
        widget.categories.sort();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Rename failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage categories'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Renaming a category updates every item in that category. '
              'If the new name already exists, items merge into it.',
              style: AppTextStyles.caption(
                context, color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.categories.isEmpty)
              Text(
                'No categories yet.',
                style: AppTextStyles.body(
                  context, color: AppColors.lightTextSecondary,
                ),
              )
            else
              for (final c in widget.categories)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _editing == c
                      ? Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _newNameCtrl,
                                autofocus: true,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onSubmitted: (_) => _rename(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            AdminPrimaryButton(
                              label: 'Save',
                              busy: _busy,
                              onPressed: _busy ? null : _rename,
                            ),
                            AdminIconButton(
                              tooltip: 'Cancel',
                              icon: PhosphorIconsRegular.x,
                              size: 16,
                              onPressed: () => setState(() {
                                _editing = null;
                                _newNameCtrl.clear();
                                _error = null;
                              }),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Text(c, style: AppTextStyles.body(context)),
                            ),
                            AdminIconButton(
                              tooltip: 'Rename',
                              icon: PhosphorIconsRegular.pencilSimple,
                              size: 16,
                              onPressed: () => setState(() {
                                _editing = c;
                                _newNameCtrl.text = c;
                              }),
                            ),
                          ],
                        ),
                ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: AppTextStyles.caption(
                  context, color: AppColors.adminRed,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AdminPrimaryButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
