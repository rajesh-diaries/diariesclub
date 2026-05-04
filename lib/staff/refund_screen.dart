// ignore_for_file: deprecated_member_use
// ^ RadioListTile.groupValue/onChanged — matches session_start_screen.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/utils/currency.dart';
import '../core/utils/phone.dart';
import '../core/widgets/primary_button.dart';

/// Find a recent transaction by family phone, then issue a refund. Wrapper
/// RPC `refund_issue_by_staff` enforces the ₹500 staff cap (above-cap →
/// 'refund_exceeds_staff_cap'); the UI surfaces that as a "needs admin"
/// hint.
class RefundScreen extends ConsumerStatefulWidget {
  final String staffId;
  const RefundScreen({super.key, required this.staffId});

  @override
  ConsumerState<RefundScreen> createState() => _RefundScreenState();
}

class _RefundScreenState extends ConsumerState<RefundScreen> {
  final _phoneCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  String? _familyId;
  List<_TxnRow> _txns = const [];
  _TxnRow? _selected;
  String _destination = 'wallet';
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final phone = PhoneNormalizer.toE164(_phoneCtrl.text);
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
      final family =
          Map<String, dynamic>.from((result as Map)['family'] as Map);
      _familyId = family['id'] as String?;

      // Pull recent orders + sessions for this family.
      final since = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 30))
          .toIso8601String();
      final orders = await Supabase.instance.client
          .from('orders')
          .select()
          .eq('family_id', _familyId!)
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(20);
      final sessions = await Supabase.instance.client
          .from('sessions')
          .select()
          .eq('family_id', _familyId!)
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(20);

      final txns = <_TxnRow>[];
      for (final o in orders as List) {
        final m = Map<String, dynamic>.from(o as Map);
        txns.add(_TxnRow(
          id: m['id'] as String,
          type: 'order',
          amountPaise: (m['total_paise'] as int?) ?? 0,
          createdAt: DateTime.tryParse(m['created_at'] as String? ?? ''),
          label: 'Order #${(m['id'] as String).substring(0, 4).toUpperCase()}',
        ));
      }
      for (final s in sessions as List) {
        final m = Map<String, dynamic>.from(s as Map);
        txns.add(_TxnRow(
          id: m['id'] as String,
          type: 'session',
          amountPaise: (m['amount_paise'] as int?) ?? 0,
          createdAt: DateTime.tryParse(m['created_at'] as String? ?? ''),
          label: 'Session ${m['duration_minutes']}m',
        ));
      }
      txns.sort((a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

      setState(() {
        _txns = txns;
        _busy = false;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _busy = false;
        _errorText = e.message.contains('family_not_found')
            ? 'No family found.'
            : "Couldn't look up.";
      });
    } catch (_) {
      setState(() {
        _busy = false;
        _errorText = "Couldn't look up.";
      });
    }
  }

  Future<void> _issue() async {
    if (_selected == null) return;
    final reason = _reasonCtrl.text.trim();
    final amountRupees = double.tryParse(_amountCtrl.text);
    if (amountRupees == null || amountRupees <= 0) {
      setState(() => _errorText = 'Enter a refund amount.');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _errorText = 'Reason is required.');
      return;
    }
    final amountPaise = (amountRupees * 100).round();

    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      final res = await Supabase.instance.client
          .rpc<dynamic>('refund_issue_by_staff', params: {
        'p_reference_id': _selected!.id,
        'p_reference_type': _selected!.type,
        'p_amount_paise': amountPaise,
        'p_destination': _destination,
        'p_reason': reason,
        'p_staff_pin_id': widget.staffId,
        'p_idempotency_key': const Uuid().v4(),
      });
      if (!mounted) return;
      final r = Map<String, dynamic>.from(res as Map);
      final status = r['status'] as String?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'completed'
                ? 'Refund of ${Money.fromPaise(amountPaise)} issued.'
                : 'Refund recorded ($status). Customer will see when admin approves.',
          ),
        ),
      );
      context.pop();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message.contains('refund_exceeds_staff_cap')
            ? 'Above ₹500 — admin approval required. Send to admin web.'
            : e.message.contains('reference_other_venue')
                ? 'That transaction is from another venue.'
                : "Couldn't issue refund.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't issue refund.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final overCap =
        (double.tryParse(_amountCtrl.text) ?? 0) * 100 > 50000;

    return Scaffold(
      appBar: AppBar(title: const Text('Issue refund')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Phone lookup
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.lightSurface,
                  border: Border.all(color: AppColors.lightBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Find original transaction',
                        style: AppTextStyles.bodyLarge(context)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        prefixText: '+91 ',
                        hintText: '98765 43210',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'Look up',
                      loading: _busy && _txns.isEmpty,
                      onPressed: _busy ? null : _lookup,
                    ),
                  ],
                ),
              ),
              if (_txns.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.lightSurface,
                    border: Border.all(color: AppColors.lightBorder),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recent transactions',
                          style: AppTextStyles.bodyLarge(context)),
                      const SizedBox(height: 8),
                      for (final t in _txns)
                        RadioListTile<_TxnRow>(
                          value: t,
                          groupValue: _selected,
                          onChanged: (v) {
                            setState(() {
                              _selected = v;
                              _amountCtrl.text =
                                  (t.amountPaise / 100).toStringAsFixed(0);
                            });
                          },
                          title: Text(
                            '${t.label} — ${Money.fromPaise(t.amountPaise)}',
                          ),
                          subtitle: Text(_formatDate(t.createdAt)),
                        ),
                    ],
                  ),
                ),
              ],
              if (_selected != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.lightSurface,
                    border: Border.all(color: AppColors.lightBorder),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Refund details',
                          style: AppTextStyles.bodyLarge(context)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]')),
                        ],
                        decoration: const InputDecoration(
                          prefixText: '₹ ',
                          labelText: 'Amount',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _reasonCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Reason',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Wallet'),
                            selected: _destination == 'wallet',
                            onSelected: (_) =>
                                setState(() => _destination = 'wallet'),
                          ),
                          ChoiceChip(
                            label: const Text('Razorpay'),
                            selected: _destination == 'razorpay',
                            onSelected: (_) =>
                                setState(() => _destination = 'razorpay'),
                          ),
                        ],
                      ),
                      if (overCap) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.warningYellow
                                .withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Above ₹500. The RPC will reject this — admin web (Session 11) must issue larger refunds.',
                            style: AppTextStyles.caption(
                              context,
                              color: AppColors.lightTextPrimary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
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
              if (_selected != null)
                PrimaryButton(
                  label: 'Issue refund',
                  loading: _busy,
                  onPressed: _busy ? null : _issue,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    final local = d.toLocal();
    return '${local.day}/${local.month}/${local.year} ${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _TxnRow {
  final String id;
  final String type; // 'order' | 'session'
  final int amountPaise;
  final DateTime? createdAt;
  final String label;
  const _TxnRow({
    required this.id,
    required this.type,
    required this.amountPaise,
    required this.createdAt,
    required this.label,
  });
}
