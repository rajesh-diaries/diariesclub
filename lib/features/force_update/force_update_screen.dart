import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/app_version_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/primary_button.dart';

/// Hard gate shown when the running app version is below
/// `venue_config.{platform}_min_supported_version`. App Store / Play Store
/// links open via url_launcher.
class ForceUpdateScreen extends ConsumerWidget {
  const ForceUpdateScreen({super.key});

  static const _appStoreUrl =
      'https://apps.apple.com/in/app/diaries-club/id000000000';
  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.diariesclub.app';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionStatusProvider).valueOrNull;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                PhosphorIconsFill.arrowCircleUp,
                size: 80,
                color: AppColors.gold,
              ),
              const SizedBox(height: 24),
              Text(
                'Update required',
                style: AppTextStyles.h1(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Please update Diaries Club to continue.',
                style: AppTextStyles.body(context),
                textAlign: TextAlign.center,
              ),
              if (version != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Installed v${version.currentVersion} · '
                  'Minimum v${version.minVersion}',
                  style: AppTextStyles.caption(context),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 40),
              PrimaryButton(
                label: Platform.isIOS
                    ? 'Update on App Store'
                    : 'Update on Play Store',
                onPressed: () => launchUrl(
                  Uri.parse(Platform.isIOS ? _appStoreUrl : _playStoreUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
