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

/// Promo / coupon admin list. Edits go through standard CRUD; redemptions
/// per coupon shown via uses_count badge.
class CouponsListScreen extends ConsumerWidget {
  const CouponsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(couponsAdminListProvider);

    return AdminListScaffold(
      title: 'Coupons',
      subtitle:
          'Promo codes for marketing, partner deals, refund-as-credit. '
          'Independent of family-to-family referrals.',
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: AdminPrimaryButton(
            icon: PhosphorIconsRegular.plus,
            label: 'New coupon',
            onPressed: () => context.go('/admin/coupons/new'),
          ),
        ),
      ],
      isEmpty: async.maybeWhen(
        data: (rows) => rows.isEmpty,
        orElse: () => false,
      ),
      emptyState: const AdminListEmptyState(
        icon: PhosphorIconsRegular.ticket,
        message: 'No coupons yet.',
        subtitle: 'Create one to share with partners or campaigns.',
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

  Future<void> _confirmDeactivate(
    BuildContext context, String id, String code) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => AlertDialog(
        title: const Text('Deactivate coupon?'),
        content: Text(
          'Customers will no longer be able to redeem $code. Existing '
          'redemptions stay on the record. You can reactivate via Edit.',
        ),
        actions: [
          AdminSecondaryButton(
            label: 'Cancel',
            ghost: true,
            onPressed: () => Navigator.of(c).pop(false),
          ),
          const SizedBox(width: 8),
          AdminPrimaryButton.danger(
            label: 'Deactivate',
            onPressed: () => Navigator.of(c).pop(true),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await Supabase.instance.client
          .from('coupons')
          .update({'is_active': false}).eq('id', id);
      if (!context.mounted) return;
      ref.invalidate(couponsAdminListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deactivated $code')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not deactivate: $e')),
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
              DataColumn(label: Text('Code')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Discount')),
              DataColumn(label: Text('Usage')),
              DataColumn(label: Text('Window')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(Text(
                    (r['code'] as String?) ?? '—',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  )),
                  DataCell(_TypeBadge(type: r['type'] as String?)),
                  DataCell(Text(_discountText(r))),
                  DataCell(Text(_usageText(r))),
                  DataCell(Text(_window(r))),
                  DataCell(_StatusBadge(row: r, now: now)),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AdminIconButton(
                        tooltip: 'Edit',
                        icon: PhosphorIconsRegular.pencilSimple,
                        size: 18,
                        onPressed: () =>
                            context.go('/admin/coupons/${r['id']}/edit'),
                      ),
                      if (r['is_active'] as bool? ?? true)
                        AdminIconButton(
                          tooltip: 'Deactivate',
                          icon: PhosphorIconsRegular.prohibit,
                          size: 18,
                          color: AppColors.adminRed,
                          onPressed: () => _confirmDeactivate(
                            context,
                            r['id'] as String,
                            (r['code'] as String?) ?? 'this coupon',
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

  String _discountText(Map<String, dynamic> r) {
    final type = r['type'] as String?;
    final value = r['value'] as int? ?? 0;
    final cap = r['max_discount_paise'] as int?;
    return switch (type) {
      'percent_off' => cap != null
          ? '$value% off (max ${Money.fromPaise(cap)})'
          : '$value% off',
      'flat_off' => '${Money.fromPaise(value)} off',
      'free_session' => 'Free session',
      _ => '—',
    };
  }

  String _usageText(Map<String, dynamic> r) {
    final used = r['uses_count'] as int? ?? 0;
    final max = r['max_uses'] as int?;
    return max == null ? '$used / ∞' : '$used / $max';
  }

  String _window(Map<String, dynamic> r) {
    final from = DateTime.tryParse((r['valid_from'] as String?) ?? '')?.toLocal();
    final until =
        DateTime.tryParse((r['valid_until'] as String?) ?? '')?.toLocal();
    final fromStr = from == null ? '—' : DateFormat('MMM d').format(from);
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
      'percent_off' => AppColors.gold,
      'flat_off' => AppColors.navy,
      'free_session' => AppColors.activeGreen,
      _ => AppColors.lightTextSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        switch (type) {
          'percent_off' => '% off',
          'flat_off' => 'Flat',
          'free_session' => 'Free',
          _ => '—',
        },
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
    if (!(row['is_active'] as bool? ?? true)) {
      return _badge('Inactive', AppColors.lightTextSecondary);
    }
    final from = DateTime.tryParse((row['valid_from'] as String?) ?? '');
    final until = DateTime.tryParse((row['valid_until'] as String?) ?? '');
    if (from != null && from.isAfter(now)) {
      return _badge('Scheduled', AppColors.gold);
    }
    if (until != null && until.isBefore(now)) {
      return _badge('Expired', AppColors.lightTextSecondary);
    }
    final maxUses = row['max_uses'] as int?;
    final used = row['uses_count'] as int? ?? 0;
    if (maxUses != null && used >= maxUses) {
      return _badge('Exhausted', AppColors.lightTextSecondary);
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

final couponsAdminListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('coupons')
      .select(
        'id, code, type, value, max_discount_paise, min_order_paise, '
        'max_uses, uses_count, max_per_family, valid_from, valid_until, '
        'is_active, description, created_at',
      )
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows);
});
