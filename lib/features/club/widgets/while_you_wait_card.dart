import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../providers/cart_provider.dart';
import '../providers/while_you_wait_provider.dart';

/// Soft "While [child] plays..." card on the active-session Home view.
/// Shows only when (a) family has ≥ 2 completed sessions and (b) the
/// caller hasn't dismissed for THIS session_id. Tap "Browse menu" → /club
/// with table-service pre-selected.
class WhileYouWaitCard extends ConsumerWidget {
  /// Active session row from the Home in-session view.
  final Map<String, dynamic> session;
  const WhileYouWaitCard({super.key, required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionId = session['id'] as String?;
    final showAsync = ref.watch(shouldShowWhileYouWaitProvider(sessionId));
    if (showAsync.valueOrNull != true) return const SizedBox.shrink();

    final childName = (session['children']?['name'] as String?) ??
        (session['child_name'] as String?) ??
        'your child';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.coffeeBrown.withValues(alpha: 0.18),
            AppColors.fitGreen.withValues(alpha: 0.18),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                PhosphorIconsFill.coffee,
                color: AppColors.coffeeBrown,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'While $childName plays…',
                style: AppTextStyles.bodyLarge(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Order from Coffee Diaries or FIT and we'll bring it to your table.",
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: () {
                  ref.read(cartFulfillmentProvider.notifier).state =
                      FulfillmentMode.dineIn;
                  context.go('/club');
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Browse menu'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: sessionId == null
                    ? null
                    : () async {
                        await dismissWhileYouWait(sessionId);
                        ref.invalidate(
                            shouldShowWhileYouWaitProvider(sessionId));
                      },
                child: const Text('Not now'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
