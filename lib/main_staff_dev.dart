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

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  // Fail fast with a useful message instead of letting Supabase boot with
  // an empty URL — the symptom otherwise is "invalid arguments: no host
  // specified in URL /auth/v1/token?grant_type=password" on first login,
  // which doesn't point at the real cause (missing --dart-define-from-file).
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw StateError(
      'Staff app launched without env/staff_dev.json. '
      'Run via ./run_staff_dev_android.sh or pass '
      '--dart-define-from-file=env/staff_dev.json to flutter run.',
    );
  }

  F = FlavorConfig(
    flavor: Flavor.staffDev,
    supabaseUrl: supabaseUrl,
    supabaseAnonKey: supabaseAnonKey,
    razorpayKeyId: const String.fromEnvironment(
      'RAZORPAY_KEY_ID',
      defaultValue: 'rzp_test_placeholder',
    ),
    razorpayMode: razorpayModeFrom(
      const String.fromEnvironment('RAZORPAY_MODE', defaultValue: 'mock'),
    ),
    otpMode: otpModeFrom(
      const String.fromEnvironment('OTP_MODE', defaultValue: 'mock'),
    ),
  );
  assertSafeRazorpayKeys(F);
  await bootstrap();
}
