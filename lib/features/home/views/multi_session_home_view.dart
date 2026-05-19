import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/active_sessions_provider.dart';
import '../../../core/providers/current_family_provider.dart';
import '../../../core/providers/family_children_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../widgets/active_session_card.dart';
import '../widgets/announcements_feed.dart';
import '../widgets/birthday_card.dart';
import '../widgets/home_combos_strip.dart';
import '../widgets/my_upcoming_workshops.dart';
import '../widgets/live_orders_card.dart';
import '../widgets/order_food_card.dart';
import '../widgets/pending_reflections_section.dart';
import '../widgets/recent_activity_list.dart';
import '../widgets/referral_invite_card.dart';
import '../widgets/start_session_card.dart';

/// Home view used whenever the family has at least one open session.
/// Renders a stack of compact session cards (one per child playing) at
/// the top, then the standard idle-home affordances (wallet, Start
/// playing for siblings, birthday, etc.) — so any sibling without a
/// session can start one anytime.
class MultiSessionHomeView extends ConsumerWidget {
  const MultiSessionHomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(activeSessionsProvider).valueOrNull ?? const [];
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    final family = ref.watch(currentFamilyProvider).valueOrNull;
    final familyName = (family?['name'] as String?) ?? '';

    final childrenInSession = sessions
        .map((s) => s['child_id'] as String?)
        .whereType<String>()
        .toSet();
    final hasIdleChildren = children
        .any((c) => !childrenInSession.contains(c['id'] as String?));
    // If there are no children registered yet, still show Start playing
    // (the start screen handles guests / new-child flow).
    final showStartCta = children.isEmpty || hasIdleChildren;

    // Greeting first, then the immersive ActiveSessionsCard with a ring
    // timer per kid (character-tinted). Wallet pill lives in the top app
    // bar so we don't render WalletCard here.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  familyName.isEmpty
                      ? 'Hi there 👋'
                      : 'Hi, ${familyName.split(' ').first} 👋',
                  style: AppTextStyles.h2(context),
                ),
              ),
              Text(
                // Count by unique child — matches ActiveSessionsCard's
                // dedupe so the badge can never disagree with the rings.
                childrenInSession.length == 1
                    ? '1 playing'
                    : '${childrenInSession.length} playing',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ActiveSessionsCard(sessions: sessions),
          // In-flight kitchen status — mirrors what the staff app sees,
          // so the parent watches their cappuccino move placed →
          // preparing → ready in real time. Hidden when nothing is in
          // flight, so it doesn't compete with the Order food CTA when
          // there's nothing to track yet.
          const SizedBox(height: 16),
          const LiveOrdersCard(),
          // Primary CTA while a session is running: order food. Cafe tab
          // gets pre-selected on /club so the parent lands on coffee +
          // snacks directly.
          const SizedBox(height: 16),
          const OrderFoodCard(),
          // Secondary CTA: only when at least one sibling is idle. Lets
          // the parent start a session for the other kid without leaving
          // home.
          if (showStartCta) ...[
            const SizedBox(height: 12),
            const StartSessionCard(),
          ],
          // Pending reflections for siblings whose sessions ended within
          // the last 24h. Sits below the live-session block so the active
          // play stays the visual priority, but parent still sees what
          // needs reflecting next.
          const PendingReflectionsSection(),
          // Active-session view always shows the invite card (referral
          // redemption is gated on no completed sessions — by the time
          // the family is here, they can't redeem someone else's code
          // anymore, so promote sharing their own instead).
          const SizedBox(height: 16),
          const ReferralInviteCard(),
          // Announcements moved BELOW the live session(s) — the primary
          // attention moment is what's playing right now.
          const AnnouncementsFeed(),
          const SizedBox(height: 20),
          const HomeCombosStrip(),
          const SizedBox(height: 16),
          const BirthdayCardList(),
          const SizedBox(height: 16),
          const MyUpcomingWorkshopsSection(),
          const SizedBox(height: 16),
          const RecentActivityList(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
