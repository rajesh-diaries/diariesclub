import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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

    final dashboard =
        ref.watch(adminBirthdayDashboardProvider).valueOrNull ??
            const <String, dynamic>{};
    final kpis = (dashboard['kpis'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final attention =
        (dashboard['attention'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final birthdays = ((dashboard['birthdays'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final selectedMonth = ref.watch(adminBirthdayDashboardMonthProvider);

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: const AdminAppBar(title: 'Birthday CRM'),
      body: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AttentionBanner(attention: attention),
                  const SizedBox(height: 16),
                  _KpiRow(kpis: kpis),
                  const SizedBox(height: 24),
                  _BirthdaysThisMonth(
                    selectedMonth: selectedMonth,
                    rows: birthdays,
                    onMonthChanged: (m) => ref
                        .read(adminBirthdayDashboardMonthProvider.notifier)
                        .state = m,
                    onRowTap: (rid) {
                      final match = reservations.firstWhere(
                        (r) => r['id'] == rid,
                        orElse: () => const <String, dynamic>{},
                      );
                      if (match.isNotEmpty) {
                        setState(() => _selected = match);
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'PIPELINE',
                    style: AppTextStyles.caption(
                      context, color: AppColors.lightTextSecondary,
                    ).copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
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
                ],
              ),
            ),
          ),
          if (_selected != null)
            _DetailDrawer(
              reservation: _selected!,
              onClose: () => setState(() => _selected = null),
              onAction: () async {
                // After any RPC action (contact/confirm/cancel/edit/
                // complete), force-refresh both providers so the kanban
                // and the drawer immediately reflect the new state. The
                // adminBirthdayReservationsProvider was switched from
                // a realtime stream to a polling FutureProvider — without
                // this explicit invalidate, the drawer keeps showing the
                // old status and re-tapping the action throws invalid_state.
                ref.invalidate(adminBirthdayReservationsProvider);
                ref.invalidate(adminBirthdayDashboardProvider);
                final fresh =
                    await ref.read(adminBirthdayReservationsProvider.future);
                if (!mounted) return;
                final match = fresh.firstWhere(
                  (r) => r['id'] == _selected!['id'],
                  orElse: () => const <String, dynamic>{},
                );
                setState(() =>
                    _selected = match.isEmpty ? null : match);
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
                  'Inquiry ${(reservation['id'] as String).substring(0, 6).toUpperCase()}',
                  style: AppTextStyles.bodyLarge(context),
                ),
                const SizedBox(height: 4),
                Text(
                  '${reservation['num_kids'] ?? 0} guests',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
                if (reservation['slot_date'] != null)
                  Text(
                    '${reservation['slot_date']} · ${(reservation['slot'] as String? ?? '').toUpperCase()}',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  )
                else if (reservation['preferred_month'] != null)
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
    } on PostgrestException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
      // Always refresh — on success the new state lands; on error
      // (e.g. invalid_state because the DB advanced between drawer
      // open and this click) the drawer picks up the actual current
      // state so the user can act on it instead of hitting the same
      // error again.
      widget.onAction();
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
    } on PostgrestException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
      // Always refresh — on success the new state lands; on error
      // (e.g. invalid_state because the DB advanced between drawer
      // open and this click) the drawer picks up the actual current
      // state so the user can act on it instead of hitting the same
      // error again.
      widget.onAction();
    }
  }

  Future<void> _edit() async {
    final result = await showDialog<_EditInquiryResult>(
      context: context,
      builder: (_) => _EditInquiryDialog(reservation: widget.reservation),
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_birthday_reservation_edit',
        params: {
          'p_reservation_id': widget.reservation['id'],
          if (result.slotDate != null)
            'p_slot_date':
                '${result.slotDate!.year}-${result.slotDate!.month.toString().padLeft(2, '0')}-${result.slotDate!.day.toString().padLeft(2, '0')}',
          if (result.slot != null) 'p_slot': result.slot,
          if (result.guestCount != null) 'p_guest_count': result.guestCount,
          if (result.adminNotes != null) 'p_admin_notes': result.adminNotes,
        },
      );
    } on PostgrestException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
      // Always refresh — on success the new state lands; on error
      // (e.g. invalid_state because the DB advanced between drawer
      // open and this click) the drawer picks up the actual current
      // state so the user can act on it instead of hitting the same
      // error again.
      widget.onAction();
    }
  }

  Future<void> _cancel() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _CancelInquiryDialog(),
    );
    if (reason == null || reason.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_birthday_reservation_cancel',
        params: {
          'p_reservation_id': widget.reservation['id'],
          'p_reason': reason.trim(),
        },
      );
    } on PostgrestException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
      // Always refresh — on success the new state lands; on error
      // (e.g. invalid_state because the DB advanced between drawer
      // open and this click) the drawer picks up the actual current
      // state so the user can act on it instead of hitting the same
      // error again.
      widget.onAction();
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
    } on PostgrestException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
      // Always refresh — on success the new state lands; on error
      // (e.g. invalid_state because the DB advanced between drawer
      // open and this click) the drawer picks up the actual current
      // state so the user can act on it instead of hitting the same
      // error again.
      widget.onAction();
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
                  _ContextHeader(reservationId: r['id'] as String),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  _row(context, 'Status', status),
                  _row(context, 'Inquiry ID',
                      (r['id'] as String).substring(0, 12)),
                  if (r['slot_date'] != null)
                    _row(context, 'Date', '${r['slot_date']}'),
                  if (r['slot'] != null)
                    _row(context, 'Slot',
                        '${(r['slot'] as String)[0].toUpperCase()}${(r['slot'] as String).substring(1)}'),
                  _row(context, 'Guests', '${r['num_kids'] ?? 0}'),
                  if (r['package_price_paise'] != null)
                    _row(context, 'Per-pax (snapshot)',
                        Money.fromPaise((r['package_price_paise'] as int?) ?? 0)),
                  if (r['preferred_month'] != null)
                    _row(context, 'Preferred month (legacy)',
                        r['preferred_month'] as String),
                  if (r['special_requests'] != null)
                    _row(context, 'Special requests',
                        r['special_requests'] as String),
                  if (r['admin_notes'] != null)
                    _row(context, 'Admin notes',
                        r['admin_notes'] as String),
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
    final cancellable = status == 'interested' ||
        status == 'admin_contacted' ||
        status == 'confirmed';
    final editable = status != 'completed' && status != 'cancelled';
    final primary = switch (status) {
      'interested' => AdminPrimaryButton(
          label: 'Mark contacted',
          onPressed: _contact,
        ),
      'admin_contacted' => AdminPrimaryButton(
          label: 'Confirm date + deposit',
          onPressed: _confirmDate,
        ),
      'confirmed' => AdminPrimaryButton(
          label: 'Mark completed (auto-award cards)',
          onPressed: _markCompleted,
        ),
      'completed' => Text(
          'Album publish ships in v1.1. Photos upload + birthday_album_publish RPC chain stays as a follow-up.',
          style: AppTextStyles.body(
            context,
            color: AppColors.lightTextSecondary,
          ),
        ),
      'cancelled' => Text(
          'Cancelled.${(widget.reservation['cancelled_reason'] as String?) != null ? ' Reason: ${widget.reservation['cancelled_reason']}' : ''}',
          style: AppTextStyles.body(
            context,
            color: AppColors.adminRed,
          ),
        ),
      _ => Text('Status "$status" has no admin actions here.'),
    };
    return [
      primary,
      if (editable) ...[
        const SizedBox(height: 12),
        AdminSecondaryButton(
          label: 'Edit inquiry',
          onPressed: _edit,
        ),
      ],
      if (cancellable) ...[
        const SizedBox(height: 8),
        AdminSecondaryButton(
          label: 'Cancel inquiry',
          ghost: true,
          onPressed: _cancel,
        ),
      ],
    ];
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


class _EditInquiryResult {
  final DateTime? slotDate;
  final String? slot;
  final int? guestCount;
  final String? adminNotes;
  const _EditInquiryResult({
    this.slotDate, this.slot, this.guestCount, this.adminNotes,
  });
}

class _EditInquiryDialog extends StatefulWidget {
  final Map<String, dynamic> reservation;
  const _EditInquiryDialog({required this.reservation});

  @override
  State<_EditInquiryDialog> createState() => _EditInquiryDialogState();
}

class _EditInquiryDialogState extends State<_EditInquiryDialog> {
  DateTime? _date;
  String? _slot;
  late final TextEditingController _guests;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final r = widget.reservation;
    final ds = r['slot_date'] as String?;
    if (ds != null) _date = DateTime.tryParse(ds);
    _slot = r['slot'] as String?;
    _guests = TextEditingController(text: '${r['num_kids'] ?? ''}');
    _notes = TextEditingController(text: (r['admin_notes'] as String?) ?? '');
  }

  @override
  void dispose() {
    _guests.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? today.add(const Duration(days: 14)),
      firstDate: today.subtract(const Duration(days: 30)),
      lastDate: today.add(const Duration(days: 365 * 2)),
    );
    if (d != null) setState(() => _date = d);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit inquiry'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_date == null
                  ? 'Pick date'
                  : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Morning'),
                  selected: _slot == 'morning',
                  onSelected: (_) => setState(() => _slot = 'morning'),
                ),
                ChoiceChip(
                  label: const Text('Evening'),
                  selected: _slot == 'evening',
                  onSelected: (_) => setState(() => _slot = 'evening'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _guests,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Guest count',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Admin notes (internal)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        AdminSecondaryButton(
          label: 'Cancel',
          ghost: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        AdminPrimaryButton(
          label: 'Save',
          onPressed: () {
            Navigator.of(context).pop(_EditInquiryResult(
              slotDate: _date,
              slot: _slot,
              guestCount: int.tryParse(_guests.text.trim()),
              adminNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ));
          },
        ),
      ],
    );
  }
}

class _CancelInquiryDialog extends StatefulWidget {
  const _CancelInquiryDialog();

  @override
  State<_CancelInquiryDialog> createState() => _CancelInquiryDialogState();
}

class _CancelInquiryDialogState extends State<_CancelInquiryDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel inquiry?'),
      content: TextField(
        controller: _reason,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Reason (visible in audit log)',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        AdminSecondaryButton(
          label: 'Keep',
          ghost: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        AdminPrimaryButton(
          label: 'Cancel inquiry',
          onPressed: () => Navigator.of(context).pop(_reason.text),
        ),
      ],
    );
  }
}

// ─── Dashboard sections ────────────────────────────────────────────────────

class _AttentionBanner extends StatelessWidget {
  final Map<String, dynamic> attention;
  const _AttentionBanner({required this.attention});

  @override
  Widget build(BuildContext context) {
    final waiting = (attention['new_inquiries_waiting'] as int?) ?? 0;
    final noInquiry = (attention['kids_no_inquiry_upcoming'] as int?) ?? 0;
    final thisWeek = (attention['confirmed_this_week'] as int?) ?? 0;
    if (waiting == 0 && noInquiry == 0 && thisWeek == 0) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.adminRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.adminRed.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsFill.warning,
                  color: AppColors.adminRed, size: 20),
              const SizedBox(width: 8),
              Text(
                'Needs attention',
                style: AppTextStyles.h3(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (waiting > 0)
            _AttentionRow(
              icon: PhosphorIconsRegular.envelope,
              text:
                  '$waiting new ${waiting == 1 ? 'inquiry' : 'inquiries'} waiting > 4 h to be contacted',
            ),
          if (noInquiry > 0)
            _AttentionRow(
              icon: PhosphorIconsRegular.cake,
              text:
                  '$noInquiry ${noInquiry == 1 ? 'kid has' : 'kids have'} birthday in next 14 days — no inquiry yet',
            ),
          if (thisWeek > 0)
            _AttentionRow(
              icon: PhosphorIconsRegular.confetti,
              text:
                  '$thisWeek confirmed ${thisWeek == 1 ? 'party' : 'parties'} this week — review checklist',
            ),
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _AttentionRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.adminRed),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppTextStyles.body(context))),
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  final Map<String, dynamic> kpis;
  const _KpiRow({required this.kpis});

  @override
  Widget build(BuildContext context) {
    final birthdays = (kpis['birthdays_count'] as int?) ?? 0;
    final inquiries = (kpis['inquiries_count'] as int?) ?? 0;
    final confirmed = (kpis['confirmed_count'] as int?) ?? 0;
    final completed = (kpis['completed_count'] as int?) ?? 0;
    final revenuePaise = (kpis['revenue_paise'] as int?) ?? 0;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _KpiTile(
          icon: PhosphorIconsFill.cake,
          label: 'Birthdays this month',
          value: '$birthdays',
          color: AppColors.gold,
        ),
        _KpiTile(
          icon: PhosphorIconsFill.envelope,
          label: 'Inquiries',
          value: '$inquiries',
          color: AppColors.navy,
        ),
        _KpiTile(
          icon: PhosphorIconsFill.checkCircle,
          label: 'Confirmed',
          value: '$confirmed',
          color: AppColors.activeGreen,
        ),
        _KpiTile(
          icon: PhosphorIconsFill.confetti,
          label: 'Completed',
          value: '$completed',
          color: AppColors.xpPurple,
        ),
        _KpiTile(
          icon: PhosphorIconsFill.coins,
          label: 'Revenue (est.)',
          value: Money.fromPaise(revenuePaise),
          color: AppColors.gold,
        ),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _KpiTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.caption(
                    context, color: AppColors.lightTextSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.h2(context, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _BirthdaysThisMonth extends StatefulWidget {
  final int selectedMonth;
  final List<Map<String, dynamic>> rows;
  final ValueChanged<int> onMonthChanged;
  /// Tap on a row with an active inquiry opens the detail drawer. The
  /// callback receives the reservation_id; the parent matches it to a
  /// reservation row and sets _selected.
  final ValueChanged<String> onRowTap;
  const _BirthdaysThisMonth({
    required this.selectedMonth,
    required this.rows,
    required this.onMonthChanged,
    required this.onRowTap,
  });

  @override
  State<_BirthdaysThisMonth> createState() => _BirthdaysThisMonthState();
}

class _BirthdaysThisMonthState extends State<_BirthdaysThisMonth> {
  // 'all' | 'needs_outreach' | 'in_pipeline' | 'completed'
  String _filter = 'all';

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  bool _matches(Map<String, dynamic> r) {
    final status = r['reservation_status'] as String?;
    switch (_filter) {
      case 'needs_outreach':
        return status == null;
      case 'in_pipeline':
        return status == 'interested' ||
            status == 'admin_contacted' ||
            status == 'confirmed';
      case 'completed':
        return status == 'completed';
      default:
        return true;
    }
  }

  Future<void> _whatsApp(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    try {
      await launchUrl(
        Uri.parse('https://wa.me/$clean'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.rows.where(_matches).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'BIRTHDAYS',
              style: AppTextStyles.caption(
                context, color: AppColors.lightTextSecondary,
              ).copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 12),
            DropdownButton<int>(
              value: widget.selectedMonth,
              underline: const SizedBox.shrink(),
              items: [
                for (var m = 1; m <= 12; m++)
                  DropdownMenuItem(value: m, child: Text(_months[m - 1])),
              ],
              onChanged: (v) {
                if (v != null) widget.onMonthChanged(v);
              },
            ),
            const Spacer(),
            Text(
              '${filtered.length} of ${widget.rows.length}',
              style: AppTextStyles.caption(
                context, color: AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final f in const <(String, String)>[
              ('all', 'All'),
              ('needs_outreach', 'Needs outreach'),
              ('in_pipeline', 'In pipeline'),
              ('completed', 'Completed'),
            ])
              FilterChip(
                label: Text(f.$2),
                selected: _filter == f.$1,
                onSelected: (_) => setState(() => _filter = f.$1),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.lightSurface,
            border: Border.all(color: AppColors.lightBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    widget.rows.isEmpty
                        ? 'No birthdays in this month.'
                        : 'No rows match this filter.',
                    style: AppTextStyles.body(
                      context, color: AppColors.lightTextSecondary,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final r in filtered)
                      _BirthdayRow(
                        row: r,
                        onWhatsApp: () =>
                            _whatsApp(r['family_phone'] as String?),
                        onTap: () {
                          final rid = r['reservation_id'] as String?;
                          if (rid != null) widget.onRowTap(rid);
                        },
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _BirthdayRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onWhatsApp;
  final VoidCallback onTap;
  const _BirthdayRow({
    required this.row,
    required this.onWhatsApp,
    required this.onTap,
  });

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final name = (row['child_name'] as String?) ?? '—';
    final family = (row['family_name'] as String?) ?? '—';
    final day = (row['birthday_day'] as num?)?.toInt() ?? 0;
    final month = (row['birthday_month'] as num?)?.toInt() ?? 0;
    final status = row['reservation_status'] as String?;
    final dateLabel = month > 0 && day > 0
        ? '${_months[month - 1]} $day'
        : '—';

    final (Color color, String label) = switch (status) {
      'interested' => (AppColors.gold, '🟡 Interested'),
      'admin_contacted' => (AppColors.navy, '📞 Contacted'),
      'confirmed' => (AppColors.activeGreen, '✅ Confirmed'),
      'completed' => (AppColors.xpPurple, '🎉 Completed'),
      _ => (AppColors.adminRed, '❌ No inquiry'),
    };

    final hasReservation = row['reservation_id'] != null;
    return InkWell(
      onTap: hasReservation ? onTap : null,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.lightBorder, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                dateLabel,
                style: AppTextStyles.body(context).copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.body(context).copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  family,
                  style: AppTextStyles.caption(
                    context, color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppTextStyles.caption(context, color: color).copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onWhatsApp,
              icon: const Icon(PhosphorIconsRegular.whatsappLogo, size: 16),
              label: const Text('Reach out'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top of the detail drawer — shows the family, kid, and wallet
/// context that lives outside the birthday_reservations row itself.
/// Powered by the admin_birthday_reservation_detail RPC which joins
/// families + children + wallets + lifetime-spend in one round trip.
class _ContextHeader extends ConsumerWidget {
  final String reservationId;
  const _ContextHeader({required this.reservationId});

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  String _formatDob(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final d = DateTime.parse(iso);
      return '${d.day} ${_months[d.month - 1]} ${d.year}';
    } catch (_) {
      return iso;
    }
  }

  String _ageFromDob(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dob = DateTime.parse(iso);
      final now = DateTime.now();
      var years = now.year - dob.year;
      if (now.month < dob.month ||
          (now.month == dob.month && now.day < dob.day)) {
        years--;
      }
      return years >= 0 ? '$years yrs' : '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _whatsApp(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final num = phone.replaceAll(RegExp(r'[^\d]'), '');
    await launchUrl(Uri.parse('https://wa.me/$num'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminReservationDetailProvider(reservationId));
    return async.when(
      loading: () => const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (d) {
        final family = (d['family'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final child = (d['child'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final wallet = (d['wallet'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final pkg = (d['package'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final lifetime = (d['lifetime_spend_paise'] as num?)?.toInt() ?? 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (child['name'] as String?) ?? '—',
              style: AppTextStyles.h3(context),
            ),
            const SizedBox(height: 2),
            Text(
              [
                _formatDob(child['date_of_birth'] as String?),
                _ageFromDob(child['date_of_birth'] as String?),
              ].where((s) => s.isNotEmpty).join(' · '),
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 12),
            _kv(context, 'Customer', (family['name'] as String?) ?? '—'),
            Row(
              children: [
                Expanded(
                  child: _kv(
                    context,
                    'Phone',
                    (family['phone'] as String?) ?? '—',
                  ),
                ),
                if ((family['phone'] as String?)?.isNotEmpty ?? false)
                  IconButton(
                    tooltip: 'WhatsApp',
                    icon: const Icon(
                      PhosphorIconsRegular.whatsappLogo,
                      color: AppColors.activeGreen,
                    ),
                    onPressed: () =>
                        _whatsApp(family['phone'] as String?),
                  ),
              ],
            ),
            _kv(
              context,
              'Package',
              (pkg['name'] as String?) ?? '—',
              suffix: (pkg['hall_name'] as String?),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.30),
                ),
              ),
              child: Column(
                children: [
                  _statRow(context, 'Lifetime spend',
                      Money.fromPaise(lifetime)),
                  _statRow(
                    context,
                    'Wallet balance',
                    Money.fromPaise(
                        (wallet['balance_paise'] as num?)?.toInt() ?? 0),
                  ),
                  _statRow(
                    context,
                    'Diaries Coins',
                    '${(wallet['coins_balance'] as num?)?.toInt() ?? 0}'
                    ' · lifetime '
                    '${(wallet['coins_lifetime'] as num?)?.toInt() ?? 0}',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _kv(BuildContext context, String k, String v, {String? suffix}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              k,
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              suffix == null || suffix.isEmpty ? v : '$v · $suffix',
              style: AppTextStyles.body(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
          Text(
            v,
            style: AppTextStyles.body(context).copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
