import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_app_bar.dart';

/// Module 2.8 — content hub. Cards for the editable content tables
/// (reflection moments, hero cards). FAQ table seed remains a v1.1
/// follow-up (table doesn't exist yet).
class ContentIndexScreen extends StatelessWidget {
  const ContentIndexScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: const AdminAppBar(title: 'Content'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Editable copy + cards used across the app.',
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _ContentCard(
                  icon: PhosphorIconsRegular.heartHalf,
                  title: 'Reflection moments',
                  description:
                      'Tags shown in the reflection sheet. Trait + XP weight + sort order.',
                  onTap: () => context.go('/admin/content/reflection-moments'),
                ),
                _ContentCard(
                  icon: PhosphorIconsRegular.shieldCheck,
                  title: 'Hero cards',
                  description:
                      'Card definitions awarded for hero moments. Per-hero, rare/birthday-exclusive flags, descriptions.',
                  onTap: () => context.go('/admin/content/hero-cards'),
                ),
                const _ContentCard(
                  icon: PhosphorIconsRegular.fileText,
                  title: 'FAQ',
                  description: 'Coming in v1.1 — needs FAQ table seed first.',
                  onTap: null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContentCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;
  const _ContentCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return SizedBox(
      width: 320,
      child: Material(
        color: AppColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.lightBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 28,
                  color: disabled
                      ? AppColors.lightTextSecondary
                      : AppColors.gold,
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: AppTextStyles.h3(context).copyWith(
                    color: disabled ? AppColors.lightTextSecondary : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
