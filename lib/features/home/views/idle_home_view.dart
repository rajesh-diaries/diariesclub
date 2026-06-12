import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/referral_eligibility_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/announcements_feed.dart';
import '../widgets/big_start_session_card.dart';
import '../widgets/birthday_card.dart';
import '../widgets/home_banner_carousel.dart';
import '../widgets/home_combos_strip.dart';
import '../widgets/live_orders_card.dart';
import '../widgets/my_upcoming_workshops.dart';
import '../widgets/order_food_card.dart';
import '../widgets/play_pass_promo_card.dart';
import '../widgets/recent_activity_list.dart';
import '../widgets/referral_entry_card.dart';

/// "No active session" state. Greeting + wallet + start CTA + birthday +
/// soft prompts + recent activity. Most users land here on every cold open.
class IdleHomeView extends ConsumerWidget {
  const IdleHomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SingleChildScrollView(
      padding: EdgeInsets.only(left: 20, right: 20, bottom: 12),
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
    // Only include the referral entry card when the provider has
    // explicit data (eligible == true). Skipping inclusion entirely is
    // safer than rendering a 0-sized widget — Flutter web's hit-test
    // can cascade-fail over a SizedBox.shrink in the tree.
    final referralEligible = ref
        .watch(referralRedeemEligibleProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);

    // Order: big "Shall we start a session?" card (always pinned at top
    // so the primary CTA is the first thing below the app-bar greeting)
    // → combos → birthday → workshops → announcements → activity.
    // Sections that have nothing to show return SizedBox.shrink so they
    // don't leave phantom gaps.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BigStartSessionCard(),
        const SizedBox(height: kHomeSectionGap),
        const HomeBannerCarousel(),
        const SizedBox(height: kHomeSectionGap),
        const PlayPassPromoCard(),
        // Order food without starting a session — e.g. parent drops by
        // just for coffee/snacks, or wants to pre-order while planning.
        const SizedBox(height: kHomeSectionGap),
        const OrderFoodCard(),
        // Live orders the parent placed during a session that just
        // ended — show them above reflections so they can track the
        // kitchen without losing the cards behind a finished session.
        // Self-hides when there are no in-flight orders.
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: LiveOrdersCard(),
        ),
        if (referralEligible) ...[
          const SizedBox(height: kHomeSectionGap),
          const ReferralEntryCard(),
        ],
        const SizedBox(height: kHomeSectionGap),
        const HomeCombosStrip(),
        const SizedBox(height: kHomeSectionGap),
        const BirthdayCardList(),
        const SizedBox(height: kHomeSectionGap),
        const MyUpcomingWorkshopsSection(),
        // Announcements moved BELOW the start CTA so the primary
        // action lands first. Self-margined: collapses if no rows.
        const AnnouncementsFeed(),
        const SizedBox(height: kHomeSectionGap),
        const RecentActivityList(),
        const SizedBox(height: 20),
      ],
    );
  }
}
