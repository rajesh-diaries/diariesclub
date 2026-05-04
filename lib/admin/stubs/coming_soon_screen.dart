import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_app_bar.dart';

/// Placeholder used by the six stub admin sections (Workshops, Catalog,
/// Content, Reports, Reactivation, System Health). Routes are wired
/// today; full CRUD ships in a follow-up session.
class ComingSoonScreen extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final String? rationale;
  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.rationale,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AdminAppBar(title: title),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 64, color: AppColors.lightTextSecondary),
                const SizedBox(height: 24),
                Text(
                  description,
                  style: AppTextStyles.h3(context),
                  textAlign: TextAlign.center,
                ),
                if (rationale != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    rationale!,
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'Coming in v1.1',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.navy,
                    ),
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
