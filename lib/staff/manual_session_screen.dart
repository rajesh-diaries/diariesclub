import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/utils/currency.dart';
import '../core/utils/phone.dart';
import '../core/widgets/primary_button.dart';
import 'providers/staff_auth_provider.dart';

/// Front-desk fallback for when a parent's phone is dead or the QR can't
/// load. Looks up the family by phone (staff_lookup_family RPC), then
/// runs session_create with p_staff_pin_id set so the audit trail tags
/// this as a staff-initiated session.
class ManualSessionScreen extends ConsumerStatefulWidget {
  final String staffId;
  const ManualSessionScreen({super.key, required this.staffId});

  @override
  ConsumerState<ManualSessionScreen> createState() =>
      _ManualSessionScreenState();
}

class _ManualSessionScreenState extends ConsumerState<ManualSessionScreen> {
  final _phoneCtrl = TextEditingController();
  Map<String, dynamic>? _family;
  List<Map<String, dynamic>> _children = const [];
  Map<String, dynamic>? _wallet;

  String? _selectedChildId;
  int? _selectedDuration;
  String _paymentMethod = 'wallet';
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final raw = _phoneCtrl.text.trim();
    final phone = PhoneNormalizer.toE164(raw);
    if (phone == null) {
      setState(() => _errorText = 'Enter a valid 10-digit number.');
      return;
    }
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final result = await Supabase.instance.client
          .rpc<dynamic>('staff_lookup_family', params: {'p_phone': phone});
      final map = Map<String, dynamic>.from(result as Map);
      setState(() {
        _family = Map<String, dynamic>.from(map['family'] as Map);
        _children = ((map['children'] as List?) ?? const [])
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        _wallet = Map<String, dynamic>.from(
          (map['wallet'] as Map?) ?? const {},
        );
        _selectedChildId =
            _children.isEmpty ? null : _children.first['id'] as String?;
        _busy = false;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _busy = false;
        _errorText = e.message.contains('family_not_found')
            ? 'No family found with that number.'
            : "Couldn't look up. Try again.";
      });
    } catch (_) {
      setState(() {
        _busy = false;
        _errorText = "Couldn't look up. Try again.";
      });
    }
  }

  int _priceFor(int? duration) {
    if (duration == 60) return 80000;
    if (duration == 120) return 110000;
    return 0;
  }

  Future<void> _start() async {
    if (_family == null ||
        _selectedChildId == null ||
        _selectedDuration == null) {
      return;
    }
    final venueId = ref.read(currentTabletVenueIdProvider);
    if (venueId == null) return;

    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc<dynamic>('session_create', params: {
        'p_venue_id': venueId,
        'p_family_id': _family!['id'],
        'p_child_id': _selectedChildId,
        'p_duration_minutes': _selectedDuration,
        'p_payment_method': _paymentMethod,
        'p_staff_pin_id': widget.staffId,
        'p_idempotency_key': const Uuid().v4(),
      });
      final map = Map<String, dynamic>.from(res as Map);
      final sid = map['session_id'] as String?;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session started for ${_childName()}.')),
      );
      // Send the staff back home; customer will see the session live in
      // their own app via Realtime.
      context.go('/staff/home');
      // ignore: unused_local_variable
      sid;
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message.contains('insufficient_balance')
            ? 'Wallet has insufficient balance. Switch to cash or top up.'
            : "Couldn't start session.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't start session.";
      });
    }
  }

  String _childName() {
    final c = _children.firstWhere(
      (x) => x['id'] == _selectedChildId,
      orElse: () => const <String, dynamic>{},
    );
    return (c['name'] as String?) ?? 'the child';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manual session')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PhoneLookupCard(
                controller: _phoneCtrl,
                busy: _busy && _family == null,
                onLookup: _lookup,
              ),
              if (_family != null) ...[
                const SizedBox(height: 16),
                _FamilyCard(family: _family!, wallet: _wallet),
                const SizedBox(height: 16),
                _ChildPicker(
                  children: _children,
                  selectedId: _selectedChildId,
                  onChanged: (id) => setState(() => _selectedChildId = id),
                ),
                const SizedBox(height: 16),
                _DurationPicker(
                  selected: _selectedDuration,
                  onChanged: (d) => setState(() => _selectedDuration = d),
                ),
                const SizedBox(height: 16),
                _PaymentPicker(
                  walletBalance: (_wallet?['balance_paise'] as int?) ?? 0,
                  selected: _paymentMethod,
                  onChanged: (m) => setState(() => _paymentMethod = m),
                ),
              ],
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.adminRed,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_family != null)
                PrimaryButton(
                  label: _selectedDuration == null
                      ? 'Pick a duration'
                      : 'Start session ${Money.fromPaise(_priceFor(_selectedDuration))}',
                  loading: _busy && _family != null,
                  onPressed: (_selectedDuration == null ||
                          _selectedChildId == null ||
                          _busy)
                      ? null
                      : _start,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneLookupCard extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onLookup;
  const _PhoneLookupCard({
    required this.controller,
    required this.busy,
    required this.onLookup,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Step 1 — Find family',
              style: AppTextStyles.bodyLarge(context)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            enabled: !busy,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onLookup(),
            decoration: const InputDecoration(
              prefixText: '+91 ',
              hintText: '98765 43210',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Look up',
            loading: busy,
            onPressed: busy ? null : onLookup,
          ),
        ],
      ),
    );
  }
}

class _FamilyCard extends StatelessWidget {
  final Map<String, dynamic> family;
  final Map<String, dynamic>? wallet;
  const _FamilyCard({required this.family, required this.wallet});

  @override
  Widget build(BuildContext context) {
    final name = (family['name'] as String?) ?? '—';
    final balance = (wallet?['balance_paise'] as int?) ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.activeGreen.withValues(alpha: 0.10),
        border: Border.all(
            color: AppColors.activeGreen.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.family_restroom, color: AppColors.activeGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.bodyLarge(context)),
                Text(
                  'Wallet: ${Money.fromPaise(balance)}',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChildPicker extends StatelessWidget {
  final List<Map<String, dynamic>> children;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  const _ChildPicker({
    required this.children,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step 2 — Pick child',
              style: AppTextStyles.bodyLarge(context)),
          const SizedBox(height: 8),
          if (children.isEmpty)
            Text(
              'No children on this family.',
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in children)
                  ChoiceChip(
                    label: Text((c['name'] as String?) ?? '—'),
                    selected: selectedId == c['id'],
                    onSelected: (_) => onChanged(c['id'] as String?),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DurationPicker extends StatelessWidget {
  final int? selected;
  final ValueChanged<int> onChanged;
  const _DurationPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step 3 — Duration',
              style: AppTextStyles.bodyLarge(context)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('1 hour · ₹800'),
                  selected: selected == 60,
                  onSelected: (_) => onChanged(60),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('2 hours · ₹1,100'),
                  selected: selected == 120,
                  onSelected: (_) => onChanged(120),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentPicker extends StatelessWidget {
  final int walletBalance;
  final String selected;
  final ValueChanged<String> onChanged;
  const _PaymentPicker({
    required this.walletBalance,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step 4 — Payment',
              style: AppTextStyles.bodyLarge(context)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text('Wallet · ${Money.fromPaise(walletBalance)}'),
                selected: selected == 'wallet',
                onSelected: (_) => onChanged('wallet'),
              ),
              ChoiceChip(
                label: const Text('Cash'),
                selected: selected == 'cash',
                onSelected: (_) => onChanged('cash'),
              ),
              ChoiceChip(
                label: const Text('UPI/Card'),
                selected: selected == 'razorpay',
                onSelected: (_) => onChanged('razorpay'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
