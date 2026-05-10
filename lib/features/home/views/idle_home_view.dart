import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/current_family_provider.dart';
import '../../../core/providers/referral_eligibility_provider.dart';
import '../../../core/theme/app_text_styles.dart';
import '../widgets/announcements_feed.dart';
import '../widgets/birthday_card.dart';
import '../widgets/healthy_bite_widget.dart';
import '../widgets/home_combos_strip.dart';
import '../widgets/marketing_consent_card.dart';
import '../widgets/my_upcoming_workshops.dart';
import '../widgets/recent_activity_list.dart';
import '../widgets/referral_entry_card.dart';
import '../widgets/start_session_card.dart';
import '../widgets/wallet_card.dart';

/// "No active session" state. Greeting + wallet + start CTA + birthday +
/// soft prompts + recent activity. Most users land here on every cold open.
class IdleHomeView extends ConsumerWidget {
  const IdleHomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: IdleHomeBody(),
    );
  }
}

/// Same content as [IdleHomeView] but unwrapped — used inside the
/// post-session view, which adds its own scroll container above this body.
class IdleHomeBody extends ConsumerWidget {
  const IdleHomeBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final family = ref.watch(currentFamilyProvider).valueOrNull;
    final familyName = (family?['name'] as String?) ?? '';
    // Only include the referral entry card when the provider has
    // explicit data (eligible == true). Skipping inclusion entirely is
    // safer than rendering a 0-sized widget — Flutter web's hit-test
    // can cascade-fail over a SizedBox.shrink in the tree.
    final referralEligible = ref
        .watch(referralRedeemEligibleProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          familyName.isEmpty
              ? 'Hi there 👋'
              : 'Hi, ${familyName.split(' ').first} 👋',
          style: AppTextStyles.h1(context),
        ),
        const SizedBox(height: 4),
        Text('Ready for adventure?', style: AppTextStyles.body(context)),
        const SizedBox(height: 20),
        const WalletCard(),
        const SizedBox(height: 16),
        const StartSessionCard(),
        if (referralEligible) ...[
          const SizedBox(height: 16),
          const ReferralEntryCard(),
        ],
        const SizedBox(height: 20),
        const HomeCombosStrip(),
        const SizedBox(height: 16),
        const BirthdayCardList(),
        const SizedBox(height: 16),
        // Module 2.3: announcements section between birthday card and
        // recent activity. Renders nothing when no active rows.
        const AnnouncementsFeed(),
        const MarketingConsentCard(),
        const SizedBox(height: 16),
        const HealthyBiteWidget(),
        const SizedBox(height: 16),
        const MyUpcomingWorkshopsSection(),
        const SizedBox(height: 16),
        const RecentActivityList(),
        const SizedBox(height: 32),
      ],
    );
  }
}
