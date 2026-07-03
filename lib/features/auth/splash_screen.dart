import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/app_version_provider.dart';
import '../../core/providers/current_family_provider.dart';
import '../../core/providers/onboarding_state_provider.dart';
import '../../core/theme/app_colors.dart';

/// Always the first screen on app launch.
///
/// Responsibilities:
///   1. Wait for the version check (the router will already redirect to
///      /update-required if force-update is required — we just need to
///      let it settle before navigating off splash).
///   2. Read auth state.
///   3. If signed in: read families row → route to /home or resume the
///      saved onboarding step.
///   4. If signed out: route to /auth/phone.
///
/// Asset paths are defined for `assets/images/logo_white.png` and a Lottie
/// pulse animation; the Session-4 stub renders a Nunito wordmark on navy
/// while those assets are still pending art.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  // Matches the asset wired into flutter_native_splash so the native and
  // Flutter-side splash look continuous — no jarring colour or logo flip
  // when control passes from iOS/Android to the Dart engine.
  static const _logoAsset = 'assets/splash/play_diaries_splash.png';

  static const _minSplashDuration = Duration(milliseconds: 800);

  bool _errored = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      // Let the version check resolve. The router redirect will already kick
      // us to /update-required if forceUpdate; we still wait so the splash
      // doesn't flash before the redirect lands.
      final version = await ref.read(appVersionStatusProvider.future);
      if (!mounted) return;
      if (version.status == AppVersionStatus.forceUpdate) {
        return; // Router will handle this; just stop here.
      }

      // Splash polish: minimum dwell so the user can see the wordmark.
      await Future<void>.delayed(_minSplashDuration);
      if (!mounted) return;

      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        context.go('/auth/phone');
        return;
      }

      // Signed in. Decide route based on family row + saved onboarding step.
      final family = await ref.read(currentFamilyProvider.future);
      if (!mounted) return;

      if (family == null) {
        // Auth user exists but family_create hasn't run — resume saved step.
        final step = await ref.read(onboardingStepProvider.future);
        if (!mounted) return;
        context.go(step.route);
        return;
      }

      // Family row exists; onboarding may still be partial.
      if (family['is_cafe_only'] == true || family['has_children'] == true) {
        context.go('/home');
        return;
      }

      final step = await ref.read(onboardingStepProvider.future);
      if (!mounted) return;
      if (step == OnboardingStep.familyName ||
          step == OnboardingStep.complete) {
        context.go(OnboardingStep.addChild.route);
      } else {
        context.go(step.route);
      }
    } catch (_) {
      // A slow or failed cold-start read (e.g. the family fetch timing out)
      // must not leave the splash spinning forever — show a retry instead.
      if (mounted) setState(() => _errored = true);
    }
  }

  void _retry() {
    setState(() => _errored = false);
    ref.invalidate(appVersionStatusProvider);
    ref.invalidate(currentFamilyProvider);
    ref.invalidate(onboardingStepProvider);
    _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                _logoAsset,
                width: 240,
                height: 240,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 32),
              if (_errored) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    "Couldn't connect. Please check your internet and try again.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.navy.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _retry,
                  child: const Text('Retry'),
                ),
              ] else
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      AppColors.navy.withValues(alpha: 0.55),
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
