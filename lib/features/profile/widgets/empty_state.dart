import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Bottom-nav tab roots — when the empty-state CTA points at one of
/// these we must use `context.go` (swap shell), not `context.push`.
const _bottomNavTabs = <String>{'/home', '/club', '/adventure', '/profile'};

/// Reusable empty-state for activity sub-screens. Centred icon + line +
/// optional CTA that navigates to a related discovery surface.
class ProfileEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? ctaLabel;
  final String? ctaRoute;

  const ProfileEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.ctaLabel,
    this.ctaRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.lightTextSecondary),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (ctaLabel != null && ctaRoute != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                // Two route shapes go through this widget and need
                // different navigation verbs:
                //   * bottom-nav tab roots (/home, /club, /adventure,
                //     /profile) → context.go so we swap the active shell;
                //     pushing on top of the Profile shell rendered /club
                //     inside the wrong StatefulShellBranch and produced
                //     a blank screen.
                //   * regular routes (/session/start, /birthday, etc.)
                //     → context.push so the customer keeps a back button.
                //     The earlier blanket context.go left users stuck on
                //     /session/start with no way to return to Profile.
                onPressed: () => _bottomNavTabs.contains(ctaRoute)
                    ? context.go(ctaRoute!)
                    : context.push(ctaRoute!),
                child: Text(ctaLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
