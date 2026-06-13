import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/app_theme_mode_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/selection_card.dart';

/// Three radios — System / Light / Dark. Persists to SharedPreferences via
/// `appThemeModeProvider.set` immediately on selection (no separate Save).
class ThemeSelectorSheet extends ConsumerWidget {
  const ThemeSelectorSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    final notifier = ref.read(appThemeModeProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Theme', style: AppTextStyles.h2(context)),
          const SizedBox(height: 8),
          SelectableCard<ThemeMode>(
            value: ThemeMode.system,
            groupValue: mode,
            title: 'System default',
            subtitle: 'Follow your device setting',
            leading: const Icon(
              PhosphorIconsRegular.deviceMobile,
              color: AppColors.navy,
              size: 24,
            ),
            onChanged: (v) => notifier.set(v ?? ThemeMode.system),
          ),
          SelectableCard<ThemeMode>(
            value: ThemeMode.light,
            groupValue: mode,
            title: 'Light',
            subtitle: 'Always use light mode',
            leading: const Icon(
              PhosphorIconsRegular.sun,
              color: AppColors.navy,
              size: 24,
            ),
            onChanged: (v) => notifier.set(v ?? ThemeMode.light),
          ),
          SelectableCard<ThemeMode>(
            value: ThemeMode.dark,
            groupValue: mode,
            title: 'Dark',
            subtitle: 'Always use dark mode',
            leading: const Icon(
              PhosphorIconsRegular.moon,
              color: AppColors.navy,
              size: 24,
            ),
            onChanged: (v) => notifier.set(v ?? ThemeMode.dark),
          ),
        ],
      ),
    );
  }
}
