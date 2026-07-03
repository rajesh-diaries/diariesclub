import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import 'widgets/safari_announcement_card.dart';
import 'widgets/safari_colors.dart';
import 'widgets/safari_faq_section.dart';
import 'widgets/safari_hero_banner.dart';
import 'widgets/safari_philosophy_card.dart';
import 'widgets/safari_trait_video_card.dart';
import 'widgets/safari_typical_morning.dart';
import 'widgets/safari_waitlist_form.dart';
import 'widgets/safari_what_it_is.dart';

class SafariScreen extends StatefulWidget {
  const SafariScreen({super.key});

  @override
  State<SafariScreen> createState() => _SafariScreenState();
}

class _SafariScreenState extends State<SafariScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SafariColors.softCream,
      body: ListView(
        padding: EdgeInsets.zero,
        children: const [
          SafariHeroBanner(),
          SafariAnnouncementCard(),
          SizedBox(height: 16),
          SafariWhatItIs(),
          SizedBox(height: 32),
          SafariPhilosophyCard(),
          SizedBox(height: 32),
          SafariTypicalMorning(),
          SizedBox(height: 32),
          _FourTraitsSection(),
          SizedBox(height: 32),
          SafariFaqSection(),
          SizedBox(height: 32),
          SafariWaitlistForm(),
          SizedBox(height: 32),
          _Footer(),
          SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _FourTraitsSection extends StatelessWidget {
  const _FourTraitsSection();

  final List<Map<String, String>> _traits = const [
    {
      'image': 'assets/hero/rafi.png',
      'title': 'Brave like Rafi',
      'desc': 'Trying new things, speaking up, and bouncing back.',
      'scenario': 'Going first on the slide',
      'video': 'assets/videos/rafi_brave.mp4',
    },
    {
      'image': 'assets/hero/gerry.png',
      'title': 'Curious like Gerry',
      'desc': 'Asking "why?", exploring, and wondering.',
      'scenario': 'Looking under a rock',
      'video': 'assets/videos/gerry_curious.mp4',
    },
    {
      'image': 'assets/hero/ellie.png',
      'title': 'Kind like Ellie',
      'desc': 'Sharing, including others, and caring.',
      'scenario': 'Sharing snack time',
      'video': 'assets/videos/ellie_kind.mp4',
    },
    {
      'image': 'assets/hero/zena.png',
      'title': 'Creative like Zena',
      'desc': 'Imagining, building, and finding new ways.',
      'scenario': 'Painting with unexpected tools',
      'video': 'assets/videos/zena_creative.mp4',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Text(
            'The Four Traits',
            style: AppTextStyles.h3(context, color: SafariColors.jungleGreen),
          ),
          const SizedBox(height: 24),
          ..._traits.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SafariTraitVideoCard(
                title: t['title']!,
                description: t['desc']!,
                scenario: t['scenario']!,
                placeholderImage: t['image']!,
                videoAsset: t['video']!,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Safari Club · Play Diaries',
        style: AppTextStyles.caption(context, color: const Color(0xFFAAAAAA)),
      ),
    );
  }
}
