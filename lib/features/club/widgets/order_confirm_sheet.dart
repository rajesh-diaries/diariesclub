import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/current_wallet_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/venues.dart';
import '../../../core/widgets/primary_button.dart';

const _venueId = Venues.kondapurId;

/// Shows a tax-aware order summary before the user commits to `order_place`.
/// Calls the `order_preview` RPC with the same items that will be sent to
/// `order_place`, so the total/GST/rounding shown here matches the invoice.
class OrderConfirmSheet extends ConsumerStatefulWidget {
  final String title;
  final String? subtitle;
  final List<Map<String, dynamic>> items;
  final String? childId;
  final VoidCallback onConfirm;

  const OrderConfirmSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.items,
    this.childId,
    required this.onConfirm,
  });

  @override
  ConsumerState<OrderConfirmSheet> createState() => _OrderConfirmSheetState();
}

class _OrderConfirmSheetState extends ConsumerState<OrderConfirmSheet> {
  bool _loading = true;
  bool _confirming = false;
  String? _errorText;
  Map<String, dynamic>? _preview;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) {
      setState(() {
        _loading = false;
        _errorText = 'Not signed in.';
      });
      return;
    }
    try {
      final result = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('order_preview', params: {
        'p_venue_id': _venueId,
        'p_family_id': familyId,
        'p_items': widget.items,
        'p_child_id': widget.childId,
      });
      if (!mounted) return;
      setState(() {
        _loading = false;
        _preview = result;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = _mapError(e.message);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = 'Could not load preview: $e';
      });
    }
  }

  String _mapError(String raw) {
    if (raw.contains('insufficient_balance')) {
      return 'Wallet balance is short. Top up to continue.';
    }
    if (raw.contains('menu_item_unavailable')) {
      return 'One or more items are no longer available.';
    }
    if (raw.contains('invalid_combo')) {
      return 'This combo is not available right now.';
    }
    if (raw.contains('combo_requires_child')) {
      return 'Please pick a child for the play session.';
    }
    if (raw.contains('child_not_in_family')) {
      return 'Selected child is not linked to your account.';
    }
    if (raw.contains('category_required:')) {
      final slug = raw.split('category_required:').last.trim();
      return 'Please pick an option for: $slug';
    }
    if (raw.contains('option_unavailable:')) {
      return 'One of your selected options is sold out. Try another.';
    }
    return raw;
  }

  Future<void> _confirm() async {
    setState(() => _confirming = true);
    try {
      widget.onConfirm();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(currentWalletProvider).valueOrNull;
    final balancePaise = wallet?['balance_paise'] as int? ?? 0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Confirm order',
                    style: AppTextStyles.h2(context),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(PhosphorIconsRegular.x),
                ),
              ],
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                widget.subtitle!,
                style: AppTextStyles.body(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_errorText != null)
              _buildError()
            else
              _buildSummary(balancePaise),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          PhosphorIconsFill.warningCircle,
          size: 40,
          color: AppColors.adminRed,
        ),
        const SizedBox(height: 12),
        Text(
          _errorText!,
          textAlign: TextAlign.center,
          style: AppTextStyles.body(context),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Try again',
          onPressed: () {
            setState(() {
              _loading = true;
              _errorText = null;
            });
            _loadPreview();
          },
        ),
      ],
    );
  }

  Widget _buildSummary(int balancePaise) {
    final total = (_preview!['total_paise'] as int?) ?? 0;
    final foodTaxable = (_preview!['food_taxable_paise'] as int?) ?? 0;
    final foodGst = (_preview!['food_gst_paise'] as int?) ?? 0;
    final sessionValue = (_preview!['session_value_paise'] as int?) ?? 0;
    final rounding = (_preview!['rounding_paise'] as int?) ?? 0;
    final coins = (_preview!['coins_earned'] as int?) ?? 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Line(label: widget.title, value: null, isBold: true),
        if (foodTaxable > 0) ...[
          const SizedBox(height: 12),
          const _Divider(),
          _Line(label: 'Food (taxable)', value: foodTaxable),
        ],
        if (foodGst > 0)
          _Line(label: 'GST 5% (food)', value: foodGst),
        if (sessionValue > 0)
          _Line(
            label: 'Play session (incl. GST)',
            value: sessionValue,
          ),
        if (rounding != 0)
          _Line(
            label: rounding > 0 ? 'Rounding' : 'Rounding discount',
            value: rounding.abs(),
            showPlus: rounding > 0,
          ),
        const _Divider(),
        _Line(
          label: 'Total',
          value: total,
          isTotal: true,
        ),
        const SizedBox(height: 8),
        if (coins > 0)
          Text(
            '+${Money.fromPaise(coins * 100)} Coins earned',
            style: AppTextStyles.caption(
              context,
              color: AppColors.gold,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        const SizedBox(height: 16),
        Text(
          'Wallet balance: ${Money.fromPaise(balancePaise)}',
          style: AppTextStyles.caption(
            context,
            color: AppColors.lightTextSecondary,
          ),
        ),
        if (balancePaise < total) ...[
          const SizedBox(height: 8),
          Text(
            'Your wallet is short by ${Money.fromPaise(total - balancePaise)}.',
            style: AppTextStyles.caption(
              context,
              color: AppColors.adminRed,
            ),
          ),
        ],
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Place order · ${Money.fromPaise(total)}',
          loading: _confirming,
          onPressed: balancePaise < total ? null : _confirm,
        ),
        const SizedBox(height: 8),
        Text(
          'Tap above to confirm. This will debit your wallet and place the order.',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption(
            context,
            color: AppColors.lightTextSecondary,
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final int? value;
  final bool isBold;
  final bool isTotal;
  final bool showPlus;
  const _Line({
    required this.label,
    this.value,
    this.isBold = false,
    this.isTotal = false,
    this.showPlus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: (isTotal
                      ? AppTextStyles.bodyLarge(context)
                      : AppTextStyles.body(context))
                  .copyWith(
                fontWeight: isBold || isTotal ? FontWeight.w700 : null,
                color: isTotal ? AppColors.navy : null,
              ),
            ),
          ),
          if (value != null)
            Text(
              '${showPlus && value! > 0 ? '+' : ''}${Money.fromPaise(value!)}',
              style: (isTotal
                      ? AppTextStyles.h3(context)
                      : AppTextStyles.body(context))
                  .copyWith(
                fontWeight: isTotal ? FontWeight.w800 : FontWeight.w700,
                color: isTotal ? AppColors.navy : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      height: 1,
      color: AppColors.lightBorder,
    );
  }
}
