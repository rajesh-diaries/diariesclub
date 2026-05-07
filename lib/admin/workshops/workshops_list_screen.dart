import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/currency.dart';
import '../widgets/admin_buttons.dart';
import '../widgets/admin_list_scaffold.dart';

/// Workshops list with full CRUD (Module 2.2). + New button creates a
/// new workshop; row actions edit or unpublish. Soft-delete via
/// admin_workshop_delete sets is_published=FALSE; the list shows
/// unpublished rows greyed out so admin can re-publish.
class WorkshopsListScreen extends ConsumerWidget {
  const WorkshopsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(workshopsListProvider);
    return AdminListScaffold(
      title: 'Workshops',
      subtitle:
          'Schedule, ages, capacity, registrations. Publish-toggle fans out push to opted-in families.',
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: AdminPrimaryButton(
            icon: PhosphorIconsRegular.plus,
            label: 'New workshop',
            onPressed: () => context.go('/admin/workshops/new'),
          ),
        ),
      ],
      isEmpty: async.maybeWhen(
        data: (rows) => rows.isEmpty,
        orElse: () => false,
      ),
      emptyState: const AdminListEmptyState(
        icon: PhosphorIconsRegular.graduationCap,
        message: 'No workshops yet.',
        subtitle: "Tap 'New workshop' to create the first one.",
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

  Future<void> _confirmUnpublish(BuildContext context, String id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Unpublish workshop?'),
        content: Text(
          'Hides "$title" from customers. Existing registrations are kept; '
          're-publishing later does not re-fan-out push.',
        ),
        actions: [
          AdminSecondaryButton(
            label: 'Cancel',
            ghost: true,
            onPressed: () => Navigator.pop(c, false),
          ),
          const SizedBox(width: 8),
          AdminPrimaryButton.danger(
            label: 'Unpublish',
            onPressed: () => Navigator.pop(c, true),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_workshop_delete',
        params: {'p_workshop_id': id},
      );
      if (!context.mounted) return;
      ref.invalidate(workshopsListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Workshop unpublished')),
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
              DataColumn(label: Text('When')),
              DataColumn(label: Text('Title')),
              DataColumn(label: Text('Ages')),
              DataColumn(label: Text('Capacity'), numeric: true),
              DataColumn(label: Text('Spots left'), numeric: true),
              DataColumn(label: Text('Price'), numeric: true),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(Text(_formatDate(r['scheduled_at'] as String?))),
                  DataCell(Text(
                    (r['title'] as String?) ?? '—',
                    style: TextStyle(
                      color: (r['is_published'] as bool? ?? true)
                          ? null
                          : AppColors.lightTextSecondary,
                      decoration: (r['is_published'] as bool? ?? true)
                          ? null
                          : TextDecoration.lineThrough,
                    ),
                  )),
                  DataCell(Text(_ageRange(r))),
                  DataCell(Text('${r['capacity'] ?? 0}')),
                  DataCell(_spotsCell(context, r)),
                  DataCell(Text(
                    Money.fromPaise((r['price_paise'] as int?) ?? 0),
                  )),
                  DataCell(_StatusBadge(
                    status: r['status'] as String?,
                    isPublished: (r['is_published'] as bool?) ?? true,
                  )),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AdminIconButton(
                        tooltip: 'Edit',
                        icon: PhosphorIconsRegular.pencilSimple,
                        size: 18,
                        onPressed: () => context.go(
                          '/admin/workshops/${r['id']}/edit',
                        ),
                      ),
                      if (r['is_published'] as bool? ?? true)
                        AdminIconButton(
                          tooltip: 'Unpublish',
                          icon: PhosphorIconsRegular.eyeSlash,
                          size: 18,
                          color: AppColors.adminRed,
                          onPressed: () => _confirmUnpublish(
                            context,
                            r['id'] as String,
                            (r['title'] as String?) ?? 'this workshop',
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
  final bool isPublished;
  const _StatusBadge({required this.status, required this.isPublished});
  @override
  Widget build(BuildContext context) {
    if (!isPublished) {
      return _badge('Unpublished', AppColors.lightTextSecondary);
    }
    return switch (status) {
      'upcoming' => _badge('Upcoming', AppColors.activeGreen),
      'completed' => _badge('Completed', AppColors.lightTextSecondary),
      'cancelled' => _badge('Cancelled', AppColors.adminRed),
      _ => _badge(status ?? '—', AppColors.lightTextSecondary),
    };
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

final workshopsListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  // Admin sees published + unpublished. Customer-side query (in /club) only
  // reads is_published=TRUE.
  final rows = await Supabase.instance.client
      .from('workshops')
      .select(
        'id, title, scheduled_at, age_group_min, age_group_max, '
        'capacity, spots_remaining, price_paise, status, is_published',
      )
      .order('scheduled_at', ascending: true);
  return List<Map<String, dynamic>>.from(rows);
});
