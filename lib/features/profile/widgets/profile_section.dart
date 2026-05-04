import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// SliverPersistentHeader-friendly section heading. Renders an uppercase
/// label that mirrors iOS Settings groupings.
class ProfileSectionHeader extends StatelessWidget {
  final String title;
  const ProfileSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: AppTextStyles.caption(
          context,
          color: AppColors.lightTextSecondary,
        ).copyWith(letterSpacing: 1.0),
      ),
    );
  }
}

/// Bordered card containing one or more rows. Visually groups settings
/// rows into a single rounded surface (again, iOS-style).
class ProfileSectionCard extends StatelessWidget {
  final List<Widget> children;
  const ProfileSectionCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.lightBorder),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
