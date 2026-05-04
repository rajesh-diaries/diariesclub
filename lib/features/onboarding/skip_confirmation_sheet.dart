import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/primary_button.dart';

/// Bottom sheet shown when a user taps "I'm just here for coffee" on the
/// add-child screen. The friction screen — gives them one more chance to
/// reconsider before we flip them to cafe-only.
///
/// Returns `true` if the user confirms the skip; `false` (or null on dismiss)
/// otherwise.
Future<bool?> showSkipConfirmationSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const _SkipConfirmationSheet(),
  );
}

class _SkipConfirmationSheet extends StatelessWidget {
  const _SkipConfirmationSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Skip child setup?', style: AppTextStyles.h2(context)),
          const SizedBox(height: 12),
          Text(
            'You can still order from Coffee Diaries and FIT Diaries. '
            'You can add a child anytime from your Profile.',
            style: AppTextStyles.body(context,
                color: AppColors.lightTextSecondary),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Add child',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Skip for now'),
          ),
        ],
      ),
    );
  }
}
