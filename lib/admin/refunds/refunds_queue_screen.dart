import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../providers/admin_auth_provider.dart';
import '../providers/admin_streams.dart';
import '../widgets/admin_app_bar.dart';

const _venueId = '00000000-0000-0000-0000-000000000001';

/// Refunds queue. Tabs filter by status. Approve fires refund_approve
/// (now is_admin gated server-side); reject sets status='rejected' with
/// a reason. Realtime stream means the list refreshes the moment a
/// staff-issued ≤₹500 refund or a staff-issued >₹500 pending shows up.
class RefundsQueueScreen extends ConsumerStatefulWidget {
  const RefundsQueueScreen({super.key});

  @override
  ConsumerState<RefundsQueueScreen> createState() =>
      _RefundsQueueScreenState();
}

class _RefundsQueueScreenState extends ConsumerState<RefundsQueueScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(adminAllRefundsProvider).valueOrNull ?? const [];
    final pending = all.where((r) => r['status'] == 'pending').toList();
    final approved = all.where((r) => r['status'] == 'approved').toList();
    final completed = all.where((r) => r['status'] == 'completed').toList();

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: const AdminAppBar(title: 'Refunds'),
      body: Column(
        children: [
          Material(
            color: AppColors.lightSurface,
            child: TabBar(
              controller: _tab,
              tabs: [
                Tab(text: 'Pending (${pending.length})'),
                Tab(text: 'Approved (${approved.length})'),
                Tab(text: 'Completed (${completed.length})'),
                Tab(text: 'All (${all.length})'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _Table(rows: pending, showActions: true),
                _Table(rows: approved, showActions: false),
                _Table(rows: completed, showActions: false),
                _Table(rows: all, showActions: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Table extends ConsumerWidget {
  final List<Map<String, dynamic>> rows;
  final bool showActions;
  const _Table({required this.rows, required this.showActions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'No refunds in this bucket.',
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DataTable(
          columns: [
            const DataColumn(label: Text('Created')),
            const DataColumn(label: Text('Family')),
            const DataColumn(label: Text('Reason')),
            const DataColumn(label: Text('Amount')),
            const DataColumn(label: Text('Initiator')),
            const DataColumn(label: Text('Destination')),
            const DataColumn(label: Text('Status')),
            if (showActions) const DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (final r in rows)
              DataRow(cells: [
                DataCell(Text(_short(r['created_at'] as String?))),
                DataCell(Text(
                  (r['family_id'] as String?)?.substring(0, 8) ?? '—',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                )),
                DataCell(SizedBox(
                  width: 240,
                  child: Text(
                    (r['reason'] as String?) ?? '—',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                )),
                DataCell(Text(
                  Money.fromPaise((r['amount_paise'] as int?) ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                )),
                DataCell(Text((r['initiated_by'] as String?) ?? '—')),
                DataCell(Text((r['destination'] as String?) ?? '—')),
                DataCell(_StatusChip(status: r['status'] as String? ?? '')),
                if (showActions)
                  DataCell(_PendingActions(refund: r)),
              ]),
          ],
        ),
      ),
    );
  }

  String _short(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'pending' => AppColors.warningYellow,
      'approved' => AppColors.activeGreen,
      'completed' => AppColors.activeGreen,
      'rejected' => AppColors.adminRed,
      _ => AppColors.lightTextSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        status,
        style: AppTextStyles.caption(context, color: color),
      ),
    );
  }
}

class _PendingActions extends ConsumerStatefulWidget {
  final Map<String, dynamic> refund;
  const _PendingActions({required this.refund});

  @override
  ConsumerState<_PendingActions> createState() => _PendingActionsState();
}

class _PendingActionsState extends ConsumerState<_PendingActions> {
  bool _busy = false;

  Future<void> _approve() async {
    final adminId = ref.read(adminAuthUserIdProvider);
    if (adminId == null) return;

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc<dynamic>('refund_approve', params: {
        'p_refund_id': widget.refund['id'],
        'p_approver_id': adminId,
        'p_venue_id': _venueId,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Refund approved.')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't approve: ${e.message}")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reject refund?'),
        content: TextField(
          controller: reasonCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Rejection reason',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.adminRed),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true || reasonCtrl.text.trim().isEmpty) return;
    if (!mounted) return;

    final adminId = ref.read(adminAuthUserIdProvider);
    if (adminId == null) return;

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.from('refunds').update({
        'status': 'rejected',
        'approved_by': adminId,
        'approved_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.refund['id'] as String);

      await Supabase.instance.client.from('audit_log').insert({
        'actor_id': adminId,
        'actor_type': 'admin',
        'action': 'refund.reject',
        'entity_type': 'refund',
        'entity_id': widget.refund['id'],
        'venue_id': _venueId,
        'new_value': {'reason': reasonCtrl.text.trim()},
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Refund rejected.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't reject: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: _approve,
          style: TextButton.styleFrom(foregroundColor: AppColors.activeGreen),
          child: const Text('Approve'),
        ),
        TextButton(
          onPressed: _reject,
          style: TextButton.styleFrom(foregroundColor: AppColors.adminRed),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
