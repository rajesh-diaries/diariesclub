import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/utils/currency.dart';
import '../core/widgets/primary_button.dart';
import 'providers/staff_auth_provider.dart';

/// End-of-shift cash reconciliation. Pulls today's expected cash live from
/// sessions + orders (cash + cash_walkin), takes the staff's counted
/// figure, calls shift_close RPC. Big discrepancies (>₹100) drop an
/// audit_log row that the admin web surfaces.
class ShiftCloseScreen extends ConsumerStatefulWidget {
  final String staffId;
  const ShiftCloseScreen({super.key, required this.staffId});

  @override
  ConsumerState<ShiftCloseScreen> createState() => _ShiftCloseScreenState();
}

class _ShiftCloseScreenState extends ConsumerState<ShiftCloseScreen> {
  final _countedCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _busy = false;
  String? _errorText;

  int _expected = 0;
  int _todaySessions = 0;
  int _todayOrders = 0;
  int _todayRefunds = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    final venueId = ref.read(currentTabletVenueIdProvider);
    if (venueId == null) return;
    final since = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 24))
        .toIso8601String();

    try {
      final sessions = await Supabase.instance.client
          .from('sessions')
          .select('amount_paise, payment_method')
          .eq('venue_id', venueId)
          .gte('created_at', since);
      final orders = await Supabase.instance.client
          .from('orders')
          .select('total_paise, payment_method')
          .eq('venue_id', venueId)
          .gte('created_at', since);
      final refunds = await Supabase.instance.client
          .from('refunds')
          .select('id, amount_paise')
          .gte('created_at', since);

      var expected = 0;
      for (final s in sessions as List) {
        final m = Map<String, dynamic>.from(s as Map);
        if (m['payment_method'] == 'cash' ||
            m['payment_method'] == 'cash_walkin') {
          expected += (m['amount_paise'] as int?) ?? 0;
        }
      }
      for (final o in orders as List) {
        final m = Map<String, dynamic>.from(o as Map);
        if (m['payment_method'] == 'cash' ||
            m['payment_method'] == 'cash_walkin') {
          expected += (m['total_paise'] as int?) ?? 0;
        }
      }

      if (!mounted) return;
      setState(() {
        _expected = expected;
        _todaySessions = (sessions as List).length;
        _todayOrders = (orders as List).length;
        _todayRefunds = (refunds as List).length;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _close() async {
    final raw = _countedCtrl.text.replaceAll(',', '').trim();
    final rupees = double.tryParse(raw);
    if (rupees == null || rupees < 0) {
      setState(() => _errorText = 'Enter a counted amount.');
      return;
    }
    final paise = (rupees * 100).round();

    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc<dynamic>('shift_close', params: {
        'p_counted_cash_paise': paise,
        'p_notes': _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
        'p_staff_pin_id': widget.staffId,
      });
      final r = Map<String, dynamic>.from(res as Map);
      final discrepancy = (r['discrepancy_paise'] as int?) ?? 0;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(discrepancy.abs() > 10000
              ? 'Shift closed with discrepancy ${Money.fromPaise(discrepancy)}. Admin notified.'
              : 'Shift closed.'),
        ),
      );
      context.go('/staff/home');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't close shift: ${e.message}";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't close shift.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final counted =
        (double.tryParse(_countedCtrl.text.replaceAll(',', '')) ?? 0) * 100;
    final discrepancy = counted.toInt() - _expected;

    return Scaffold(
      appBar: AppBar(title: const Text('End shift')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SummaryCard(
                      sessions: _todaySessions,
                      orders: _todayOrders,
                      refunds: _todayRefunds,
                      expected: _expected,
                    ),
                    const SizedBox(height: 16),
                    _CountedCard(
                      controller: _countedCtrl,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    _DiscrepancyRow(discrepancy: discrepancy),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
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
                    PrimaryButton(
                      label: 'Close shift',
                      loading: _busy,
                      onPressed: _busy ? null : _close,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int sessions;
  final int orders;
  final int refunds;
  final int expected;
  const _SummaryCard({
    required this.sessions,
    required this.orders,
    required this.refunds,
    required this.expected,
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
          Text("Today's summary",
              style: AppTextStyles.bodyLarge(context)),
          const SizedBox(height: 8),
          _row(context, 'Sessions', '$sessions'),
          _row(context, 'Orders', '$orders'),
          _row(context, 'Refunds', '$refunds'),
          const Divider(),
          _row(context, 'Expected cash', Money.fromPaise(expected),
              bold: true),
        ],
      ),
    );
  }

  Widget _row(BuildContext c, String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.body(c))),
          Text(
            value,
            style: bold
                ? AppTextStyles.bodyLarge(c)
                : AppTextStyles.body(c),
          ),
        ],
      ),
    );
  }
}

class _CountedCard extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;
  const _CountedCard({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      onChanged: (_) => onChanged(),
      decoration: const InputDecoration(
        prefixText: '₹ ',
        labelText: 'Counted cash',
        border: OutlineInputBorder(),
      ),
    );
  }
}

class _DiscrepancyRow extends StatelessWidget {
  final int discrepancy;
  const _DiscrepancyRow({required this.discrepancy});

  @override
  Widget build(BuildContext context) {
    final isOk = discrepancy == 0;
    final isAcceptable = discrepancy.abs() <= 10000;
    final color = isOk
        ? AppColors.activeGreen
        : isAcceptable
            ? AppColors.warningYellow
            : AppColors.adminRed;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text('Discrepancy', style: AppTextStyles.body(context)),
          const Spacer(),
          Text(
            '${discrepancy >= 0 ? '+' : ''}${Money.fromPaise(discrepancy)}',
            style: AppTextStyles.bodyLarge(context, color: color),
          ),
        ],
      ),
    );
  }
}
