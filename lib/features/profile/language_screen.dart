import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Placeholder language picker for v1. Only English is wired; Hindi and
/// Telugu are listed as "coming soon" so users know multi-language is on
/// the roadmap.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Language'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ListTile(
              leading: const Icon(
                PhosphorIconsRegular.check,
                color: AppColors.activeGreen,
              ),
              title: Text('English', style: AppTextStyles.body(context)),
              subtitle: Text(
                'Currently the only supported language.',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.lightBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'COMING SOON',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ).copyWith(letterSpacing: 1.0),
              ),
            ),
            ListTile(
              title: Text('हिन्दी', style: AppTextStyles.body(context)),
              enabled: false,
            ),
            ListTile(
              title: Text('తెలుగు', style: AppTextStyles.body(context)),
              enabled: false,
            ),
          ],
        ),
      ),
    );
  }
}
