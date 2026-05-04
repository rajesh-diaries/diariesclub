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
/// staffProd / staffStaging entries land later when we wire CI; this dev
/// flavor is what the founder uses on the Kondapur tablet emulator today.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock landscape on the tablet — the customer app stays unlocked because
  // it's used on phones in portrait. SystemChrome runs after the binding
  // init so this fires before the first frame.
  await SystemChrome.setPreferredOrientations([
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
