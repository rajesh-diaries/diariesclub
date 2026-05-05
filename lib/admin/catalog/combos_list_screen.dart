import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../widgets/admin_list_scaffold.dart';

/// View-only list of session+menu combos. Module 2.4-onward will add CRUD.
class CombosListScreen extends ConsumerWidget {
  const CombosListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_combosListProvider);
    return AdminListScaffold(
      title: 'Combos',
      subtitle: 'Read-only — name, photo, price, sort, status',
      placeholderBanner:
          'Create / Edit coming soon — full CRUD scheduled after Module 2.4.',
      isEmpty: async.maybeWhen(
        data: (rows) => rows.isEmpty,
        orElse: () => false,
      ),
      emptyState: const AdminListEmptyState(
        icon: PhosphorIconsRegular.gift,
        message: 'No combos yet.',
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
              DataColumn(label: Text('Description')),
              DataColumn(label: Text('Price'), numeric: true),
              DataColumn(label: Text('Sort'), numeric: true),
              DataColumn(label: Text('Active')),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(_thumb(r['cover_image_url'] as String?)),
                  DataCell(Text((r['name'] as String?) ?? '—')),
                  DataCell(SizedBox(
                    width: 280,
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
                  DataCell(Text(
                    Money.fromPaise((r['price_paise'] as int?) ?? 0),
                  )),
                  DataCell(Text('${r['sort_order'] ?? 0}')),
                  DataCell(_ActiveBadge(
                    isActive: (r['is_active'] as bool?) ?? true,
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

class _ActiveBadge extends StatelessWidget {
  final bool isActive;
  const _ActiveBadge({required this.isActive});
  @override
  Widget build(BuildContext context) {
    final color =
        isActive ? AppColors.activeGreen : AppColors.lightTextSecondary;
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

final _combosListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('combos')
      .select(
        'id, name, description, cover_image_url, price_paise, '
        'is_active, sort_order',
      )
      .order('sort_order', ascending: true);
  return List<Map<String, dynamic>>.from(rows);
});
