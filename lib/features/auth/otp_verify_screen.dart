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

  // Single source of truth for the OTP. The visual boxes are a pure
  // decoration of `_controller.text` — one TextField means one keyboard,
  // no flicker as digits move from box to box, and iOS Messages
  // autofill targets a single field.
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

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
    _controller.dispose();
    _focusNode.dispose();
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
    _controller.clear();
    _focusNode.requestFocus();
  }

  Future<void> _verify() async {
    // BUG-007 guard: paste handler + per-box completion can both call us in
    // the same frame. Without this gate, two HTTP submits race.
    if (_isVerifying) return;

    final code = _controller.text;
    if (code.length != _otpLength || _phone == null) return;

    setState(() {
      _isVerifying = true;
      _errorText = null;
    });

    try {
      // 1) Ask the Edge Function to verify and return a magic-link token_hash
      //    plus (BUG-043 fix) the families row. Routing off the response
      //    avoids the post-verifyOTP auth-state-propagation race that
      //    previously sent existing users to onboarding on web.
      //    15s timeout: better to surface "couldn't reach server" with a
      //    retry than spin forever if the Edge Function is cold-starting
      //    or the Supabase gateway is having a moment.
      final res = await Supabase.instance.client.functions.invoke(
        'auth-otp',
        body: {'action': 'verify', 'phone': _phone, 'code': code},
      ).timeout(const Duration(seconds: 15));
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

      // 3) Route off the family payload returned by the Edge Function. No
      //    DB read here — the new JWT may not have propagated to the
      //    PostgREST client yet on web, and a families read under the
      //    pre-signin context would get RLS-blocked → null → wrong route.
      final family = (data['family'] as Map?)?.cast<String, dynamic>();

      // Prime the local cache so other screens see the family without an
      // extra round-trip. Safe even if family is null (caller will fetch).
      ref.invalidate(currentFamilyProvider);
      // The welcome-manifesto flag is keyed by auth.uid — the uid just
      // changed, so re-evaluate so splash can see whether THIS account
      // has seen the manifesto yet.
      ref.invalidate(hasSeenWelcomeManifestoProvider);

      if (!mounted) return;

      // Brand-new families (family == null) → land on the welcome
      // manifesto, full stop. Existing families with children → home.
      // Half-onboarded families (family row but no kid) → resume at
      // add-child. We route DIRECTLY here instead of bouncing through
      // splash so there's no chance of timing weirdness between the
      // setStep write and the splash's read.
      if (family == null) {
        // Skip the welcome manifesto on first signup — it was too much
        // before they'd entered anything. The manifesto still lives at
        // Adventure → About for parents who want to read it later.
        await ref
            .read(onboardingStepProvider.notifier)
            .setStep(OnboardingStep.familyName);
        if (!mounted) return;
        context.go('/onboarding/family-name');
      } else if (family['has_children'] == true ||
          family['is_cafe_only'] == true) {
        await ref
            .read(onboardingStepProvider.notifier)
            .setStep(OnboardingStep.complete);
        unawaited(Supabase.instance.client.rpc('family_touch_active'));
        if (!mounted) return;
        context.go('/home');
      } else {
        await ref
            .read(onboardingStepProvider.notifier)
            .setStep(OnboardingStep.addChild);
        if (!mounted) return;
        context.go('/onboarding/add-child');
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = "Couldn't verify. Please try again. (${e.message})";
        _isVerifying = false;
      });
      _clearBoxes();
    } on FunctionException catch (e) {
      // The Edge Function returns 4xx with a structured body for expected
      // failures (code expired, wrong code, too many attempts). Parse the
      // body so the user sees the right message instead of "Couldn't reach
      // the server" — that catch-all was misleading for, e.g., re-using a
      // burned OTP after going back to the OTP screen (BUG-043 collateral).
      final body = (e.details as Map?)?.cast<String, dynamic>();
      final errCode = body?['error'] as String?;
      if (!mounted) return;
      setState(() {
        _errorText = errCode != null
            ? _mapVerifyError(errCode)
            : "Couldn't reach the server. Please try again.";
        _attemptsRemaining = body?['attempts_remaining'] as int?;
        _isVerifying = false;
      });
      _clearBoxes();
    } catch (_) {
      if (!mounted) return;
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
      ).timeout(const Duration(seconds: 10));
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
                controller: _controller,
                focusNode: _focusNode,
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

/// Single TextField rendered invisibly behind six visible boxes.
///
/// All keyboard input — typing, deleting, iOS Messages autofill, paste —
/// lands on the one TextField. The boxes are pure decoration that
/// display the controller's characters with a "next box" indicator.
/// Single focus means iOS doesn't dismiss/re-present the keyboard
/// between digits → no flicker.
class _OtpBoxes extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCompleted;
  final bool isVerifying;

  const _OtpBoxes({
    required this.controller,
    required this.focusNode,
    required this.onCompleted,
    required this.isVerifying,
  });

  @override
  State<_OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<_OtpBoxes> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
    if (widget.controller.text.length == 6 && !widget.isVerifying) {
      widget.focusNode.unfocus();
      widget.onCompleted();
    }
  }

  void _onFocusChanged() => setState(() {});

  void _requestFocus() {
    if (widget.isVerifying) return;
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final hasFocus = widget.focusNode.hasFocus;

    return AutofillGroup(
      child: GestureDetector(
        onTap: _requestFocus,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // Invisible-but-functional TextField. SizedBox.shrink keeps it
            // out of the layout flow but still lets the framework attach
            // the platform keyboard.
            SizedBox(
              height: 56,
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  enabled: !widget.isVerifying,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(counterText: ''),
                ),
              ),
            ),
            // Visible cells — pure presentation.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(6, (i) {
                final hasChar = i < text.length;
                final isNext = i == text.length && hasFocus;
                return _OtpCell(
                  character: hasChar ? text[i] : null,
                  active: isNext,
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _OtpCell extends StatelessWidget {
  final String? character;
  final bool active;
  const _OtpCell({required this.character, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(
          color: active ? AppColors.navy : AppColors.lightBorder,
          width: active ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: character != null
          ? Text(
              character!,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            )
          : active
              ? const _BlinkingCursor()
              : null,
    );
  }
}

/// Lightweight blinking caret for the "next box". A 600ms toggle keeps it
/// feeling alive without burning frames.
class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor> {
  Timer? _timer;
  bool _on = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (mounted) setState(() => _on = !_on);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _on ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 150),
      child: Container(
        width: 2,
        height: 28,
        color: AppColors.navy,
      ),
    );
  }
}
