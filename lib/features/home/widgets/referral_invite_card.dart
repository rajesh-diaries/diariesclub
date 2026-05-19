import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/current_family_provider.dart';
import '../../../core/providers/venue_config_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';

/// Compact "Refer friends" card for the active-session home view.
///
/// Replaces the previous [ReferralEntryCard] (which prompted the parent to
/// enter someone else's code) on screens where the family has already
/// started a session — referral redemption is gated on the family having
/// NO completed sessions, so an entry CTA is moot post-first-session.
/// Tap routes to the full Profile referral details screen, which has the
/// share-via-WhatsApp button and the venue-configurable credit amounts.
class ReferralInviteCard extends ConsumerWidget {
  const ReferralInviteCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final family = ref.watch(currentFamilyProvider).valueOrNull;
    final code = (family?['referral_code'] as String?) ?? '';
    if (code.isEmpty) return const SizedBox.shrink();
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final gifterPaise =
        (cfg['referral_gifter_credit_paise'] as int?) ?? 10000;
    final newFamilyPaise =
        (cfg['referral_new_family_credit_paise'] as int?) ?? 10000;
    // Show the bigger of the two so the headline is honest in both
    // directions — both sides currently get ₹100 by default.
    final headlineAmount = gifterPaise >= newFamilyPaise
        ? gifterPaise
        : newFamilyPaise;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push('/profile/referral-details'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(PhosphorIconsFill.gift,
                color: AppColors.gold, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Refer friends',
                    style: AppTextStyles.h3(context, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${Money.fromPaise(headlineAmount)} wallet credit each '
                    'after their first visit.',
                    style: AppTextStyles.caption(
                      context,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }
}
