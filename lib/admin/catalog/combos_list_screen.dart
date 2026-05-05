import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../widgets/admin_list_scaffold.dart';

/// Combos CRUD list (Module 2.6). Replaces the Module 2.1 view-only stub.
class CombosListScreen extends ConsumerWidget {
  const CombosListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(combosAdminListProvider);
    return AdminListScaffold(
      title: 'Combos',
      subtitle:
          'Bundle deals across Coffee + FIT. Each combo references items by id; pricing is set per combo (not auto-summed).',
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FilledButton.icon(
            icon: const Icon(PhosphorIconsRegular.plus, size: 16),
            label: const Text('New combo'),
            onPressed: () => context.go('/admin/catalog/combos/new'),
          ),
        ),
      ],
      isEmpty: async.maybeWhen(
        data: (rows) => rows.isEmpty,
        orElse: () => false,
      ),
      emptyState: const AdminListEmptyState(
        icon: PhosphorIconsRegular.gift,
        message: 'No combos yet.',
        subtitle: "Tap 'New combo' to create your first bundle.",
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

  Future<void> _confirmHide(BuildContext context, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Deactivate combo?'),
        content: Text('Hides "$name" from customers. Re-activate via Edit.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.adminRed),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_combo_delete',
        params: {'p_id': id},
      );
      if (!context.mounted) return;
      ref.invalidate(combosAdminListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Combo deactivated')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not deactivate: $e')),
      );
    }
  }

  int _itemCount(Map<String, dynamic> r) {
    final inc = r['inclusions'];
    if (inc is! Map) return 0;
    final items = inc['menu_items'];
    if (items is List) return items.length;
    final legacy = inc['menu_item_ids'];
    if (legacy is List) return legacy.length;
    return 0;
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
              DataColumn(label: Text('Description')),
              DataColumn(label: Text('Items'), numeric: true),
              DataColumn(label: Text('Price'), numeric: true),
              DataColumn(label: Text('Sort'), numeric: true),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(_thumb(r['cover_image_url'] as String?)),
                  DataCell(Text(
                    (r['name'] as String?) ?? '—',
                    style: TextStyle(
                      decoration: (r['is_active'] as bool? ?? true)
                          ? null
                          : TextDecoration.lineThrough,
                      color: (r['is_active'] as bool? ?? true)
                          ? null
                          : AppColors.lightTextSecondary,
                    ),
                  )),
                  DataCell(SizedBox(
                    width: 240,
                    child: Text(
                      (r['description'] as String?) ?? '—',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  )),
                  DataCell(Text('${_itemCount(r)}')),
                  DataCell(Text(
                    Money.fromPaise((r['price_paise'] as int?) ?? 0),
                  )),
                  DataCell(Text('${r['sort_order'] ?? 0}')),
                  DataCell(_StatusBadge(
                    isActive: (r['is_active'] as bool?) ?? true,
                  )),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(PhosphorIconsRegular.pencilSimple,
                            size: 16),
                        onPressed: () => context.go(
                          '/admin/catalog/combos/${r['id']}/edit',
                        ),
                      ),
                      if (r['is_active'] as bool? ?? true)
                        IconButton(
                          tooltip: 'Deactivate',
                          icon: const Icon(PhosphorIconsRegular.eyeSlash,
                              size: 16, color: AppColors.adminRed),
                          onPressed: () => _confirmHide(
                            context,
                            r['id'] as String,
                            (r['name'] as String?) ?? 'this combo',
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
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: AppColors.lightBackground,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(PhosphorIconsRegular.image,
            size: 16, color: AppColors.lightTextSecondary),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(url, width: 32, height: 32, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 32, height: 32, color: AppColors.lightBackground,
          )),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  const _StatusBadge({required this.isActive});
  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.activeGreen : AppColors.lightTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isActive ? 'Active' : 'Hidden',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

final combosAdminListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('combos')
      .select(
        'id, name, description, cover_image_url, price_paise, '
        'inclusions, is_active, sort_order',
      )
      .order('sort_order', ascending: true);
  return List<Map<String, dynamic>>.from(rows);
});
