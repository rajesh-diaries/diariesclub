import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/family_children_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/active_session_card.dart';
import '../widgets/announcements_feed.dart';
import '../widgets/healthy_bite_reminder_banner.dart';
import '../widgets/home_banner_carousel.dart';
import '../widgets/birthday_card.dart';
import '../widgets/home_combos_strip.dart';
import '../widgets/my_upcoming_workshops.dart';
import '../widgets/live_orders_card.dart';
import '../widgets/order_food_card.dart';
import '../widgets/referral_invite_card.dart';
import '../widgets/start_session_card.dart';

/// Home view used whenever the family has at least one open session.
/// Renders a stack of compact session cards (one per child playing) at
/// the top, then the standard idle-home affordances (wallet, Start
/// playing for siblings, birthday, etc.) — so any sibling without a
/// session can start one anytime.
class MultiSessionHomeView extends ConsumerWidget {
  final List<Map<String, dynamic>> sessions;

  const MultiSessionHomeView({super.key, this.sessions = const []});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];

    final childrenInSession = sessions
        .map((s) => s['child_id'] as String?)
        .whereType<String>()
        .toSet();
    final idleChildren = children
        .where((c) => !childrenInSession.contains(c['id'] as String?))
        .toList();
    final hasIdleChildren = idleChildren.isNotEmpty;
    // If there are no children registered yet, still show Start playing
    // (the start screen handles guests / new-child flow).
    final showStartCta = children.isEmpty || hasIdleChildren;

    // At most ONE Healthy Bite nudge on Home, even with several sessions
    // closing: pick the actively-playing session closest to ending that
    // staff hasn't handed the bite over for. The banner itself only appears
    // inside the last 10 minutes and self-hides on claim (Realtime) /
    // dismiss / session end.
    final hbCandidates = sessions
        .where((s) =>
            (s['status'] == 'active' || s['status'] == 'grace') &&
            s['healthy_bite_claimed_at'] == null &&
            s['expires_at'] != null)
        .toList()
      ..sort((a, b) {
        final ae = DateTime.tryParse(a['expires_at'] as String? ?? '');
        final be = DateTime.tryParse(b['expires_at'] as String? ?? '');
        if (ae == null) return 1;
        if (be == null) return -1;
        return ae.compareTo(be);
      });
    final Map<String, dynamic>? primaryHealthyBiteSession =
        hbCandidates.isEmpty ? null : hbCandidates.first;

    // Greeting now lives in [HomeAppBar]. Start with the immersive
    // ActiveSessionsCard so the parent sees the timer first.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: kHomeSectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ActiveSessionsCard(sessions: sessions),
          // Single complimentary Healthy Bite nudge (see primary session
          // selection above) — shown only inside the last 10 minutes and
          // self-hiding on claim (Realtime) / dismiss / session end.
          if (primaryHealthyBiteSession != null)
            HealthyBiteReminderBanner(session: primaryHealthyBiteSession),
          // In-flight kitchen status — mirrors what the staff app sees,
          // so the parent watches their cappuccino move placed →
          // preparing → ready in real time. Hidden when nothing is in
          // flight, so it doesn't compete with the Order food CTA when
          // there's nothing to track yet.
          const SizedBox(height: kHomeSectionGap),
          const LiveOrdersCard(),
          // Promotional banner comes after personalized info (timer + live
          // orders) so it never pushes actionable content below the fold.
          const SizedBox(height: kHomeSectionGap),
          const HomeBannerCarousel(),
          // Primary CTA while a session is running: order food. Cafe tab
          // gets pre-selected on /club so the parent lands on coffee +
          // snacks directly.
          const SizedBox(height: kHomeSectionGap),
          const OrderFoodCard(),
          // Secondary CTA: only when at least one sibling is idle. Lets
          // the parent start a session for the other kid without leaving
          // home.
          if (showStartCta) ...[
            const SizedBox(height: kHomeSectionGap),
            StartSessionCard(compact: idleChildren.length == 1),
          ],
          // Active-session view always shows the invite card (referral
          // redemption is gated on no completed sessions — by the time
          // the family is here, they can't redeem someone else's code
          // anymore, so promote sharing their own instead).
          const SizedBox(height: kHomeSectionGap),
          const ReferralInviteCard(),
          // Announcements moved BELOW the live session(s) — the primary
          // attention moment is what's playing right now.
          const AnnouncementsFeed(),
          const SizedBox(height: kHomeSectionGap),
          const HomeCombosStrip(),
          const SizedBox(height: kHomeSectionGap),
          const BirthdayCardList(),
          const SizedBox(height: kHomeSectionGap),
          const MyUpcomingWorkshopsSection(),
          const SizedBox(height: kHomeSectionGap),
        ],
      ),
    );
  }
}
