import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../providers/admin_streams.dart';
import '../widgets/admin_app_bar.dart';

const _venueId = '00000000-0000-0000-0000-000000000001';

/// Staff + admin user management. Two tabs: Staff (PIN-based, one row per
/// person at the venue) and Admin Users (web admins). Add staff fires
/// admin_create_staff which returns the generated PIN once — we surface
/// it in a "save this now" dialog. Reset PIN regenerates a 4-digit code
/// + flips force_pin_change=true.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: const AdminAppBar(title: 'Users'),
      body: Column(
        children: [
          Material(
            color: AppColors.lightSurface,
            child: TabBar(
              controller: _tab,
              tabs: const [
                Tab(text: 'Staff (PIN)'),
                Tab(text: 'Admin users (web)'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [_StaffTab(), _AdminTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffTab extends ConsumerWidget {
  const _StaffTab();

  Future<void> _addStaff(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _AddStaffDialog(),
    );
    if (result == null) return;

    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_create_staff',
        params: {
          'p_venue_id': _venueId,
          'p_name': result['name'],
          'p_phone': result['phone'],
          'p_email': result['email'],
          'p_role': result['role'],
          'p_pin': result['pin'],
        },
      );
      if (!context.mounted) return;
      _showPinOnce(context, result['name'] as String, result['pin'] as String);
    } on PostgrestException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't create staff: ${e.message}")),
      );
    }
  }

  Future<void> _resetPin(BuildContext context, Map<String, dynamic> staff) async {
    final pin = _generatePin();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Reset PIN for ${staff['name']}?'),
        content: Text(
          'New PIN will be $pin. The staff member will be required to change '
          'it on next login. Save this PIN somewhere safe before continuing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Reset PIN'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_reset_staff_pin',
        params: {'p_staff_id': staff['id'], 'p_new_pin': pin},
      );
      if (!context.mounted) return;
      _showPinOnce(context, staff['name'] as String, pin);
    } on PostgrestException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't reset PIN: ${e.message}")),
      );
    }
  }

  Future<void> _deactivate(BuildContext context, Map<String, dynamic> staff) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Deactivate ${staff['name']}?'),
        content: const Text(
          'They will not be able to verify PIN on their phone. Reactivation '
          'requires editing the row in Supabase Studio (no UI for it yet).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.adminRed),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_deactivate_staff',
        params: {'p_staff_id': staff['id']},
      );
    } on PostgrestException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't deactivate: ${e.message}")),
      );
    }
  }

  String _generatePin() {
    final rng = Random.secure();
    var pin = '';
    while (pin.length < 4 || pin == '0000') {
      pin = '${rng.nextInt(10)}${rng.nextInt(10)}${rng.nextInt(10)}${rng.nextInt(10)}';
    }
    return pin;
  }

  void _showPinOnce(BuildContext context, String staffName, String pin) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('PIN set for $staffName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Save this PIN now. It will not be shown again.'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                pin,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: pin));
                ScaffoldMessenger.of(c).showSnackBar(
                  const SnackBar(content: Text('PIN copied to clipboard.')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(adminStaffListProvider).valueOrNull ?? const [];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('${staff.length} staff', style: AppTextStyles.body(context)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _addStaff(context),
                icon: const Icon(Icons.add),
                label: const Text('Add staff'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.lightSurface,
                border: Border.all(color: AppColors.lightBorder),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Email')),
                    DataColumn(label: Text('Phone')),
                    DataColumn(label: Text('Role')),
                    DataColumn(label: Text('Active')),
                    DataColumn(label: Text('Force PIN change')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (final s in staff)
                      DataRow(cells: [
                        DataCell(Text((s['name'] as String?) ?? '—')),
                        DataCell(Text((s['email'] as String?) ?? '—')),
                        DataCell(Text(
                          (s['phone'] as String?) ?? '—',
                          style: const TextStyle(fontFamily: 'monospace'),
                        )),
                        DataCell(Text((s['role'] as String?) ?? '—')),
                        DataCell(Icon(
                          s['is_active'] == true
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: s['is_active'] == true
                              ? AppColors.activeGreen
                              : AppColors.adminRed,
                          size: 18,
                        )),
                        DataCell(s['force_pin_change'] == true
                            ? const Text('Yes',
                                style: TextStyle(color: AppColors.adminRed))
                            : const Text('No')),
                        DataCell(Row(
                          children: [
                            TextButton(
                              onPressed: () => _resetPin(context, s),
                              child: const Text('Reset PIN'),
                            ),
                            if (s['is_active'] == true)
                              TextButton(
                                onPressed: () => _deactivate(context, s),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.adminRed,
                                ),
                                child: const Text('Deactivate'),
                              ),
                          ],
                        )),
                      ]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddStaffDialog extends StatefulWidget {
  const _AddStaffDialog();
  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  String _role = 'cashier';
  String _pin = '';

  @override
  void initState() {
    super.initState();
    _pin = _generatePin();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  String _generatePin() {
    final rng = Random.secure();
    var pin = '';
    while (pin.length < 4 || pin == '0000') {
      pin = '${rng.nextInt(10)}${rng.nextInt(10)}${rng.nextInt(10)}${rng.nextInt(10)}';
    }
    return pin;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add staff'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  prefixText: '+91 ',
                  labelText: 'Phone (10 digits)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                  DropdownMenuItem(
                      value: 'kitchen_staff', child: Text('Kitchen staff')),
                  DropdownMenuItem(value: 'manager', child: Text('Manager')),
                  DropdownMenuItem(
                      value: 'super_admin', child: Text('Super admin')),
                ],
                onChanged: (v) => setState(() => _role = v ?? 'cashier'),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.vpn_key, color: AppColors.gold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Initial PIN: $_pin',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => setState(() => _pin = _generatePin()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final phone = _phone.text.trim();
            final fullPhone = phone.startsWith('+') ? phone : '+91$phone';
            Navigator.of(context).pop({
              'name': _name.text.trim(),
              'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
              'phone': fullPhone,
              'role': _role,
              'pin': _pin,
            });
          },
          child: const Text('Create staff'),
        ),
      ],
    );
  }
}

class _AdminTab extends ConsumerWidget {
  const _AdminTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admins = ref.watch(adminUsersListProvider).valueOrNull ?? const [];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Email')),
              DataColumn(label: Text('Role')),
              DataColumn(label: Text('Active')),
              DataColumn(label: Text('Last login')),
            ],
            rows: [
              for (final a in admins)
                DataRow(cells: [
                  DataCell(Text((a['name'] as String?) ?? '—')),
                  DataCell(Text((a['email'] as String?) ?? '—')),
                  DataCell(Text((a['role'] as String?) ?? '—')),
                  DataCell(Icon(
                    a['is_active'] == true ? Icons.check_circle : Icons.cancel,
                    color: a['is_active'] == true
                        ? AppColors.activeGreen
                        : AppColors.adminRed,
                    size: 18,
                  )),
                  DataCell(Text(_short(a['last_login_at'] as String?))),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  String _short(String? iso) {
    if (iso == null) return 'Never';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
