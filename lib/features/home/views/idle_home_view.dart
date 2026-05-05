import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/current_family_provider.dart';
import '../../../core/theme/app_text_styles.dart';
import '../widgets/announcements_feed.dart';
import '../widgets/birthday_card.dart';
import '../widgets/healthy_bite_widget.dart';
import '../widgets/marketing_consent_card.dart';
import '../widgets/recent_activity_list.dart';
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
        const RecentActivityList(),
        const SizedBox(height: 32),
      ],
    );
  }
}
