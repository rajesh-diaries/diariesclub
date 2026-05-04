import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/primary_button.dart';
import '../../home/widgets/top_up_sheet.dart';

/// Shown when `session_create` rejects with `insufficient_balance`. Two
/// branches: top up the wallet (closes this sheet, opens TopUpSheet), or
/// switch the payment method to cash and retry.
class InsufficientBalanceSheet extends StatelessWidget {
  final int requiredPaise;
  final VoidCallback onSwitchToCash;

  const InsufficientBalanceSheet({
    super.key,
    required this.requiredPaise,
    required this.onSwitchToCash,
  });

  void _topUp(BuildContext context) {
    Navigator.of(context).pop();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TopUpSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
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
          const Icon(
            PhosphorIconsFill.wallet,
            color: AppColors.warningYellow,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            'Wallet balance is too low',
            style: AppTextStyles.h2(context),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'This session needs ${Money.fromPaise(requiredPaise)}.',
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Top up wallet',
              onPressed: () => _topUp(context),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onSwitchToCash();
            },
            child: const Text('Switch to cash at venue'),
          ),
        ],
      ),
    );
  }
}
