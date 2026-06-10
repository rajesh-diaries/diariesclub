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
      child: Column(
        children: [
          const Text(
            'Safari Club',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
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
              const SizedBox(width: 12),
              _HeroAvatar(imagePath: 'assets/hero/gerry.png'),
              const SizedBox(width: 12),
              _HeroAvatar(imagePath: 'assets/hero/ellie.png'),
              const SizedBox(width: 12),
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
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 2),
        image: DecorationImage(
          image: AssetImage(imagePath),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
