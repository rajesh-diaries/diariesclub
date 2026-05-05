import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/venue_config_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/primary_button.dart';
import '../../flavors.dart';

/// Step 1 of auth: collect phone, gate behind 18+ guardian consent, send
/// OTP via the auth-otp Edge Function.
class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final _phoneController = TextEditingController();
  bool _consentChecked = false;
  bool _isLoading = false;
  String? _errorText;

  bool get _canSubmit =>
      _consentChecked &&
      PhoneNormalizer.isValid(_phoneController.text) &&
      !_isLoading;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = PhoneNormalizer.toE164(_phoneController.text);
    if (phone == null) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'auth-otp',
        body: {'action': 'send', 'phone': phone},
      );

      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['ok'] != true) {
        setState(() {
          _errorText = _mapSendError(data['error'] as String?);
          _isLoading = false;
        });
        return;
      }

      // Persist phone so the OTP screen knows what to verify.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_otp_phone', phone);

      if (!mounted) return;
      // Clear loading before pushing — this screen stays alive in the route
      // stack, so if the user pops back (Wrong number? / browser back) the
      // submit button must show its label, not a stuck spinner.
      setState(() => _isLoading = false);
      context.push('/auth/otp');
    } on FunctionException catch (e) {
      setState(() {
        _errorText = _mapSendError(e.details?.toString());
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _errorText = "Couldn't send code. Please check your connection.";
        _isLoading = false;
      });
    }
  }

  String _mapSendError(String? code) {
    switch (code) {
      case 'rate_limited':
        return 'Too many attempts. Please wait a few minutes.';
      case 'invalid_phone':
        return "That phone number doesn't look right. Please check.";
      case 'sms_send_failed':
      case 'msg91_not_configured':
        return "Couldn't send the SMS. Please try again in a moment.";
      default:
        return "Couldn't send code. Please try again.";
    }
  }

  Future<void> _openUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _openWhatsapp(String? supportPhone) async {
    if (supportPhone == null || supportPhone.isEmpty) return;
    final num = supportPhone.replaceAll(RegExp(r'[^\d]'), '');
    await launchUrl(
      Uri.parse('https://wa.me/$num?text=${Uri.encodeComponent('Need help signing up')}'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final venueAsync = ref.watch(venueConfigProvider);
    final venue = venueAsync.valueOrNull;
    final privacyUrl = venue?['privacy_policy_url'] as String?;
    final termsUrl = venue?['terms_of_service_url'] as String?;
    final supportPhone = venue?['whatsapp_support_phone'] as String?;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),

              // Hero placeholder until art lands. Same row of icons that
              // will become the four-hero illustration.
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _HeroPlaceholder(icon: PhosphorIconsFill.shieldStar, color: AppColors.rafiCoral),
                  SizedBox(width: 12),
                  _HeroPlaceholder(icon: PhosphorIconsFill.heart, color: AppColors.ellieBlue),
                  SizedBox(width: 12),
                  _HeroPlaceholder(icon: PhosphorIconsFill.magnifyingGlass, color: AppColors.gerryAmber),
                  SizedBox(width: 12),
                  _HeroPlaceholder(icon: PhosphorIconsFill.palette, color: AppColors.zenaGreen),
                ],
              ),

              const SizedBox(height: 32),
              Text('Welcome to Diaries Club', style: AppTextStyles.h1(context)),
              const SizedBox(height: 8),
              Text(
                'Enter your phone number to get started.',
                style: AppTextStyles.body(context, color: AppColors.lightTextSecondary),
              ),
              const SizedBox(height: 40),

              _PhoneField(
                controller: _phoneController,
                onChanged: () => setState(() {}),
              ),

              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _errorText!,
                    style: AppTextStyles.caption(context, color: AppColors.adminRed),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              _ConsentCheckbox(
                checked: _consentChecked,
                onChanged: (v) => setState(() => _consentChecked = v),
                privacyUrl: privacyUrl,
                termsUrl: termsUrl,
                onOpenUrl: _openUrl,
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Send code',
                  onPressed: _canSubmit ? _sendOtp : null,
                  loading: _isLoading,
                ),
              ),

              const SizedBox(height: 16),

              if (F.isMockOtp)
                Center(
                  child: Text(
                    'Dev mode — any phone, the code is 123456.',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              Center(
                child: TextButton(
                  onPressed: () => _openWhatsapp(supportPhone),
                  child: Text('Need help?',
                      style: AppTextStyles.caption(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroPlaceholder extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _HeroPlaceholder({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 28),
    );
  }
}

class _PhoneField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;
  const _PhoneField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isValid = PhoneNormalizer.isValid(controller.text);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.lightBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('🇮🇳 +91', style: AppTextStyles.body(context)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            label: 'Phone number',
            hint: 'Enter 10-digit Indian mobile number',
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                hintText: '98765 43210',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: isValid
                    ? const Icon(Icons.check_circle, color: AppColors.activeGreen)
                    : null,
              ),
              style: AppTextStyles.body(context),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConsentCheckbox extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool> onChanged;
  final String? privacyUrl;
  final String? termsUrl;
  final Future<void> Function(String?) onOpenUrl;

  const _ConsentCheckbox({
    required this.checked,
    required this.onChanged,
    required this.privacyUrl,
    required this.termsUrl,
    required this.onOpenUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          checked: checked,
          label: 'I agree to terms and privacy policy',
          child: Checkbox(
            value: checked,
            onChanged: (v) => onChanged(v ?? false),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(!checked),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: RichText(
                text: TextSpan(
                  style: AppTextStyles.caption(context),
                  children: [
                    const TextSpan(
                      text: 'I am 18+ and a parent or guardian. I agree to the ',
                    ),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: const TextStyle(decoration: TextDecoration.underline),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => onOpenUrl(privacyUrl),
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Terms',
                      style: const TextStyle(decoration: TextDecoration.underline),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => onOpenUrl(termsUrl),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
