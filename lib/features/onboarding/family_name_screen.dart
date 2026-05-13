import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/current_family_provider.dart';
import '../../core/providers/onboarding_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/progress_dots.dart';

/// Onboarding step 1 — collect the family name. Calls family_create RPC,
/// which inserts the families row (id = auth.uid()) and lets the
/// families_create_wallet trigger fire automatically.
class FamilyNameScreen extends ConsumerStatefulWidget {
  const FamilyNameScreen({super.key});

  @override
  ConsumerState<FamilyNameScreen> createState() => _FamilyNameScreenState();
}

class _FamilyNameScreenState extends ConsumerState<FamilyNameScreen> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit => _controller.text.trim().length >= 2 && !_isLoading;

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.length < 2) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      // Read pending phone — the OTP screen wrote it before navigating.
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('pending_otp_phone');
      if (phone == null) {
        throw StateError('phone not in preferences');
      }

      await Supabase.instance.client.rpc<Map<String, dynamic>>(
        'family_create',
        params: {'p_phone': phone, 'p_name': name},
      );

      ref.invalidate(currentFamilyProvider);
      await ref
          .read(onboardingStepProvider.notifier)
          .setStep(OnboardingStep.addChild);

      if (!mounted) return;
      context.go('/onboarding/add-child');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = "Couldn't save. Please try again.";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const ProgressDots(currentStep: 1),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text('What should we call you?',
                  style: AppTextStyles.h1(context)),
              const SizedBox(height: 8),
              Text(
                "We'll use this on receipts and to greet you.",
                style: AppTextStyles.body(context,
                    color: AppColors.lightTextSecondary),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Your name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                style: AppTextStyles.body(context),
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
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Continue',
                  onPressed: _canSubmit ? _submit : null,
                  loading: _isLoading,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
