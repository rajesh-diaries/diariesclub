import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/active_sessions_provider.dart';
import '../../../core/providers/current_family_provider.dart';
import '../../../core/providers/family_children_provider.dart';
import '../../../core/providers/referral_eligibility_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../widgets/active_session_card.dart';
import '../widgets/announcements_feed.dart';
import '../widgets/birthday_card.dart';
import '../widgets/healthy_bite_widget.dart';
import '../widgets/hero_quests_card.dart';
import '../widgets/home_combos_strip.dart';
import '../widgets/marketing_consent_card.dart';
import '../widgets/my_upcoming_workshops.dart';
import '../widgets/recent_activity_list.dart';
import '../widgets/referral_entry_card.dart';
import '../widgets/start_session_card.dart';
import '../widgets/wallet_card.dart';

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
    final referralEligible = ref
        .watch(referralRedeemEligibleProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);

    final childrenInSession = sessions
        .map((s) => s['child_id'] as String?)
        .whereType<String>()
        .toSet();
    final hasIdleChildren = children
        .any((c) => !childrenInSession.contains(c['id'] as String?));
    // If there are no children registered yet, still show Start playing
    // (the start screen handles guests / new-child flow).
    final showStartCta = children.isEmpty || hasIdleChildren;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Compact wallet pill at top — small + clean. Big top-up
          // experience moves to the idle home view.
          const WalletCard(compact: true),
          const SizedBox(height: 16),
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
                sessions.length == 1
                    ? '1 playing'
                    : '${sessions.length} playing',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final s in sessions) ...[
            ActiveSessionCard(session: s),
            const SizedBox(height: 10),
          ],
          if (showStartCta) ...[
            const SizedBox(height: 8),
            const StartSessionCard(),
          ],
          if (referralEligible) ...[
            const SizedBox(height: 16),
            const ReferralEntryCard(),
          ],
          const SizedBox(height: 20),
          const HeroQuestsCard(),
          const SizedBox(height: 16),
          const HomeCombosStrip(),
          const SizedBox(height: 16),
          const BirthdayCardList(),
          const SizedBox(height: 16),
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
      ),
    );
  }
}
