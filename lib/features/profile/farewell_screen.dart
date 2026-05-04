import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Soft, dignified farewell after account deletion. No app bar, no back —
/// the only path forward is the "Back to start" button which routes to
/// the splash so a brand-new sign-up can begin.
class FarewellScreen extends StatelessWidget {
  const FarewellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(
                PhosphorIconsFill.handWaving,
                size: 80,
                color: AppColors.gold,
              ),
              const SizedBox(height: 24),
              Text(
                "We'll miss you.",
                style: AppTextStyles.h1(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your account has been deleted. '
                'Thanks for being part of Diaries Club.',
                style: AppTextStyles.body(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => context.go('/'),
                child: const Text('Back to start'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
