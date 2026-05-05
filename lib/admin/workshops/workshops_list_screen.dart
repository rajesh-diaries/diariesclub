import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/currency.dart';
import '../widgets/admin_list_scaffold.dart';

/// View-only stub for /admin/workshops — Module 2.1. Full CRUD lands in
/// Module 2.2 (workshop create/edit/delete + photo upload + push).
class WorkshopsListScreen extends ConsumerWidget {
  const WorkshopsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_workshopsListProvider);
    return AdminListScaffold(
      title: 'Workshops',
      subtitle: 'Read-only — schedule, ages, capacity, registrations',
      placeholderBanner:
          'Create / Edit coming soon — full CRUD ships in Module 2.2.',
      isEmpty: async.maybeWhen(
        data: (rows) => rows.isEmpty,
        orElse: () => false,
      ),
      emptyState: const AdminListEmptyState(
        icon: PhosphorIconsRegular.graduationCap,
        message: 'No workshops yet.',
        subtitle: 'Create the first one once Module 2.2 ships.',
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
              DataColumn(label: Text('When')),
              DataColumn(label: Text('Title')),
              DataColumn(label: Text('Ages')),
              DataColumn(label: Text('Capacity'), numeric: true),
              DataColumn(label: Text('Spots left'), numeric: true),
              DataColumn(label: Text('Price'), numeric: true),
              DataColumn(label: Text('Status')),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(Text(_formatDate(r['scheduled_at'] as String?))),
                  DataCell(Text((r['title'] as String?) ?? '—')),
                  DataCell(Text(_ageRange(r))),
                  DataCell(Text('${r['capacity'] ?? 0}')),
                  DataCell(_spotsCell(context, r)),
                  DataCell(Text(
                    Money.fromPaise((r['price_paise'] as int?) ?? 0),
                  )),
                  DataCell(_StatusBadge(status: r['status'] as String?)),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      return DateFormat('EEE MMM d · h:mm a').format(d);
    } catch (_) {
      return iso;
    }
  }

  String _ageRange(Map<String, dynamic> r) {
    final lo = r['age_group_min'] as int?;
    final hi = r['age_group_max'] as int?;
    if (lo == null && hi == null) return 'Any';
    if (lo != null && hi != null) return '$lo–$hi';
    if (lo != null) return '$lo+';
    return '≤$hi';
  }

  Widget _spotsCell(BuildContext context, Map<String, dynamic> r) {
    final spots = (r['spots_remaining'] as int?) ?? 0;
    final low = spots <= 3;
    return Text(
      '$spots',
      style: TextStyle(
        color: low ? AppColors.adminRed : AppColors.lightTextPrimary,
        fontWeight: low ? FontWeight.w700 : FontWeight.w400,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String? status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'upcoming' => AppColors.activeGreen,
      'completed' => AppColors.lightTextSecondary,
      'cancelled' => AppColors.adminRed,
      _ => AppColors.lightTextSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status ?? '—',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

final _workshopsListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('workshops')
      .select(
        'id, title, scheduled_at, age_group_min, age_group_max, '
        'capacity, spots_remaining, price_paise, status',
      )
      .order('scheduled_at', ascending: true);
  return List<Map<String, dynamic>>.from(rows);
});
