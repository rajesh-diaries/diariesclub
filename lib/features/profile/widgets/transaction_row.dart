import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';

/// One row in the wallet history list. Renders icon/title/amount based on
/// the `type` enum from `wallet_transactions`. Tapping the row opens the
/// detail sheet with raw refs (handled by the parent screen).
class TransactionRow extends StatelessWidget {
  final Map<String, dynamic> tx;
  final VoidCallback onTap;
  const TransactionRow({super.key, required this.tx, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final type = (tx['type'] as String?) ?? '';
    final amount = (tx['amount_paise'] as int?) ?? 0;
    final coins = (tx['coins_amount'] as int?) ?? 0;

    final (icon, color, title) = _present(type, amount, coins);
    final isCredit = amount > 0 || coins > 0;
    final amountText = type == 'coins_credit' || type == 'coins_debit'
        ? '${coins > 0 ? '+' : ''}$coins coins'
        : '${amount >= 0 ? '+' : ''}${Money.fromPaise(amount.abs() * (amount >= 0 ? 1 : -1))}';
    final shownAmount = amount >= 0
        ? '+${Money.fromPaise(amount)}'
        : '-${Money.fromPaise(-amount)}';

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.15),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: AppTextStyles.body(context)),
      subtitle: Text(
        _relativeTime(tx['created_at'] as String?),
        style: AppTextStyles.caption(
          context,
          color: AppColors.lightTextSecondary,
        ),
      ),
      trailing: Text(
        type == 'coins_credit' || type == 'coins_debit'
            ? amountText
            : shownAmount,
        style: AppTextStyles.bodyLarge(
          context,
          color: isCredit ? AppColors.activeGreen : AppColors.lightTextPrimary,
        ),
      ),
    );
  }

  /// Maps wallet_transactions.type → (icon, color, title) for the row.
  /// Per spec §5.3 — covers all 14+ enum values.
  (IconData, Color, String) _present(String type, int amount, int coins) =>
      switch (type) {
        'topup' => (
            PhosphorIconsRegular.wallet,
            AppColors.activeGreen,
            'Topped up',
          ),
        'bonus' => (
            PhosphorIconsRegular.gift,
            AppColors.gold,
            'Bonus credit',
          ),
        'session_debit' => (
            PhosphorIconsRegular.timer,
            AppColors.navy,
            'Play session',
          ),
        'extension_debit' => (
            PhosphorIconsRegular.clockClockwise,
            AppColors.navy,
            'Session extended',
          ),
        'order_debit' => (
            PhosphorIconsRegular.coffee,
            AppColors.coffeeBrown,
            'Café/FIT order',
          ),
        'workshop_debit' => (
            PhosphorIconsRegular.paintBrush,
            AppColors.xpPurple,
            'Workshop',
          ),
        'birthday_deposit_debit' => (
            PhosphorIconsRegular.cake,
            AppColors.rafiCoral,
            'Birthday deposit',
          ),
        'birthday_balance_debit' => (
            PhosphorIconsRegular.cake,
            AppColors.rafiCoral,
            'Birthday balance',
          ),
        'refund' => (
            PhosphorIconsRegular.arrowUUpLeft,
            AppColors.activeGreen,
            'Refund',
          ),
        'coins_credit' => (
            PhosphorIconsRegular.star,
            AppColors.gold,
            'Coins earned',
          ),
        'coins_debit' => (
            PhosphorIconsRegular.star,
            AppColors.lightTextSecondary,
            'Coins redeemed',
          ),
        'reactivation_credit' => (
            PhosphorIconsRegular.sparkle,
            AppColors.gold,
            'Welcome back credit',
          ),
        'visit_bonus' => (
            PhosphorIconsRegular.confetti,
            AppColors.gold,
            'Visit milestone',
          ),
        'streak_milestone' => (
            PhosphorIconsRegular.fire,
            AppColors.gold,
            'Streak reward',
          ),
        'manual_credit' => (
            PhosphorIconsRegular.pencil,
            AppColors.lightTextSecondary,
            'Admin credit',
          ),
        'manual_debit' => (
            PhosphorIconsRegular.pencil,
            AppColors.lightTextSecondary,
            'Admin adjustment',
          ),
        _ => (
            PhosphorIconsRegular.circle,
            AppColors.lightTextSecondary,
            type,
          ),
      };

  String _relativeTime(String? iso) {
    if (iso == null) return '';
    final t = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][t.month - 1];
    return '$m ${t.day}';
  }
}
