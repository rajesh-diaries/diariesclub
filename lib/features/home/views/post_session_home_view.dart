import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import 'idle_home_view.dart';

/// Recently-completed-session state. Hero recap card sits at the top
/// pointing to the reflection screen (Session 6 owns the recap detail);
/// the rest of the page mirrors the idle layout below it.
class PostSessionHomeView extends ConsumerWidget {
  final Map<String, dynamic> session;
  const PostSessionHomeView({super.key, required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionId = session['id'] as String;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/reflection/$sessionId'),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.gold.withValues(alpha: 0.18),
                    AppColors.rafiCoral.withValues(alpha: 0.18),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: AppColors.gold),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(
                    PhosphorIconsFill.medal,
                    color: AppColors.navy,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Adventure complete!',
                          style: AppTextStyles.h3(context),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap to reflect on the play session →',
                          style: AppTextStyles.body(
                            context,
                            color: AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Reuse the idle layout's body below the recap card.
          const IdleHomeBody(),
        ],
      ),
    );
  }
}
