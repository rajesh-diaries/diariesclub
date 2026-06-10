import 'package:flutter/material.dart';
import 'safari_colors.dart';

class SafariHeroBanner extends StatelessWidget {
  const SafariHeroBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: const BoxDecoration(
        color: SafariColors.jungleGreen,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: const Column(
        children: [
          Text(
            'Safari Club',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'A club for little explorers.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _HeroAvatar(imagePath: 'assets/hero/rafi.png'),
              const SizedBox(width: 10),
              _HeroAvatar(imagePath: 'assets/hero/gerry.png'),
              const SizedBox(width: 10),
              _HeroAvatar(imagePath: 'assets/hero/ellie.png'),
              const SizedBox(width: 10),
              _HeroAvatar(imagePath: 'assets/hero/zena.png'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroAvatar extends StatelessWidget {
  final String imagePath;

  const _HeroAvatar({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 1.5),
      ),
      padding: const EdgeInsets.all(4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          imagePath,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
