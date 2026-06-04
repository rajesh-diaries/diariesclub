import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/utils/currency.dart';
import '../core/utils/phone.dart';
import 'providers/staff_auth_provider.dart';
import 'widgets/customer_summary_sheet.dart';

/// Front-desk fallback for when a parent's phone is dead or the QR can't
/// load. Four-step stepper layout (phone → child → duration → confirm),
/// with the customer summary surfaced inline as soon as the family is
/// found so staff see who this is before picking pricing.
///
/// Always runs session_create with p_staff_pin_id set so the audit
/// trail tags this as a staff-initiated session.
class ManualSessionScreen extends ConsumerStatefulWidget {
  final String staffId;
  const ManualSessionScreen({super.key, required this.staffId});

  @override
  ConsumerState<ManualSessionScreen> createState() =>
      _ManualSessionScreenState();
}

class _ManualSessionScreenState extends ConsumerState<ManualSessionScreen> {
  final _phoneCtrl = TextEditingController();

  int _currentStep = 0;
  Map<String, dynamic>? _family;
  List<Map<String, dynamic>> _children = const [];
  Map<String, dynamic>? _wallet;
  Map<String, dynamic>? _summary;

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
      if (!mounted) return;
      setState(() {
        _family = Map<String, dynamic>.from(map['family'] as Map);
        _children = ((map['children'] as List?) ?? const [])
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        _wallet = Map<String, dynamic>.from(
          (map['wallet'] as Map?) ?? const {},
        );
        _selectedChildId =
            _children.length == 1 ? _children.first['id'] as String? : null;
        _busy = false;
        _currentStep = _children.isEmpty ? 2 : 1;
      });
      // Fire-and-forget customer summary so the inline card can show
      // visits + lifetime spend.
      _loadSummary(_family!['id'] as String);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message.contains('family_not_found')
            ? 'No family found with that number.'
            : "Couldn't look up. Try again.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't look up. Try again.";
      });
    }
  }

  Future<void> _loadSummary(String familyId) async {
    try {
      final raw = await Supabase.instance.client.rpc<dynamic>(
        'staff_customer_summary',
        params: {'p_family_id': familyId},
      );
      if (!mounted) return;
      if (raw is Map) {
        setState(() => _summary = Map<String, dynamic>.from(raw));
      }
    } catch (_) {
      // Silent — inline summary stays empty; ⓘ chip still works.
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
      await Supabase.instance.client.rpc<dynamic>('session_create', params: {
        'p_venue_id': venueId,
        'p_family_id': _family!['id'],
        'p_child_id': _selectedChildId,
        'p_duration_minutes': _selectedDuration,
        'p_payment_method': _paymentMethod,
        'p_staff_pin_id': widget.staffId,
        'p_idempotency_key': const Uuid().v4(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session started for ${_childName()}.')),
      );
      // Send the staff back home; customer sees the session live in
      // their own app via Realtime.
      context.go('/staff/home');
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
          child: Stepper(
            currentStep: _currentStep,
            type: StepperType.vertical,
            physics: const NeverScrollableScrollPhysics(),
            onStepTapped: (i) {
              // Allow tapping back to earlier completed steps, never
              // forward past unmet prerequisites.
              if (i <= _currentStep) setState(() => _currentStep = i);
            },
            controlsBuilder: (context, details) => const SizedBox.shrink(),
            steps: [
              Step(
                title: const Text('Find family'),
                isActive: _currentStep >= 0,
                state: _family == null
                    ? StepState.indexed
                    : StepState.complete,
                content: _PhoneLookupContent(
                  controller: _phoneCtrl,
                  busy: _busy && _family == null,
                  onLookup: _lookup,
                  family: _family,
                  wallet: _wallet,
                  summary: _summary,
                  onSeeMore: _family == null
                      ? null
                      : () => CustomerSummarySheet.show<void>(
                            context,
                            familyId: _family!['id'] as String,
                          ),
                ),
              ),
              Step(
                title: const Text('Pick child'),
                isActive: _family != null,
                state: _selectedChildId == null
                    ? (_family == null
                        ? StepState.disabled
                        : StepState.indexed)
                    : StepState.complete,
                content: _ChildPickerContent(
                  children: _children,
                  selectedId: _selectedChildId,
                  onChanged: (id) => setState(() {
                    _selectedChildId = id;
                    _currentStep = 2;
                  }),
                ),
              ),
              Step(
                title: const Text('Pick duration'),
                isActive: _selectedChildId != null || _children.isEmpty,
                state: _selectedDuration == null
                    ? (_family == null
                        ? StepState.disabled
                        : StepState.indexed)
                    : StepState.complete,
                content: _DurationPickerContent(
                  selected: _selectedDuration,
                  onChanged: (d) => setState(() {
                    _selectedDuration = d;
                    _currentStep = 3;
                  }),
                ),
              ),
              Step(
                title: const Text('Payment & start'),
                isActive: _selectedDuration != null,
                state: _selectedDuration == null
                    ? StepState.disabled
                    : StepState.indexed,
                content: _ConfirmContent(
                  walletBalance: (_wallet?['balance_paise'] as int?) ?? 0,
                  paymentMethod: _paymentMethod,
                  onPaymentChanged: (m) =>
                      setState(() => _paymentMethod = m),
                  duration: _selectedDuration,
                  price: _priceFor(_selectedDuration),
                  busy: _busy && _family != null,
                  errorText: _errorText,
                  canStart: _selectedDuration != null &&
                      (_selectedChildId != null || _children.isEmpty),
                  onStart: _start,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneLookupContent extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onLookup;
  final Map<String, dynamic>? family;
  final Map<String, dynamic>? wallet;
  final Map<String, dynamic>? summary;
  final VoidCallback? onSeeMore;
  const _PhoneLookupContent({
    required this.controller,
    required this.busy,
    required this.onLookup,
    required this.family,
    required this.wallet,
    required this.summary,
    required this.onSeeMore,
  });

  @override
  Widget build(BuildContext context) {
    if (family == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          FilledButton.icon(
            onPressed: busy ? null : onLookup,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(PhosphorIconsRegular.magnifyingGlass),
            label: const Text('Look up'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: AppColors.navy,
            ),
          ),
        ],
      );
    }
    // Family found — show identity + inline insights.
    final name = (family!['name'] as String?) ?? 'Customer';
    final phone = (family!['phone'] as String?) ?? '';
    final balance = (wallet?['balance_paise'] as int?) ?? 0;
    final visits = (summary?['visit_count'] as int?) ?? 0;
    final lifetime = (summary?['lifetime_spend_paise'] as int?) ?? 0;
    final lastVisit = summary?['last_visit_at'] as String?;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.activeGreen.withValues(alpha: 0.10),
        border: Border.all(
            color: AppColors.activeGreen.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsFill.checkCircle,
                  color: AppColors.activeGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppTextStyles.bodyLarge(context)),
                    if (phone.isNotEmpty)
                      Text(
                        phone,
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _Stat(
                  icon: PhosphorIconsRegular.calendarCheck,
                  label: visits == 1 ? '1 visit' : '$visits visits'),
              _Stat(
                  icon: PhosphorIconsRegular.coins,
                  label: 'Lifetime ${Money.fromPaise(lifetime)}'),
              _Stat(
                  icon: PhosphorIconsRegular.wallet,
                  label: 'Wallet ${Money.fromPaise(balance)}'),
              if (lastVisit != null)
                _Stat(
                  icon: PhosphorIconsRegular.clock,
                  label: 'Last ${_relative(lastVisit)}',
                ),
            ],
          ),
          if (onSeeMore != null) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: onSeeMore,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.navy.withValues(alpha: 0.20)),
                ),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsRegular.userCircle,
                        size: 16, color: AppColors.navy),
                    const SizedBox(width: 6),
                    Text(
                      'More about this customer',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.navy,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    const Icon(PhosphorIconsRegular.caretRight,
                        size: 14, color: AppColors.navy),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _relative(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inDays == 0) return 'today';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Stat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.lightTextSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTextStyles.caption(
            context,
            color: AppColors.lightTextPrimary,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _ChildPickerContent extends StatelessWidget {
  final List<Map<String, dynamic>> children;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  const _ChildPickerContent({
    required this.children,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return Text(
        'No children registered on this family. You can still start a '
        'session — pick duration next.',
        style: AppTextStyles.body(
          context,
          color: AppColors.lightTextSecondary,
        ),
      );
    }
    return Wrap(
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
    );
  }
}

class _DurationPickerContent extends StatelessWidget {
  final int? selected;
  final ValueChanged<int> onChanged;
  const _DurationPickerContent({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DurationCard(
            label: '1 hour',
            price: '₹800',
            selected: selected == 60,
            onTap: () => onChanged(60),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DurationCard(
            label: '2 hours',
            price: '₹1,100',
            selected: selected == 120,
            onTap: () => onChanged(120),
          ),
        ),
      ],
    );
  }
}

class _DurationCard extends StatelessWidget {
  final String label;
  final String price;
  final bool selected;
  final VoidCallback onTap;
  const _DurationCard({
    required this.label,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.navy.withValues(alpha: 0.10)
              : AppColors.lightSurface,
          border: Border.all(
            color: selected ? AppColors.navy : AppColors.lightBorder,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: AppTextStyles.bodyLarge(context).copyWith(
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.navy : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmContent extends StatelessWidget {
  final int walletBalance;
  final String paymentMethod;
  final ValueChanged<String> onPaymentChanged;
  final int? duration;
  final int price;
  final bool busy;
  final String? errorText;
  final bool canStart;
  final VoidCallback onStart;

  const _ConfirmContent({
    required this.walletBalance,
    required this.paymentMethod,
    required this.onPaymentChanged,
    required this.duration,
    required this.price,
    required this.busy,
    required this.errorText,
    required this.canStart,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Payment',
          style: AppTextStyles.body(context).copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text('Wallet · ${Money.fromPaise(walletBalance)}'),
              selected: paymentMethod == 'wallet',
              onSelected: (_) => onPaymentChanged('wallet'),
            ),
            ChoiceChip(
              label: const Text('Cash'),
              selected: paymentMethod == 'cash',
              onSelected: (_) => onPaymentChanged('cash'),
            ),
            ChoiceChip(
              label: const Text('UPI/Card'),
              selected: paymentMethod == 'razorpay',
              onSelected: (_) => onPaymentChanged('razorpay'),
            ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 12),
          Text(
            errorText!,
            style: AppTextStyles.caption(
              context,
              color: AppColors.adminRed,
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: (canStart && !busy) ? onStart : null,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Icon(PhosphorIconsRegular.playCircle),
          label: Text(
            duration == null
                ? 'Pick a duration'
                : 'Start session · ${Money.fromPaise(price)}',
          ),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            backgroundColor: AppColors.navy,
          ),
        ),
      ],
    );
  }
}
