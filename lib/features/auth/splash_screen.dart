import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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
  // Asset paths reserved for when art lands; not loaded yet.
  // ignore: unused_field
  static const _logoAsset = 'assets/images/logo_white.png';
  // ignore: unused_field
  static const _lottieAsset = 'assets/lottie/splash_pulse.json';

  static const _minSplashDuration = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // Let the version check resolve. The router redirect will already kick
    // us to /update-required if forceUpdate; we still wait so the splash
    // doesn't flash before the redirect lands.
    final version = await ref.read(appVersionStatusProvider.future);
    if (!mounted) return;
    if (version.status == AppVersionStatus.forceUpdate) {
      // Router will handle this; just stop here.
      return;
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
      // Auth user exists but family_create hasn't run — fresh OTP, resume
      // at the saved step (welcome → family-name → add-child → ...).
      final step = await ref.read(onboardingStepProvider.future);
      if (!mounted) return;
      context.go(step.route);
      return;
    }

    // Family row exists. Onboarding may still be partial: cafe-only is
    // complete; otherwise has_children=false means the user added a name
    // but not a child yet; otherwise → home.
    if (family['is_cafe_only'] == true || family['has_children'] == true) {
      context.go('/home');
      return;
    }

    // Family but no child and not cafe-only — resume mid-onboarding.
    final step = await ref.read(onboardingStepProvider.future);
    if (!mounted) return;
    if (step == OnboardingStep.familyName ||
        step == OnboardingStep.complete) {
      // Defensive: if family row exists but onboarding step is still 0,
      // the user has named the family but stopped — push them to add-child.
      context.go(OnboardingStep.addChild.route);
    } else {
      context.go(step.route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Diaries Club',
                style: GoogleFonts.nunito(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: AppColors.gold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppColors.gold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
