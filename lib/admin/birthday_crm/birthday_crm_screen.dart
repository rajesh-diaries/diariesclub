import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../providers/admin_streams.dart';
import '../widgets/admin_app_bar.dart';
import '../widgets/admin_buttons.dart';

/// Birthday CRM kanban — 4 columns (interested / contacted / confirmed /
/// completed). Click a card to open the detail drawer; transition status
/// from the drawer's action bar. Photo upload (the album publish step)
/// deferred per the MVP scope; the drawer's "completed without album"
/// action calls birthday_reservation_complete and the rest waits.
class BirthdayCrmScreen extends ConsumerStatefulWidget {
  const BirthdayCrmScreen({super.key});

  @override
  ConsumerState<BirthdayCrmScreen> createState() => _BirthdayCrmScreenState();
}

class _BirthdayCrmScreenState extends ConsumerState<BirthdayCrmScreen> {
  Map<String, dynamic>? _selected;

  @override
  Widget build(BuildContext context) {
    final reservations =
        ref.watch(adminBirthdayReservationsProvider).valueOrNull ?? const [];

    final byStatus = <String, List<Map<String, dynamic>>>{
      'interested': [],
      'admin_contacted': [],
      'confirmed': [],
      'completed': [],
    };
    for (final r in reservations) {
      final s = r['status'] as String?;
      if (s != null && byStatus.containsKey(s)) {
        byStatus[s]!.add(r);
      }
    }

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: const AdminAppBar(title: 'Birthday CRM'),
      body: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Column(
                    title: 'INTERESTED',
                    color: AppColors.gold,
                    items: byStatus['interested']!,
                    onTap: (r) => setState(() => _selected = r),
                    selectedId: _selected?['id'] as String?,
                  ),
                  _Column(
                    title: 'CONTACTED',
                    color: AppColors.navy,
                    items: byStatus['admin_contacted']!,
                    onTap: (r) => setState(() => _selected = r),
                    selectedId: _selected?['id'] as String?,
                  ),
                  _Column(
                    title: 'CONFIRMED',
                    color: AppColors.activeGreen,
                    items: byStatus['confirmed']!,
                    onTap: (r) => setState(() => _selected = r),
                    selectedId: _selected?['id'] as String?,
                  ),
                  _Column(
                    title: 'COMPLETED',
                    color: AppColors.xpPurple,
                    items: byStatus['completed']!,
                    onTap: (r) => setState(() => _selected = r),
                    selectedId: _selected?['id'] as String?,
                  ),
                ],
              ),
            ),
          ),
          if (_selected != null)
            _DetailDrawer(
              reservation: _selected!,
              onClose: () => setState(() => _selected = null),
              onAction: () {
                // refresh selection from latest stream after RPC call
                final fresh = reservations.firstWhere(
                  (r) => r['id'] == _selected!['id'],
                  orElse: () => const <String, dynamic>{},
                );
                if (fresh.isNotEmpty) {
                  setState(() => _selected = fresh);
                }
              },
            ),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  final String title;
  final Color color;
  final List<Map<String, dynamic>> items;
  final ValueChanged<Map<String, dynamic>> onTap;
  final String? selectedId;
  const _Column({
    required this.title,
    required this.color,
    required this.items,
    required this.onTap,
    required this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Text(
                  title,
                  style: AppTextStyles.caption(context, color: color)
                      .copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  '${items.length}',
                  style: AppTextStyles.caption(context, color: color)
                      .copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final r in items)
            _Card(
              reservation: r,
              isSelected: r['id'] == selectedId,
              onTap: () => onTap(r),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Map<String, dynamic> reservation;
  final bool isSelected;
  final VoidCallback onTap;
  const _Card({
    required this.reservation,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final created = reservation['created_at'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: AppColors.lightSurface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? AppColors.navy : AppColors.lightBorder,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reservation ${(reservation['id'] as String).substring(0, 6).toUpperCase()}',
                  style: AppTextStyles.bodyLarge(context),
                ),
                const SizedBox(height: 4),
                Text(
                  Money.fromPaise(
                      (reservation['package_price_paise'] as int?) ?? 0),
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${reservation['num_kids'] ?? 0} kids · ${reservation['num_adults'] ?? 0} adults',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
                if (reservation['preferred_month'] != null)
                  Text(
                    'Pref: ${reservation['preferred_month']}',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                if (created != null)
                  Text(
                    'Created ${_relative(created)}',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _relative(String iso) {
    try {
      final delta = DateTime.now().difference(DateTime.parse(iso));
      if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
      if (delta.inHours < 24) return '${delta.inHours}h ago';
      return '${delta.inDays}d ago';
    } catch (_) {
      return iso;
    }
  }
}

class _DetailDrawer extends ConsumerStatefulWidget {
  final Map<String, dynamic> reservation;
  final VoidCallback onClose;
  final VoidCallback onAction;
  const _DetailDrawer({
    required this.reservation,
    required this.onClose,
    required this.onAction,
  });

  @override
  ConsumerState<_DetailDrawer> createState() => _DetailDrawerState();
}

class _DetailDrawerState extends ConsumerState<_DetailDrawer> {
  bool _busy = false;

  Future<void> _contact() async {
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_birthday_reservation_contact',
        params: {'p_reservation_id': widget.reservation['id']},
      );
      widget.onAction();
    } on PostgrestException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDate() async {
    final result = await showDialog<({DateTime date, TimeOfDay time, int depositPaise})>(
      context: context,
      builder: (_) => const _ConfirmDateDialog(),
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_birthday_reservation_confirm',
        params: {
          'p_reservation_id': widget.reservation['id'],
          'p_slot_date':
              '${result.date.year}-${result.date.month.toString().padLeft(2, '0')}-${result.date.day.toString().padLeft(2, '0')}',
          'p_slot_start_time':
              '${result.time.hour.toString().padLeft(2, '0')}:${result.time.minute.toString().padLeft(2, '0')}:00',
          'p_slot_end_time':
              '${(result.time.hour + 2).toString().padLeft(2, '0')}:${result.time.minute.toString().padLeft(2, '0')}:00',
          'p_deposit_paid_paise': result.depositPaise,
        },
      );
      widget.onAction();
    } on PostgrestException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markCompleted() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Mark party completed?'),
        content: const Text(
          'This awards 4 birthday-exclusive hero cards + 1000 XP to the child. '
          'Album publish is a separate step (deferred to v1.1).',
        ),
        actions: [
          AdminSecondaryButton(
            label: 'Cancel',
            ghost: true,
            onPressed: () => Navigator.of(c).pop(false),
          ),
          const SizedBox(width: 8),
          AdminPrimaryButton(
            label: 'Mark completed',
            onPressed: () => Navigator.of(c).pop(true),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_birthday_reservation_complete',
        params: {'p_reservation_id': widget.reservation['id']},
      );
      widget.onAction();
    } on PostgrestException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Couldn't proceed: $msg")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reservation;
    final status = r['status'] as String? ?? '';

    return Container(
      width: 440,
      decoration: const BoxDecoration(
        color: AppColors.lightSurface,
        border: Border(left: BorderSide(color: AppColors.lightBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.lightBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Reservation', style: AppTextStyles.h3(context)),
                ),
                AdminIconButton(
                  icon: Icons.close,
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(context, 'Status', status),
                  _row(context, 'Reservation ID',
                      (r['id'] as String).substring(0, 12)),
                  _row(context, 'Package price',
                      Money.fromPaise((r['package_price_paise'] as int?) ?? 0)),
                  _row(context, 'Deposit paid',
                      Money.fromPaise((r['deposit_paid_paise'] as int?) ?? 0)),
                  _row(context, 'Balance',
                      Money.fromPaise((r['balance_paise'] as int?) ?? 0)),
                  _row(context, 'Kids', '${r['num_kids'] ?? 0}'),
                  _row(context, 'Adults', '${r['num_adults'] ?? 0}'),
                  _row(context, 'Preferred month',
                      (r['preferred_month'] as String?) ?? '—'),
                  _row(context, 'Preferred window',
                      (r['preferred_window'] as String?) ?? '—'),
                  if (r['special_requests'] != null)
                    _row(context, 'Special requests',
                        r['special_requests'] as String),
                  if (r['slot_date'] != null)
                    _row(context, 'Slot', '${r['slot_date']} ${r['slot_start_time'] ?? ''}'),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  ..._actionsFor(status),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _actionsFor(String status) {
    if (_busy) {
      return [const Center(child: CircularProgressIndicator())];
    }
    return switch (status) {
      'interested' => [
          AdminPrimaryButton(
            label: 'Mark contacted',
            onPressed: _contact,
          ),
        ],
      'admin_contacted' => [
          AdminPrimaryButton(
            label: 'Confirm date + deposit',
            onPressed: _confirmDate,
          ),
        ],
      'confirmed' => [
          AdminPrimaryButton(
            label: 'Mark completed (auto-award cards)',
            onPressed: _markCompleted,
          ),
        ],
      'completed' => [
          Text(
            'Album publish ships in v1.1. Photos upload + birthday_album_publish RPC chain stays as a follow-up.',
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ],
      _ => [Text('Status "$status" has no admin actions here.')],
    };
  }

  Widget _row(BuildContext c, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: AppTextStyles.caption(
                c,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value, style: AppTextStyles.body(c))),
        ],
      ),
    );
  }
}

class _ConfirmDateDialog extends StatefulWidget {
  const _ConfirmDateDialog();

  @override
  State<_ConfirmDateDialog> createState() => _ConfirmDateDialogState();
}

class _ConfirmDateDialogState extends State<_ConfirmDateDialog> {
  DateTime? _date;
  TimeOfDay _time = const TimeOfDay(hour: 16, minute: 0);
  final _depositCtrl = TextEditingController();

  @override
  void dispose() {
    _depositCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 14)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm party'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(_date == null
                ? 'Pick date'
                : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: _pickDate,
          ),
          ListTile(
            title: Text(_time.format(context)),
            trailing: const Icon(Icons.access_time),
            onTap: _pickTime,
          ),
          TextField(
            controller: _depositCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              prefixText: '₹ ',
              labelText: 'Deposit collected (offline)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        AdminSecondaryButton(
          label: 'Cancel',
          ghost: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        AdminPrimaryButton(
          label: 'Confirm',
          onPressed: _date == null
              ? null
              : () {
                  final rupees = double.tryParse(_depositCtrl.text) ?? 0;
                  Navigator.of(context).pop((
                    date: _date!,
                    time: _time,
                    depositPaise: (rupees * 100).round(),
                  ));
                },
        ),
      ],
    );
  }
}
