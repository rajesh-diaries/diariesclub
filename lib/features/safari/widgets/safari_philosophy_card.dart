import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_text_styles.dart';
import 'safari_colors.dart';

class SafariPhilosophyCard extends StatelessWidget {
  const SafariPhilosophyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: SafariColors.lightSage,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Why Safari Club?',
            style: AppTextStyles.bodyLarge(
              context,
              color: SafariColors.jungleGreen,
            ),
          ),
          const SizedBox(height: 16),
          const _PhilosophyItem(
            icon: PhosphorIconsRegular.star,
            text:
                'Built around four life traits — Every session grows Brave, Curious, Kind, and Creative through guided play.',
          ),
          const SizedBox(height: 12),
          const _PhilosophyItem(
            icon: PhosphorIconsRegular.users,
            text:
                'Real-world skills through play — Sharing, communication, routines, independence, and empathy learned naturally.',
          ),
          const SizedBox(height: 12),
          const _PhilosophyItem(
            icon: PhosphorIconsRegular.heart,
            text:
                'Outcomes you can picture — They carry these traits into every classroom, playground, and conversation.',
          ),
        ],
      ),
    );
  }
}

class _PhilosophyItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PhilosophyItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: SafariColors.jungleGreen, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.body(
              context,
              color: SafariColors.slate,
            ),
          ),
        ),
      ],
    );
  }
}
