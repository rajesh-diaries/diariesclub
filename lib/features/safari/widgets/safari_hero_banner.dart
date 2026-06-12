import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_text_styles.dart';
import 'safari_colors.dart';

class SafariHeroBanner extends StatelessWidget {
  const SafariHeroBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 44),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SafariColors.jungleGreen,
            Color(0xFF1E3D2A),
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft decorative orbs for depth.
          Positioned(
            top: -20,
            right: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SafariColors.warmAmber.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            bottom: -10,
            left: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Column(
            children: [
              // Overlapping character avatars with alternating vertical offset.
              const SizedBox(
                height: 84,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _HeroAvatar(
                      imagePath: 'assets/hero/rafi.png',
                      offset: 0,
                    ),
                    SizedBox(width: 4),
                    _HeroAvatar(
                      imagePath: 'assets/hero/gerry.png',
                      offset: -12,
                    ),
                    SizedBox(width: 4),
                    _HeroAvatar(
                      imagePath: 'assets/hero/ellie.png',
                      offset: 0,
                    ),
                    SizedBox(width: 4),
                    _HeroAvatar(
                      imagePath: 'assets/hero/zena.png',
                      offset: -12,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Safari Club',
                style: AppTextStyles.h1(
                  context,
                  color: Colors.white,
                ).copyWith(fontSize: 34),
              ),
              const SizedBox(height: 6),
              Text(
                'A club for little explorers.',
                style: AppTextStyles.bodyLarge(
                  context,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    PhosphorIconsRegular.users,
                    color: Colors.white60,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Ages 2–5 · Mon–Fri',
                    style: AppTextStyles.caption(
                      context,
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    PhosphorIconsRegular.clock,
                    color: Colors.white60,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '9:30 AM – 12:30 PM',
                    style: AppTextStyles.caption(
                      context,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroAvatar extends StatelessWidget {
  final String imagePath;
  final double offset;

  const _HeroAvatar({required this.imagePath, required this.offset});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, offset),
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
        padding: const EdgeInsets.all(5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            imagePath,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
