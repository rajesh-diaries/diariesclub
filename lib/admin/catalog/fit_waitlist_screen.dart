import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../widgets/admin_list_scaffold.dart';

/// FIT subscription waitlist admin view (Module 2.5 commit B). Read-only
/// list with status update dropdown per row. CSV export deferred per
/// spec.
class FitWaitlistScreen extends ConsumerWidget {
  const FitWaitlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fitWaitlistAdminProvider);
    return AdminListScaffold(
      title: 'FIT subscription waitlist',
      subtitle:
          'Customers who tapped "Join waitlist" on the customer FIT tab. Update status as you contact / onboard them.',
      isEmpty: async.maybeWhen(
        data: (rows) => rows.isEmpty,
        orElse: () => false,
      ),
      emptyState: const AdminListEmptyState(
        icon: PhosphorIconsRegular.envelope,
        message: 'No signups yet.',
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

  Future<void> _updateStatus(
    BuildContext context, String id, String status) async {
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_fit_waitlist_update_status',
        params: {'p_id': id, 'p_status': status, 'p_notes': null},
      );
      ref.invalidate(fitWaitlistAdminProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: $e')),
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
              DataColumn(label: Text('Family')),
              DataColumn(label: Text('Email')),
              DataColumn(label: Text('Signed up')),
              DataColumn(label: Text('Status')),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(Text((r['family_name'] as String?) ?? '—')),
                  DataCell(Text(
                    (r['email'] as String?) ?? '—',
                    style: const TextStyle(fontFamily: 'monospace'),
                  )),
                  DataCell(Text(_relative(r['created_at'] as String?))),
                  DataCell(DropdownButton<String>(
                    value: (r['status'] as String?) ?? 'interested',
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(
                        value: 'interested', child: Text('Interested'),
                      ),
                      DropdownMenuItem(
                        value: 'contacted', child: Text('Contacted'),
                      ),
                      DropdownMenuItem(
                        value: 'onboarded', child: Text('Onboarded'),
                      ),
                      DropdownMenuItem(
                        value: 'not_interested', child: Text('Not interested'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) _updateStatus(context, r['id'] as String, v);
                    },
                  )),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  String _relative(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso);
      return DateFormat('MMM d, y').format(d.toLocal());
    } catch (_) {
      return iso;
    }
  }
}

/// Joins waitlist to families to get the family name.
final fitWaitlistAdminProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('fit_subscription_waitlist')
      .select('id, email, status, created_at, family:families(name)')
      .order('created_at', ascending: false);
  final out = <Map<String, dynamic>>[];
  for (final r in rows) {
    final m = Map<String, dynamic>.from(r);
    final fam = m['family'];
    if (fam is Map) {
      m['family_name'] = fam['name'];
    }
    out.add(m);
  }
  return out;
});
