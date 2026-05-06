import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'bootstrap.dart';
import 'flavors.dart';

/// Dev entry point for the staff flavor.
///
/// Run with:
///   flutter run --flavor staffDev -t lib/main_staff_dev.dart \
///     --dart-define-from-file=env/staff_dev.json
///
/// staffProd / staffStaging entries land later when we wire CI.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Declare all four orientations explicitly. Functionally equivalent to
  // omitting the call, but on some Android 15 ROMs the absence of any
  // preference triggers an inbound viewport-metrics thrash from the OS
  // post-launch (BUG-022 candidate). Explicit declaration gives the
  // engine a definitive answer and lets it stop renegotiating insets.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  F = FlavorConfig(
    flavor: Flavor.staffDev,
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    razorpayKeyId: const String.fromEnvironment(
      'RAZORPAY_KEY_ID',
      defaultValue: 'rzp_test_placeholder',
    ),
    razorpayMode: razorpayModeFrom(
      const String.fromEnvironment('RAZORPAY_MODE', defaultValue: 'mock'),
    ),
    sentryDsn: const String.fromEnvironment('SENTRY_DSN'),
    // Branch isn't used by the staff app (no deferred deep links) — pass
    // through so bootstrap() can no-op cleanly.
    branchKey: const String.fromEnvironment('BRANCH_KEY'),
    sentryEnabled: false,
    otpMode: otpModeFrom(
      const String.fromEnvironment('OTP_MODE', defaultValue: 'mock'),
    ),
  );
  assertSafeRazorpayKeys(F);
  await bootstrap();
}
