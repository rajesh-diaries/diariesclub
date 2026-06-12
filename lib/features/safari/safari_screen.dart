import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import 'widgets/safari_announcement_card.dart';
import 'widgets/safari_colors.dart';
import 'widgets/safari_faq_section.dart';
import 'widgets/safari_hero_banner.dart';
import 'widgets/safari_philosophy_card.dart';
import 'widgets/safari_trait_card.dart';
import 'widgets/safari_waitlist_form.dart';
import 'widgets/safari_what_it_is.dart';

class SafariScreen extends StatelessWidget {
  const SafariScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SafariColors.softCream,
      body: ListView(
        padding: EdgeInsets.zero,
        children: const [
          SafariAnnouncementCard(),
          SafariHeroBanner(),
          SizedBox(height: 32),
          SafariPhilosophyCard(),
          SizedBox(height: 32),
          _FourTraitsSection(),
          SizedBox(height: 32),
          SafariWhatItIs(),
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
      'desc': 'The courage to try, fail, and try again. To speak up, stand tall, and explore the unknown without fear.',
    },
    {
      'image': 'assets/hero/gerry.png',
      'title': 'Curious like Gerry',
      'desc': 'The hunger to ask "why?" and "what if?" To look closer, reach higher, and never stop wondering about the world.',
    },
    {
      'image': 'assets/hero/ellie.png',
      'title': 'Kind like Ellie',
      'desc': 'The strength to care, share, and include others. True confidence comes from lifting people up, not putting them down.',
    },
    {
      'image': 'assets/hero/zena.png',
      'title': 'Creative like Zena',
      'desc': 'The ability to see what isn\'t there yet. To adapt, imagine, and build something new from the pieces around you.',
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
            style: AppTextStyles.h3(
              context,
              color: SafariColors.jungleGreen,
            ),
          ),
          const SizedBox(height: 24),
          ..._traits.map((t) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SafariTraitCard(
              imagePath: t['image']!,
              title: t['title']!,
              description: t['desc']!,
            ),
          )),
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
        style: AppTextStyles.caption(
          context,
          color: const Color(0xFFAAAAAA),
        ),
      ),
    );
  }
}
