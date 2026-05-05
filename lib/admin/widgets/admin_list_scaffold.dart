import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'admin_app_bar.dart';

/// Common shell for admin list screens (Module 2.1 view-only stubs and
/// future CRUD screens). Provides:
///   - AppBar with title
///   - Optional placeholder banner (used by view-only stubs to flag
///     "Create / Edit coming soon")
///   - Padded body slot
///   - Empty-state widget when [isEmpty] is true and [emptyState] is set
class AdminListScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? placeholderBanner;
  final Widget body;
  final Widget? emptyState;
  final bool isEmpty;
  final List<Widget>? actions;

  const AdminListScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.placeholderBanner,
    this.emptyState,
    this.isEmpty = false,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AdminAppBar(title: title, actions: actions),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (subtitle != null) ...[
              Text(
                subtitle!,
                style: AppTextStyles.body(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (placeholderBanner != null) ...[
              _PlaceholderBanner(message: placeholderBanner!),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: isEmpty && emptyState != null ? emptyState! : body,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderBanner extends StatelessWidget {
  final String message;
  const _PlaceholderBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.10),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.40)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            PhosphorIconsRegular.wrench,
            color: AppColors.gold,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.body(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Default empty-state widget — centred icon + label + optional subtitle.
class AdminListEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? subtitle;
  const AdminListEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.lightTextSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              style: AppTextStyles.bodyLarge(context),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: AppTextStyles.body(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
