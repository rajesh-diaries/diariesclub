import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/app_theme_mode_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Tab 4 — Profile. Wallet, history, settings, help. Session 5b builds the real one.
/// This stub exposes the theme-mode toggle so the dark/light path can be
/// verified end-to-end as soon as the foundation boots.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    final notifier = ref.read(appThemeModeProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(PhosphorIconsRegular.user, color: AppColors.navy),
            title: Text('Profile features coming soon', style: AppTextStyles.body(context)),
            subtitle: const Text('Full screen lands in Session 5b'),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Theme', style: AppTextStyles.h3(context)),
          ),
          RadioGroup<ThemeMode>(
            groupValue: mode,
            onChanged: (m) => m == null ? null : notifier.set(m),
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: Text('Follow system'),
                  value: ThemeMode.system,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Light'),
                  value: ThemeMode.light,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Dark'),
                  value: ThemeMode.dark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
