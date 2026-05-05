import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/currency.dart';
import '../widgets/admin_list_scaffold.dart';

const _kondapurVenueId = '00000000-0000-0000-0000-000000000001';

/// FIT templates admin list (Module 2.5 commit B). Replaces the
/// Module 2.1 stub that read menu_items where brand='fit'. The legacy
/// menu_items rows still exist for the customer FIT tab's
/// backward-compat list; the meal builder is its own surface.
class FitListScreen extends ConsumerWidget {
  const FitListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fitTemplatesAdminListProvider);
    return AdminListScaffold(
      title: 'FIT meal builder',
      subtitle:
          'Templates link to global categories. Each option has its own upcharge. Pricing is server-authoritative.',
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextButton.icon(
            icon: const Icon(PhosphorIconsRegular.list, size: 16),
            label: const Text('Categories'),
            onPressed: () => context.go('/admin/catalog/fit/categories'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextButton.icon(
            icon: const Icon(PhosphorIconsRegular.envelope, size: 16),
            label: const Text('Waitlist'),
            onPressed: () => context.go('/admin/catalog/fit/waitlist'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FilledButton.icon(
            icon: const Icon(PhosphorIconsRegular.plus, size: 16),
            label: const Text('New template'),
            onPressed: () => context.go('/admin/catalog/fit/template/new'),
          ),
        ),
      ],
      isEmpty: async.maybeWhen(
        data: (rows) => rows.isEmpty,
        orElse: () => false,
      ),
      emptyState: const AdminListEmptyState(
        icon: PhosphorIconsRegular.barbell,
        message: 'No FIT meal templates yet.',
        subtitle:
            'Create categories first (Categories button), then add a template.',
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

  Future<void> _confirmUnpublish(
    BuildContext context, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Unpublish template?'),
        content: Text('Hides "$name" from customers. Re-publish via Edit.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.adminRed),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Unpublish'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_fit_template_delete',
        params: {'p_id': id},
      );
      if (!context.mounted) return;
      ref.invalidate(fitTemplatesAdminListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Template unpublished')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not unpublish: $e')),
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
              DataColumn(label: Text('Base price'), numeric: true),
              DataColumn(label: Text('Categories'), numeric: true),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Actions')),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(_thumb(r['photo_url'] as String?)),
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
                    Money.fromPaise((r['base_price_paise'] as int?) ?? 0),
                  )),
                  DataCell(Text('${r['category_count'] ?? 0}')),
                  DataCell(_StatusBadge(
                    isPublished: (r['is_published'] as bool?) ?? true,
                    isAvailable: (r['is_available'] as bool?) ?? true,
                  )),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(PhosphorIconsRegular.pencilSimple,
                            size: 16),
                        onPressed: () => context.go(
                          '/admin/catalog/fit/template/${r['id']}/edit',
                        ),
                      ),
                      if (r['is_published'] as bool? ?? true)
                        IconButton(
                          tooltip: 'Unpublish',
                          icon: const Icon(PhosphorIconsRegular.eyeSlash,
                              size: 16, color: AppColors.adminRed),
                          onPressed: () => _confirmUnpublish(
                            context,
                            r['id'] as String,
                            (r['name'] as String?) ?? 'this template',
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

/// Templates with category-count for the list display.
final fitTemplatesAdminListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('fit_meal_templates')
      .select(
        'id, name, description, base_price_paise, photo_url, '
        'is_published, is_available, sort_order, '
        'fit_meal_template_categories(count)',
      )
      .eq('venue_id', _kondapurVenueId)
      .order('sort_order', ascending: true);

  final out = <Map<String, dynamic>>[];
  for (final r in rows) {
    final m = Map<String, dynamic>.from(r);
    final linker = m['fit_meal_template_categories'];
    int count = 0;
    if (linker is List && linker.isNotEmpty) {
      final first = linker.first;
      if (first is Map && first['count'] is int) {
        count = first['count'] as int;
      }
    }
    m['category_count'] = count;
    out.add(m);
  }
  return out;
});
