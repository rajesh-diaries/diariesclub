import 'package:flutter/material.dart';
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
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What makes Safari Club different?',
            style: TextStyle(
              color: SafariColors.jungleGreen,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          const _PhilosophyItem(
            icon: Icons.favorite_border,
            text: 'Whole-child growth. Social, emotional and creative skills built through play.',
          ),
          const SizedBox(height: 12),
          const _PhilosophyItem(
            icon: Icons.psychology_outlined,
            text: 'Guided exploration. Curiosity-led activities that build confidence and independence.',
          ),
          const SizedBox(height: 12),
          const _PhilosophyItem(
            icon: Icons.school_outlined,
            text: 'Hands-on learning. No screens, no worksheets — just meaningful experiences.',
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
            style: const TextStyle(
              color: SafariColors.slate,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
