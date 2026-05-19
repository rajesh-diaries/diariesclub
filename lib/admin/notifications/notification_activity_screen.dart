import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_app_bar.dart';

/// Admin send-log: recent notifications across all families with
/// filters by type / push_status. Powered by a direct SELECT against
/// the notifications table; admin RLS allows it via the admin_users
/// role check that's already in place.
class NotificationActivityScreen extends ConsumerStatefulWidget {
  const NotificationActivityScreen({super.key});

  @override
  ConsumerState<NotificationActivityScreen> createState() =>
      _NotificationActivityScreenState();
}

class _ActivityFilter {
  final String? type;
  final String? status;
  const _ActivityFilter({this.type, this.status});

  _ActivityFilter copyWith({String? type, String? status, bool clearType = false, bool clearStatus = false}) {
    return _ActivityFilter(
      type: clearType ? null : (type ?? this.type),
      status: clearStatus ? null : (status ?? this.status),
    );
  }
}

final _activityFilterProvider =
    StateProvider<_ActivityFilter>((_) => const _ActivityFilter());

final notificationActivityProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final filter = ref.watch(_activityFilterProvider);
  var query = Supabase.instance.client
      .from('notifications')
      .select(
        'id, type, title, body, created_at, '
        'push_status, push_sent_at, push_failure_reason, '
        'family_id, families(name, phone)',
      );
  if (filter.type != null) {
    query = query.eq('type', filter.type!);
  }
  if (filter.status != null) {
    query = query.eq('push_status', filter.status!);
  }
  final rows = await query.order('created_at', ascending: false).limit(200);
  return (rows as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
});

/// Distinct types present in the table, for the type filter dropdown.
final _distinctTypesProvider = FutureProvider<List<String>>((ref) async {
  final rows = await Supabase.instance.client
      .from('notification_templates')
      .select('type')
      .order('type');
  return (rows as List)
      .map((r) => (r as Map)['type'] as String)
      .toList();
});

class _NotificationActivityScreenState
    extends ConsumerState<NotificationActivityScreen> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationActivityProvider);
    final types = ref.watch(_distinctTypesProvider);
    final filter = ref.watch(_activityFilterProvider);

    return Scaffold(
      appBar: AdminAppBar(
        title: 'Notification Activity',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(notificationActivityProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(filter: filter, types: types),
          const Divider(height: 1),
          Expanded(
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load: $e'),
                ),
              ),
              data: (rows) => _ActivityList(rows: rows),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  final _ActivityFilter filter;
  final AsyncValue<List<String>> types;
  const _FilterBar({required this.filter, required this.types});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: types.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (list) {
                return DropdownButtonFormField<String?>(
                  initialValue: filter.type,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All types'),
                    ),
                    for (final t in list)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) {
                    ref.read(_activityFilterProvider.notifier).update(
                          (f) => f.copyWith(
                            type: v,
                            clearType: v == null,
                          ),
                        );
                    ref.invalidate(notificationActivityProvider);
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: filter.status,
              decoration: const InputDecoration(
                labelText: 'Push status',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('All statuses')),
                DropdownMenuItem(
                    value: 'dispatched', child: Text('dispatched')),
                DropdownMenuItem(value: 'skipped', child: Text('skipped')),
                DropdownMenuItem(value: 'failed', child: Text('failed')),
                DropdownMenuItem(value: 'pending', child: Text('pending')),
              ],
              onChanged: (v) {
                ref.read(_activityFilterProvider.notifier).update(
                      (f) =>
                          f.copyWith(status: v, clearStatus: v == null),
                    );
                ref.invalidate(notificationActivityProvider);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityList extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _ActivityList({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No notifications matching the filter.',
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: rows.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.lightBorder),
      itemBuilder: (_, i) => _ActivityRow(row: rows[i]),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _ActivityRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final type = row['type'] as String? ?? '';
    final title = row['title'] as String? ?? '';
    final body = row['body'] as String? ?? '';
    final created = row['created_at'] as String?;
    final parsed = created == null ? null : DateTime.tryParse(created)?.toLocal();
    final timeStr = parsed == null
        ? '—'
        : DateFormat('MMM d, h:mm a').format(parsed);
    final pushStatus = row['push_status'] as String? ?? 'pending';
    final failure = row['push_failure_reason'] as String?;
    final family = row['families'] as Map?;
    final familyName = family?['name'] as String? ?? '—';
    final familyPhone = family?['phone'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusChip(status: pushStatus),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  type,
                  style: AppTextStyles.caption(context).copyWith(
                    fontFamily: 'monospace',
                    color: AppColors.coffeeBrown,
                  ),
                ),
              ),
              Text(
                timeStr,
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body(context),
          ),
          const SizedBox(height: 2),
          Text(
            body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(PhosphorIconsRegular.user,
                  size: 14, color: AppColors.lightTextSecondary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '$familyName · $familyPhone',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ),
              if (failure != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'reason: $failure',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.adminRed,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'dispatched':
        color = AppColors.activeGreen;
        break;
      case 'skipped':
        color = AppColors.lightTextSecondary;
        break;
      case 'failed':
        color = AppColors.adminRed;
        break;
      default:
        color = AppColors.gold;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
