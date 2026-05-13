import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/current_family_provider.dart';
import '../../core/providers/onboarding_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/progress_dots.dart';
import 'skip_confirmation_sheet.dart';

/// Onboarding step 2 — the cafe-only-with-friction decision point.
///
/// Visual hierarchy is intentional: "Add child" is the dominant CTA;
/// "Just here for coffee" is a quiet text link below it.
class AddChildScreen extends ConsumerStatefulWidget {
  const AddChildScreen({super.key});

  @override
  ConsumerState<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends ConsumerState<AddChildScreen> {
  bool _isSkipping = false;
  String? _errorText;

  Future<void> _addChild() async {
    await ref
        .read(onboardingStepProvider.notifier)
        .setStep(OnboardingStep.childDetails);
    if (!mounted) return;
    context.go('/onboarding/child-details');
  }

  Future<void> _skipToCafeOnly() async {
    final confirmed = await showSkipConfirmationSheet(context);
    if (confirmed != true) return;

    setState(() {
      _isSkipping = true;
      _errorText = null;
    });

    try {
      await Supabase.instance.client.rpc<Map<String, dynamic>>('family_set_cafe_only');
      ref.invalidate(currentFamilyProvider);
      await ref
          .read(onboardingStepProvider.notifier)
          .setStep(OnboardingStep.complete);

      if (!mounted) return;
      context.go('/home');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = "Couldn't continue. Please try again.";
        _isSkipping = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const ProgressDots(currentStep: 2),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isSkipping
              ? null
              : () async {
                  await ref
                      .read(onboardingStepProvider.notifier)
                      .setStep(OnboardingStep.familyName);
                  if (!context.mounted) return;
                  context.go('/onboarding/family-name');
                },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    PhosphorIconsFill.babyCarriage,
                    size: 48,
                    color: AppColors.navy,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text('Tell us about your kid', style: AppTextStyles.h1(context)),
              const SizedBox(height: 8),
              Text(
                "We'll set up their adventure profile.",
                style: AppTextStyles.body(context,
                    color: AppColors.lightTextSecondary),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Add child',
                  onPressed: _isSkipping ? null : _addChild,
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _errorText!,
                    style: AppTextStyles.caption(context,
                        color: AppColors.adminRed),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _isSkipping ? null : _skipToCafeOnly,
                  child: Text(
                    "I'm just here for coffee — skip for now",
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
