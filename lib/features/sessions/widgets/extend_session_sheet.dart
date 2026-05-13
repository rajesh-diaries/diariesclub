// ignore_for_file: deprecated_member_use
// ^ RadioListTile.groupValue/onChanged are slated for deprecation once
// RadioGroup ships in stable. We're on 3.41 where RadioGroup doesn't exist
// yet — revisit when it does.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/current_wallet_provider.dart';
import '../../../core/providers/venue_config_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/primary_button.dart';

/// Bottom sheet to extend an active or grace session. Reads the option
/// list from `venue_config.session_extension_options` (added in 0027 as
/// part of BUG-017 fix) and renders one tile per entry. Each entry has
/// {minutes, price_paise, label}. Server is the source of truth for
/// pricing — client just displays. Calls `session_extend` RPC on confirm.
class ExtendSessionSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  const ExtendSessionSheet({super.key, required this.session});

  @override
  ConsumerState<ExtendSessionSheet> createState() =>
      _ExtendSessionSheetState();
}

/// Hardcoded fallback used when venue_config hasn't loaded yet (or is
/// missing the column for any reason). Mirrors the migration default so
/// pricing stays consistent.
const _fallbackExtensionOptions = <Map<String, dynamic>>[
  {'minutes': 30, 'price_paise': 15000, 'label': '+30 min'},
  {'minutes': 60, 'price_paise': 30000, 'label': '+60 min'},
];

List<Map<String, dynamic>> _resolveOptions(Map<String, dynamic>? cfg) {
  final raw = cfg?['session_extension_options'];
  if (raw is List && raw.isNotEmpty) {
    return raw.whereType<Map<String, dynamic>>().toList();
  }
  return _fallbackExtensionOptions;
}

class _ExtendSessionSheetState extends ConsumerState<ExtendSessionSheet> {
  int _selectedMinutes = 30;
  String _paymentMethod = 'wallet';
  bool _busy = false;
  String? _errorText;

  Future<void> _submit(int amountPaise) async {
    // Hard re-entrancy guard — `canPay` already disables the button
    // visually but a fast double-tap can land between states. Without
    // this guard, two session_extend RPCs fire and the customer is
    // charged twice.
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorText = null;
    });
    final idem = const Uuid().v4();

    try {
      await Supabase.instance.client.rpc<Map<String, dynamic>>(
        'session_extend',
        params: {
          'p_session_id': widget.session['id'],
          'p_duration_minutes': _selectedMinutes,
          'p_payment_method': _paymentMethod,
          'p_initiated_by': 'parent',
          'p_idempotency_key': idem,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.activeGreen,
          content: Text('+$_selectedMinutes minutes added'),
        ),
      );
    } on PostgrestException catch (e) {
      setState(() {
        _busy = false;
        _errorText = _mapError(e.message);
      });
    } catch (_) {
      setState(() {
        _busy = false;
        _errorText = "Couldn't extend. Please try again.";
      });
    }
  }

  String _mapError(String msg) {
    if (msg.contains('insufficient_balance')) {
      return 'Wallet balance is too low. Try cash or top up first.';
    }
    if (msg.contains('session_not_active')) {
      return 'This session is no longer active.';
    }
    return "Couldn't extend. Please try again.";
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(venueConfigProvider).valueOrNull;
    final options = _resolveOptions(cfg);
    final balance = ref.watch(walletBalancePaiseProvider);

    // Default selection follows the first option if the previously-selected
    // duration isn't in the current list (e.g. admin removed it).
    if (!options.any((o) => o['minutes'] == _selectedMinutes) &&
        options.isNotEmpty) {
      _selectedMinutes = options.first['minutes'] as int;
    }
    final selectedOption = options.firstWhere(
      (o) => o['minutes'] == _selectedMinutes,
      orElse: () => options.first,
    );
    final amountPaise = (selectedOption['price_paise'] as int?) ?? 0;
    final canPay = !_busy &&
        (_paymentMethod == 'cash' ||
            (balance != null && balance >= amountPaise));

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Extend session', style: AppTextStyles.h2(context)),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (balance != null)
            Text(
              'Wallet balance: ${Money.fromPaise(balance)}',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          const SizedBox(height: 16),
          Text('Add time', style: AppTextStyles.bodyLarge(context)),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: _DurationTile(
                    label: (options[i]['label'] as String?) ??
                        '+${options[i]['minutes']} min',
                    pricePaise: (options[i]['price_paise'] as int?) ?? 0,
                    selected: _selectedMinutes == options[i]['minutes'],
                    onTap: () => setState(
                      () => _selectedMinutes = options[i]['minutes'] as int,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Text('Pay with', style: AppTextStyles.bodyLarge(context)),
          const SizedBox(height: 4),
          RadioListTile<String>(
            value: 'wallet',
            groupValue: _paymentMethod,
            title: Text(
              'Wallet${balance != null ? ' (${Money.fromPaise(balance)})' : ''}',
            ),
            subtitle: balance != null && balance < amountPaise
                ? const Text('Not enough balance', style: TextStyle(color: AppColors.adminRed))
                : null,
            onChanged: (v) => setState(() => _paymentMethod = v ?? 'wallet'),
          ),
          RadioListTile<String>(
            value: 'cash',
            groupValue: _paymentMethod,
            title: const Text('Cash at desk'),
            onChanged: (v) => setState(() => _paymentMethod = v ?? 'cash'),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: AppTextStyles.caption(context, color: AppColors.adminRed),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label:
                  'Extend · ${Money.fromPaise(amountPaise)} for $_selectedMinutes min',
              onPressed: canPay ? () => _submit(amountPaise) : null,
              loading: _busy,
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationTile extends StatelessWidget {
  final String label;
  final int pricePaise;
  final bool selected;
  final VoidCallback onTap;
  const _DurationTile({
    required this.label,
    required this.pricePaise,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.15)
              : AppColors.lightSurface,
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.lightBorder,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.h3(context)),
            const SizedBox(height: 4),
            Text(
              Money.fromPaise(pricePaise),
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
