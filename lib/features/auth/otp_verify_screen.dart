import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/current_family_provider.dart';
import '../../core/providers/onboarding_state_provider.dart';
import '../../core/providers/venue_config_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/phone.dart';
import '../../flavors.dart';

/// Step 2 of auth: 6-digit OTP entry.
///
/// On a correct code, the auth-otp Edge Function returns a magic-link
/// `token_hash` which we redeem with `auth.verifyOTP(type: magiclink)` to
/// get a real Supabase session (with refresh tokens).
class OtpVerifyScreen extends ConsumerStatefulWidget {
  const OtpVerifyScreen({super.key});

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  static const int _otpLength = 6;
  static const int _resendCooldownSeconds = 30;
  static const int _maxResends = 5;

  final _controllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final _focusNodes = List.generate(_otpLength, (_) => FocusNode());

  String? _phone;
  int _resendSeconds = _resendCooldownSeconds;
  int _resendAttempts = 0;
  Timer? _timer;
  bool _isVerifying = false;
  String? _errorText;
  int? _attemptsRemaining;

  @override
  void initState() {
    super.initState();
    _loadPhone();
    _startResendTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _phone = prefs.getString('pending_otp_phone'));
  }

  void _startResendTimer() {
    _resendSeconds = _resendCooldownSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendSeconds > 0) {
        setState(() => _resendSeconds--);
      } else {
        t.cancel();
      }
    });
  }

  void _clearBoxes() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
  }

  Future<void> _verify() async {
    final code = _controllers.map((c) => c.text).join();
    if (code.length != _otpLength || _phone == null) return;

    setState(() {
      _isVerifying = true;
      _errorText = null;
    });

    try {
      // 1) Ask the Edge Function to verify and return a magic-link token_hash.
      final res = await Supabase.instance.client.functions.invoke(
        'auth-otp',
        body: {'action': 'verify', 'phone': _phone, 'code': code},
      );
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['ok'] != true) {
        setState(() {
          _errorText = _mapVerifyError(data['error'] as String?);
          _attemptsRemaining = data['attempts_remaining'] as int?;
          _isVerifying = false;
        });
        _clearBoxes();
        return;
      }

      // 2) Redeem the token_hash for a real session.
      final tokenHash = data['token_hash'] as String;
      await Supabase.instance.client.auth.verifyOTP(
        tokenHash: tokenHash,
        type: OtpType.magiclink,
      );

      // 3) Decide where to land. Returning user with full family + child →
      // home; otherwise pick up the onboarding flow. Force a refresh so the
      // family_id has propagated.
      ref.invalidate(currentFamilyProvider);
      final family = await ref.read(currentFamilyProvider.future);

      if (!mounted) return;

      if (family == null) {
        // Brand-new user. Onboarding starts at family-name.
        await ref
            .read(onboardingStepProvider.notifier)
            .setStep(OnboardingStep.familyName);
        if (!mounted) return;
        context.go('/onboarding/family-name');
        return;
      }

      // Existing family. If they have a child OR are cafe-only, they're done.
      if (family['has_children'] == true || family['is_cafe_only'] == true) {
        await ref
            .read(onboardingStepProvider.notifier)
            .setStep(OnboardingStep.complete);
        // Touch last_active_at — best effort.
        unawaited(Supabase.instance.client.rpc('family_touch_active'));
        if (!mounted) return;
        context.go('/home');
        return;
      }

      // Family row exists but no child yet — drop them at add-child.
      await ref
          .read(onboardingStepProvider.notifier)
          .setStep(OnboardingStep.addChild);
      if (!mounted) return;
      context.go('/onboarding/add-child');
    } on AuthException catch (e) {
      setState(() {
        _errorText = "Couldn't verify. Please try again. (${e.message})";
        _isVerifying = false;
      });
      _clearBoxes();
    } on FunctionException catch (_) {
      setState(() {
        _errorText = "Couldn't reach the server. Please try again.";
        _isVerifying = false;
      });
    } catch (_) {
      setState(() {
        _errorText = "Couldn't verify. Please try again.";
        _isVerifying = false;
      });
    }
  }

  String _mapVerifyError(String? code) {
    switch (code) {
      case 'wrong_code':
        return 'Wrong code. Please check and try again.';
      case 'code_expired_or_missing':
        return 'Code expired. Tap resend below.';
      case 'too_many_attempts':
        return 'Too many attempts. Tap resend for a new code.';
      case 'invalid_code_format':
        return "That code doesn't look right.";
      case 'invalid_phone':
        return "Couldn't verify — try going back and re-entering your phone.";
      default:
        return "Couldn't verify. Please try again.";
    }
  }

  Future<void> _resend() async {
    if (_phone == null) return;
    if (_resendSeconds > 0) return;
    if (_resendAttempts >= _maxResends) {
      setState(() =>
          _errorText = 'Too many resends. Please try again in a few hours.');
      return;
    }
    setState(() {
      _resendAttempts++;
      _errorText = null;
      _attemptsRemaining = null;
    });
    try {
      await Supabase.instance.client.functions.invoke(
        'auth-otp',
        body: {'action': 'send', 'phone': _phone},
      );
      _startResendTimer();
      _clearBoxes();
    } catch (_) {
      setState(() => _errorText = "Couldn't resend. Please try again.");
    }
  }

  Future<void> _openWhatsapp() async {
    final venue = ref.read(venueConfigProvider).valueOrNull;
    final supportPhone = venue?['whatsapp_support_phone'] as String?;
    if (supportPhone == null || supportPhone.isEmpty) return;
    final num = supportPhone.replaceAll(RegExp(r'[^\d]'), '');
    await launchUrl(
      Uri.parse('https://wa.me/$num?text=${Uri.encodeComponent('OTP issue')}'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
          tooltip: 'Back',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text('Enter the code', style: AppTextStyles.h1(context)),
              const SizedBox(height: 8),
              Text(
                _phone == null
                    ? 'We sent a 6-digit code to your phone.'
                    : 'We sent a 6-digit code to ${PhoneNormalizer.forDisplay(_phone!)}.',
                style: AppTextStyles.body(context,
                    color: AppColors.lightTextSecondary),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Wrong number?'),
                ),
              ),
              const SizedBox(height: 16),

              _OtpBoxes(
                controllers: _controllers,
                focusNodes: _focusNodes,
                onCompleted: _verify,
                isVerifying: _isVerifying,
              ),

              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _attemptsRemaining != null && _attemptsRemaining! > 0
                        ? '${_errorText!} ($_attemptsRemaining attempt${_attemptsRemaining == 1 ? '' : 's'} left)'
                        : _errorText!,
                    style: AppTextStyles.caption(context,
                        color: AppColors.adminRed),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              Center(
                child: _resendSeconds > 0
                    ? Text(
                        'Resend code in 0:${_resendSeconds.toString().padLeft(2, '0')}',
                        style: AppTextStyles.caption(context,
                            color: AppColors.lightTextSecondary),
                      )
                    : TextButton(
                        onPressed: _resend,
                        child: const Text('Resend code'),
                      ),
              ),

              const SizedBox(height: 24),

              if (F.isMockOtp)
                Center(
                  child: Text(
                    'Dev mode — code is 123456.',
                    style: AppTextStyles.caption(context,
                        color: AppColors.lightTextSecondary),
                  ),
                ),

              const SizedBox(height: 8),

              Center(
                child: TextButton(
                  onPressed: _openWhatsapp,
                  child: const Text('Need help?'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtpBoxes extends StatelessWidget {
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final VoidCallback onCompleted;
  final bool isVerifying;

  const _OtpBoxes({
    required this.controllers,
    required this.focusNodes,
    required this.onCompleted,
    required this.isVerifying,
  });

  void _onChanged(int index, String value) {
    // Paste handling: a six-char paste lands in box 0; spread it.
    if (index == 0 && value.length == 6) {
      for (var i = 0; i < 6; i++) {
        controllers[i].text = value[i];
      }
      focusNodes[5].unfocus();
      onCompleted();
      return;
    }
    if (value.length == 1 && index < 5) {
      focusNodes[index + 1].requestFocus();
    }
    if (controllers.every((c) => c.text.length == 1)) {
      onCompleted();
    }
  }

  KeyEventResult _onKey(int index, FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        controllers[index].text.isEmpty &&
        index > 0) {
      controllers[index - 1].clear();
      focusNodes[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(6, (i) {
          return SizedBox(
            width: 48,
            height: 56,
            child: Focus(
              onKeyEvent: (node, event) => _onKey(i, node, event),
              child: TextField(
                controller: controllers[i],
                focusNode: focusNodes[i],
                enabled: !isVerifying,
                autofocus: i == 0,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: i == 0 ? 6 : 1,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (v) => _onChanged(i, v),
              ),
            ),
          );
        }),
      ),
    );
  }
}
