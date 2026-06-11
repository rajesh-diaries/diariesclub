import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/current_wallet_provider.dart';
import '../../../core/providers/play_passes_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import 'top_up_sheet.dart';

const _passOptions = <Map<String, dynamic>>[
  {
    'type': '5',
    'total': 5,
    'price_paise': 350000,
    'days': 30,
    'label': 'Starter Pack',
    'tag': 'Most popular',
  },
  {
    'type': '10',
    'total': 10,
    'price_paise': 650000,
    'days': 45,
    'label': 'Value Pack',
    'tag': 'Best value',
  },
  {
    'type': '15',
    'total': 15,
    'price_paise': 900000,
    'days': 60,
    'label': 'Family Pack',
    'tag': 'Biggest savings',
  },
];

/// Bottom sheet for purchasing Play Passes. Deducts from wallet balance;
/// if insufficient, routes through the top-up sheet first.
class PlayPassPurchaseSheet extends ConsumerStatefulWidget {
  const PlayPassPurchaseSheet({super.key});

  @override
  ConsumerState<PlayPassPurchaseSheet> createState() =>
      _PlayPassPurchaseSheetState();
}

class _PlayPassPurchaseSheetState extends ConsumerState<PlayPassPurchaseSheet> {
  String? _buyingType; // null = idle, otherwise the pass_type being bought
  String? _errorText;

  Future<void> _buy(Map<String, dynamic> option) async {
    final type = option['type'] as String;
    final price = option['price_paise'] as int;
    final familyId = ref.read(currentFamilyIdProvider);

    if (familyId == null) return;

    setState(() {
      _buyingType = type;
      _errorText = null;
    });

    // Check wallet balance first.
    final balance = ref.read(walletBalancePaiseProvider) ?? 0;
    if (balance < price) {
      if (!mounted) return;
      setState(() => _buyingType = null);
      // Show top-up sheet; after dismissal the parent can retry.
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useRootNavigator: true,
        builder: (_) => const TopUpSheet(),
      );
      return;
    }

    final idem = const Uuid().v4();
    try {
      final res = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('play_pass_purchase', params: {
        'p_family_id': familyId,
        'p_pass_type': type,
        'p_idempotency_key': idem,
      });

      if (!mounted) return;

      if (res['success'] != true) {
        final err = res['error'] as String?;
        if (err == 'insufficient_balance') {
          // Race: balance dropped between read and RPC.
          setState(() {
            _buyingType = null;
            _errorText = 'Not enough wallet balance. Top up first.';
          });
          return;
        }
        setState(() {
          _buyingType = null;
          _errorText = 'Purchase failed. Please try again.';
        });
        return;
      }

      // Success — refresh providers and dismiss.
      ref.invalidate(currentWalletProvider);
      ref.invalidate(playPassesProvider);
      if (!mounted) return;
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${option['label']} purchased! '
            '${option['total']} visits ready to use.',
          ),
        ),
      );
    } catch (e, st) {
      dev.log('[play_pass_purchase] error', error: e, stackTrace: st);
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      String display;
      if (msg.contains('play_pass_purchase') &&
          (msg.contains('does not exist') || msg.contains('unknown'))) {
        display = 'Play Passes are not enabled yet. Please contact support.';
      } else if (msg.contains('insufficient_balance')) {
        display = 'Not enough wallet balance. Top up first.';
      } else if (msg.contains('forbidden') || msg.contains('auth_required')) {
        display = 'Please sign in again.';
      } else {
        display = 'Something went wrong. Please try again.';
      }
      setState(() {
        _buyingType = null;
        _errorText = display;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Handle bar
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
            const SizedBox(height: 20),
            Text(
              'Play Passes',
              style: AppTextStyles.h2(context),
            ),
            const SizedBox(height: 4),
            Text(
              'Buy session credits upfront and save every time you play.',
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 20),
            for (final opt in _passOptions) ...[
              _PassOptionCard(
                option: opt,
                busy: _buyingType == opt['type'],
                onTap: () => _buy(opt),
              ),
              const SizedBox(height: 12),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 4),
              Text(
                _errorText!,
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.adminRed,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Each pass is for a 1-hour play visit. Need more time? Extend '
              'for ₹300 directly from the app after your session starts. '
              '1 kid = 1 pass. No coupons can be used with passes.',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }
}

class _PassOptionCard extends StatelessWidget {
  final Map<String, dynamic> option;
  final bool busy;
  final VoidCallback onTap;

  const _PassOptionCard({
    required this.option,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = option['total'] as int;
    final price = option['price_paise'] as int;
    final days = option['days'] as int;
    final label = option['label'] as String;
    final tag = option['tag'] as String;
    final perSession = price ~/ total;
    const singleSessionPrice = 80000; // 1hr price
    final saves = singleSessionPrice - perSession;

    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '$total Visits',
                        style: AppTextStyles.bodyLarge(context)
                            .copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tag,
                          style: AppTextStyles.caption(context)
                              .copyWith(color: AppColors.navy),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$label · valid for $days days',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        Money.fromPaise(price),
                        style: AppTextStyles.h3(context),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${Money.fromPaise(perSession)}/visit',
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.activeGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Save ${Money.fromPaise(saves)}',
                          style: AppTextStyles.caption(context).copyWith(
                            color: AppColors.fitGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                PhosphorIconsRegular.caretRight,
                color: AppColors.navy,
              ),
          ],
        ),
      ),
    );
  }
}
