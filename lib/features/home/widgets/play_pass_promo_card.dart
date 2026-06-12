import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/play_passes_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import 'play_pass_purchase_sheet.dart';

/// Promotional card shown on the home screen when the family has no active
/// Play Passes (or as a persistent upsell). Tapping opens the purchase sheet.
class PlayPassPromoCard extends ConsumerWidget {
  const PlayPassPromoCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = ref.watch(remainingPassesCountProvider);

    if (remaining > 0) {
      // Show compact "you have passes" card instead of promo.
      final passes = ref.watch(playPassesProvider).valueOrNull ?? const [];
      return _ActivePassCard(remaining: remaining, passes: passes);
    }

    return _PromoCard(onTap: () => _openSheet(context));
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (_) => const PlayPassPurchaseSheet(),
    );
  }
}

class _PromoCard extends StatelessWidget {
  final VoidCallback onTap;
  const _PromoCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kHomeCardRadius),
      child: Container(
        padding: const EdgeInsets.all(kHomeCardPadding),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E3A7B), Color(0xFF2A4A9B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(kHomeCardRadius),
          boxShadow: [kHomeCardShadow(context)],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                PhosphorIconsFill.ticket,
                color: AppColors.gold,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Play Passes',
                    style: AppTextStyles.cardTitle(context, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Save up to ₹200 per visit. Buy 5, 10 or 15 passes.',
                    style: AppTextStyles.cardSubtitle(
                      context,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              PhosphorIconsRegular.caretRight,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivePassCard extends StatelessWidget {
  final int remaining;
  final List<Map<String, dynamic>> passes;
  const _ActivePassCard({required this.remaining, required this.passes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kHomeCardPadding),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF8EE),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(kHomeCardRadius),
        boxShadow: [kHomeCardShadow(context)],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              PhosphorIconsFill.ticket,
              color: AppColors.gold,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$remaining Play Pass${remaining == 1 ? '' : 'es'}',
                  style: AppTextStyles.cardTitle(context),
                ),
                const SizedBox(height: 2),
                Text(
                  _validityLabel(passes),
                  style: AppTextStyles.cardSubtitle(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _validityLabel(List<Map<String, dynamic>> passes) {
    DateTime? earliest;
    for (final p in passes) {
      final expiry = DateTime.tryParse((p['expires_at'] as String?) ?? '');
      if (expiry == null) continue;
      if (earliest == null || expiry.isBefore(earliest)) earliest = expiry;
    }
    if (earliest == null) return 'Active';
    final now = DateTime.now();
    final days = earliest.difference(now).inDays;
    if (days < 0) return 'Expiring soon';
    if (days <= 7) return 'Expires in $days ${days == 1 ? 'day' : 'days'}';
    return 'Valid until ${DateFormat('d MMM').format(earliest)}';
  }
}
