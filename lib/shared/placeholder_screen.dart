import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

/// Generic stub screen for routes whose feature isn't implemented yet.
class PlaceholderScreen extends StatelessWidget {
  final String featureName;
  final String? subtitle;
  final IconData? icon;

  const PlaceholderScreen({
    super.key,
    required this.featureName,
    this.subtitle,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(featureName)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon ?? Icons.construction, size: 64, color: AppColors.gold),
              const SizedBox(height: 24),
              Text(
                featureName,
                style: AppTextStyles.h2(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle ?? 'Coming in a later session.',
                style: AppTextStyles.body(context),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
