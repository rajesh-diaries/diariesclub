import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'primary_button.dart';

/// Friendly error screen with copyable error code + WhatsApp deep link.
/// Used by the GoRouter errorBuilder and feature error states.
class FriendlyErrorScreen extends StatelessWidget {
  final String code; // e.g. 'E-247'
  final String userMessage;
  final String? technicalDetails;
  /// Optional retry callback. When provided, renders a "Retry" button
  /// above the "Copy code & contact support" CTA so transient errors
  /// (network blip, slow Supabase) recover with one tap.
  final VoidCallback? onRetry;

  const FriendlyErrorScreen({
    super.key,
    required this.code,
    required this.userMessage,
    this.technicalDetails,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                PhosphorIconsFill.warningCircle,
                size: 64,
                color: AppColors.warningYellow,
              ),
              const SizedBox(height: 24),
              Text(
                userMessage,
                style: AppTextStyles.h2(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text('Error $code', style: AppTextStyles.caption(context)),
              const SizedBox(height: 32),
              if (onRetry != null) ...[
                PrimaryButton(
                  label: 'Retry',
                  onPressed: onRetry!,
                ),
                const SizedBox(height: 12),
              ],
              PrimaryButton(
                label: 'Copy code & contact support',
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: 'Diaries Club error: $code'),
                  );
                  await launchUrl(
                    Uri.parse(
                      'https://wa.me/919876543210?text=Diaries+Club+error:+$code',
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/home'),
                child: Text(
                  'Back to Home',
                  style: AppTextStyles.button(
                    context,
                    color: AppColors.navy,
                  ),
                ),
              ),
              if (technicalDetails != null && technicalDetails!.isNotEmpty) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.lightBackground,
                    border: Border.all(color: AppColors.lightBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    technicalDetails!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
