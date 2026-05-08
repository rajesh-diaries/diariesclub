import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../providers/admin_streams.dart';
import '../widgets/admin_app_bar.dart';
import '../widgets/admin_buttons.dart';

/// Audit log viewer. Realtime-streamed, capped at 500 rows. Filters
/// applied client-side (so the server still returns the full window —
/// we trade a bit of bandwidth for snappy filter changes).
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  String? _actorFilter;
  String? _actionPrefix;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(adminAuditLogProvider).valueOrNull ?? const [];

    final filtered = all.where((r) {
      if (_actorFilter != null && r['actor_type'] != _actorFilter) return false;
      if (_actionPrefix != null) {
        final action = r['action'] as String? ?? '';
        if (!action.startsWith(_actionPrefix!)) return false;
      }
      final q = _searchCtrl.text.trim();
      if (q.isNotEmpty) {
        final hay =
            '${r['action']} ${r['entity_id']} ${r['actor_id']} ${r['entity_type']}'
                .toLowerCase();
        if (!hay.contains(q.toLowerCase())) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: const AdminAppBar(title: 'Audit Log'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                DropdownButton<String?>(
                  value: _actorFilter,
                  hint: const Text('Actor type'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All actors')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'staff', child: Text('Staff')),
                    DropdownMenuItem(
                        value: 'customer', child: Text('Customer')),
                    DropdownMenuItem(value: 'system', child: Text('System')),
                  ],
                  onChanged: (v) => setState(() => _actorFilter = v),
                ),
                const SizedBox(width: 16),
                DropdownButton<String?>(
                  value: _actionPrefix,
                  hint: const Text('Action category'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All actions')),
                    DropdownMenuItem(value: 'refund.', child: Text('Refunds')),
                    DropdownMenuItem(
                        value: 'birthday.', child: Text('Birthday')),
                    DropdownMenuItem(value: 'session.', child: Text('Session')),
                    DropdownMenuItem(value: 'wallet.', child: Text('Wallet')),
                    DropdownMenuItem(value: 'staff.', child: Text('Staff')),
                    DropdownMenuItem(value: 'admin.', child: Text('Admin')),
                    DropdownMenuItem(value: 'config.', child: Text('Config')),
                    DropdownMenuItem(value: 'pin.', child: Text('PIN')),
                  ],
                  onChanged: (v) => setState(() => _actionPrefix = v),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search action / entity ID',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.lightSurface,
                  border: Border.all(color: AppColors.lightBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Time')),
                    DataColumn(label: Text('Actor')),
                    DataColumn(label: Text('Action')),
                    DataColumn(label: Text('Entity')),
                    DataColumn(label: Text('Detail')),
                  ],
                  rows: [
                    for (final r in filtered)
                      DataRow(
                        onSelectChanged: (_) => _showDetail(context, r),
                        cells: [
                          DataCell(Text(_short(r['created_at'] as String?))),
                          DataCell(_ActorChip(actor: r['actor_type'] as String? ?? '')),
                          DataCell(Text(
                            (r['action'] as String?) ?? '—',
                            style: const TextStyle(fontFamily: 'monospace'),
                          )),
                          DataCell(Text((r['entity_type'] as String?) ?? '—')),
                          DataCell(SizedBox(
                            width: 240,
                            child: Text(
                              _summary(r),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                          )),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _short(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  String _summary(Map<String, dynamic> r) {
    final v = r['new_value'] ?? r['old_value'];
    if (v == null) return (r['entity_id'] as String?) ?? '';
    return v.toString();
  }

  void _showDetail(BuildContext context, Map<String, dynamic> r) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(r['action'] as String? ?? 'Audit entry'),
        content: SingleChildScrollView(
          child: SelectableText(
            r.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          AdminPrimaryButton(
            label: 'Close',
            onPressed: () => Navigator.of(c).pop(),
          ),
        ],
      ),
    );
  }
}

class _ActorChip extends StatelessWidget {
  final String actor;
  const _ActorChip({required this.actor});
  @override
  Widget build(BuildContext context) {
    final color = switch (actor) {
      'admin' => AppColors.navy,
      'staff' => AppColors.gold,
      'customer' => AppColors.activeGreen,
      'system' => AppColors.lightTextSecondary,
      _ => AppColors.lightTextSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        actor,
        style: AppTextStyles.caption(context, color: color),
      ),
    );
  }
}
