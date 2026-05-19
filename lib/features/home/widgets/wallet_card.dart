import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/current_wallet_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import 'top_up_sheet.dart';

/// Wallet card. Two sizes:
///   * regular — Home idle layout (large, prominent, gradient).
///   * compact — Home active layout (slim row, just balance + Top up CTA).
class WalletCard extends ConsumerWidget {
  final bool compact;
  const WalletCard({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(currentWalletProvider);

    return wallet.when(
      data: (w) => _Card(
        compact: compact,
        balancePaise: (w?['balance_paise'] as int?) ?? 0,
        heldPaise: (w?['held_paise'] as int?) ?? 0,
        coinsBalance: (w?['coins_balance'] as int?) ?? 0,
        loaded: w != null,
      ),
      loading: () => _Card(
        compact: compact,
        balancePaise: 0,
        heldPaise: 0,
        coinsBalance: 0,
        loaded: false,
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _Card extends StatelessWidget {
  final bool compact;
  final int balancePaise;
  final int heldPaise;
  final int coinsBalance;
  final bool loaded;
  const _Card({
    required this.compact,
    required this.balancePaise,
    required this.heldPaise,
    required this.coinsBalance,
    required this.loaded,
  });

  void _showTopUp(BuildContext c) {
    showModalBottomSheet<void>(
      context: c,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TopUpSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, Color(0xFF2A4A8B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: EdgeInsets.all(compact ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Wallet',
                style: AppTextStyles.caption(context, color: Colors.white70),
              ),
              const Spacer(),
              if (!compact)
                const Icon(
                  PhosphorIconsFill.wallet,
                  color: Colors.white70,
                  size: 20,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            loaded ? Money.fromPaise(balancePaise) : '—',
            style: compact
                ? AppTextStyles.h2(context, color: Colors.white)
                : AppTextStyles.display(context, color: Colors.white),
          ),
          // BUG-004 hold-then-charge — surface held amount so the customer
          // knows the difference between "what you have" and "what's
          // available to spend right now".
          if (loaded && heldPaise > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  PhosphorIconsRegular.lockSimple,
                  color: AppColors.gold,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  '${Money.fromPaise(heldPaise)} held for active session',
                  style: AppTextStyles.caption(context, color: AppColors.gold),
                ),
              ],
            ),
          ],
          if (coinsBalance > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  PhosphorIconsFill.coin,
                  color: AppColors.gold,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  '$coinsBalance Coins '
                  '(${coinsBalance >= 100 ? "redeem in Profile" : "${100 - coinsBalance} more to redeem"})',
                  style: AppTextStyles.caption(context, color: AppColors.gold),
                ),
              ],
            ),
          ],
          SizedBox(height: compact ? 12 : 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _showTopUp(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white, width: 1.5),
                padding:
                    EdgeInsets.symmetric(vertical: compact ? 10 : 14),
              ),
              child: Text(
                compact ? 'Top up' : 'Top up wallet',
                style: AppTextStyles.button(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
