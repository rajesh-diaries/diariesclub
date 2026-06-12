import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import 'safari_colors.dart';

class SafariWhatItIs extends StatelessWidget {
  const SafariWhatItIs({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What it is',
            style: AppTextStyles.h3(
              context,
              color: SafariColors.jungleGreen,
            ),
          ),
          const SizedBox(height: 20),
          const _InfoCard(
            icon: PhosphorIconsRegular.calendar,
            title: 'Age 2–5 years',
            subtitle: 'Monday – Friday',
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: PhosphorIconsRegular.clock,
            title: '9:30 AM – 12:30 PM',
            subtitle: 'Morning sessions',
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: PhosphorIconsRegular.mapPin,
            title: 'Play Diaries Centre',
            subtitle: 'A safe, inspiring space to explore',
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: PhosphorIconsRegular.bowlFood,
            title: 'Healthy snacks & meals',
            subtitle: 'Optional, wholesome add-ons available',
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: SafariColors.lightSage,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: SafariColors.jungleGreen, size: 20),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.body(
                  context,
                  color: SafariColors.slate,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
