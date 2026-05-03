import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Tab 1 — Home. Birthday card, current session, quick actions land here in
/// later sessions. For now: a friendly "Hello world" with theme verification.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diaries Club')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(PhosphorIconsFill.house, size: 64, color: AppColors.navy),
              const SizedBox(height: 24),
              Text('Welcome home', style: AppTextStyles.h1(context)),
              const SizedBox(height: 8),
              Text(
                'Foundation up. Features land in upcoming sessions.',
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
