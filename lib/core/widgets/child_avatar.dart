import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Round avatar for a child — tinted circle with the first letter of
/// the child's name. We deliberately do not store child photos (privacy
/// stance, see docs/POLICY_INVENTORY.md §2.2 / §2.5).
class ChildAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color? fallbackTint;

  const ChildAvatar({
    super.key,
    required this.name,
    required this.size,
    this.fallbackTint,
  });

  @override
  Widget build(BuildContext context) {
    final tint = fallbackTint ?? AppColors.gold.withValues(alpha: 0.18);
    final initial =
        name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
      child: Text(
        initial,
        style: TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}
