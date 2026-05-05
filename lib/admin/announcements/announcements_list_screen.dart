import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_list_scaffold.dart';

/// Announcements admin list. Workshop-sourced rows are flagged with an
/// "Auto" badge; admin can edit title/body but the CTA stays linked to
/// the workshop. Active count > 5 surfaces a warning since customer home
/// only renders top 5 by type-priority + recency.
class AnnouncementsListScreen extends ConsumerWidget {
  const AnnouncementsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(announcementsAdminListProvider);

    int activeCount = 0;
    async.whenData((rows) {
      final now = DateTime.now();
      activeCount = rows.where((r) {
        if (r['is_published'] != true) return false;
        final from = DateTime.tryParse((r['visible_from'] as String?) ?? '');
        final until = DateTime.tryParse((r['visible_until'] as String?) ?? '');
        if (from == null || from.isAfter(now)) return false;
        if (until != null && until.isBefore(now)) return false;
        return true;
      }).length;
    });

    return AdminListScaffold(
      title: 'Announcements',
      subtitle:
          'Multi-feed home cards for customers. Workshops auto-create rows when '
          'is_published flips and start_at is within 14 days.',
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FilledButton.icon(
            icon: const Icon(PhosphorIconsRegular.plus, size: 16),
            label: const Text('New announcement'),
            onPressed: () => context.go('/admin/announcements/new'),
          ),
        ),
      ],
      isEmpty: async.maybeWhen(
        data: (rows) => rows.isEmpty,
        orElse: () => false,
      ),
      emptyState: const AdminListEmptyState(
        icon: PhosphorIconsRegular.megaphone,
        message: 'No announcements yet.',
        subtitle: 'Workshops within 14 days will auto-create rows here.',
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (activeCount > 5)
              _ActiveOverflowBanner(count: activeCount),
            Expanded(child: _Table(rows: rows, ref: ref)),
          ],
        ),
      ),
    );
  }
}

class _ActiveOverflowBanner extends StatelessWidget {
  final int count;
  const _ActiveOverflowBanner({required this.count});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.10),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.40)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsRegular.warning,
              color: AppColors.gold, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$count active announcements — only the top 5 will show on home '
              '(workshop > promo > event > general > closure).',
              style: AppTextStyles.body(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _Table extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final WidgetRef ref;
  const _Table({required this.rows, required this.ref});

  Future<void> _confirmUnpublish(
    BuildContext context, String id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Unpublish announcement?'),
        content: Text(
          'Hides "$title" from customer home. Re-enable later via Edit.',
        ),
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
        'admin_announcement_delete',
        params: {'p_id': id},
      );
      if (!context.mounted) return;
      ref.invalidate(announcementsAdminListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement unpublished')),
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
    final now = DateTime.now();
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
              DataColumn(label: Text('Title')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Window')),
              DataColumn(label: Text('Source')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(Text((r['title'] as String?) ?? '—')),
                  DataCell(_TypeBadge(type: r['type'] as String?)),
                  DataCell(Text(_window(r))),
                  DataCell(
                    r['source_workshop_id'] != null
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.navy.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Auto · workshop',
                              style: AppTextStyles.caption(
                                context,
                                color: AppColors.navy,
                              ),
                            ),
                          )
                        : Text(
                            'Manual',
                            style: AppTextStyles.caption(
                              context,
                              color: AppColors.lightTextSecondary,
                            ),
                          ),
                  ),
                  DataCell(_StatusBadge(row: r, now: now)),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(PhosphorIconsRegular.pencilSimple,
                            size: 18),
                        onPressed: () =>
                            context.go('/admin/announcements/${r['id']}/edit'),
                      ),
                      if (r['is_published'] as bool? ?? true)
                        IconButton(
                          tooltip: 'Unpublish',
                          icon: const Icon(PhosphorIconsRegular.eyeSlash,
                              size: 18, color: AppColors.adminRed),
                          onPressed: () => _confirmUnpublish(
                            context,
                            r['id'] as String,
                            (r['title'] as String?) ?? 'this announcement',
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

  String _window(Map<String, dynamic> r) {
    final from = DateTime.tryParse((r['visible_from'] as String?) ?? '')?.toLocal();
    final until =
        DateTime.tryParse((r['visible_until'] as String?) ?? '')?.toLocal();
    if (from == null) return '—';
    final fromStr = DateFormat('MMM d').format(from);
    final untilStr = until == null ? '∞' : DateFormat('MMM d').format(until);
    return '$fromStr → $untilStr';
  }
}

class _TypeBadge extends StatelessWidget {
  final String? type;
  const _TypeBadge({required this.type});
  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      'workshop' => AppColors.navy,
      'promo' => AppColors.gold,
      'event' => AppColors.activeGreen,
      'general' => AppColors.lightTextSecondary,
      'closure' => AppColors.adminRed,
      _ => AppColors.lightTextSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        type ?? '—',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Map<String, dynamic> row;
  final DateTime now;
  const _StatusBadge({required this.row, required this.now});
  @override
  Widget build(BuildContext context) {
    if (!(row['is_published'] as bool? ?? true)) {
      return _badge('Unpublished', AppColors.lightTextSecondary);
    }
    final from = DateTime.tryParse((row['visible_from'] as String?) ?? '');
    final until = DateTime.tryParse((row['visible_until'] as String?) ?? '');
    if (from != null && from.isAfter(now)) {
      return _badge('Scheduled', AppColors.gold);
    }
    if (until != null && until.isBefore(now)) {
      return _badge('Expired', AppColors.lightTextSecondary);
    }
    return _badge('Active', AppColors.activeGreen);
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

final announcementsAdminListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('announcements')
      .select(
        'id, title, body, type, cta_label, cta_route, photo_url, '
        'visible_from, visible_until, is_published, source_workshop_id, '
        'created_at',
      )
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows);
});
