import 'bootstrap.dart';
import 'flavors.dart';

void main() async {
  // Dev defaults to MOCK for both Razorpay and OTP so the founder can
  // test the full app flow without needing Razorpay test keys or
  // MSG91 SMS credentials set up. Mock behavior:
  //   - Razorpay sheet is skipped; Edge Function fakes the order +
  //     credits the wallet directly.
  //   - OTP login accepts only "123456"; no SMS is sent.
  //
  // PRE-LAUNCH (when ready to flip):
  //   1. Grab a real Razorpay test key from the dashboard
  //   2. Set MSG91_AUTH_KEY / MSG91_TEMPLATE_ID / MSG91_SENDER_ID
  //      secrets on the auth-otp Edge Function in Supabase
  //   3. Switch the defaults below from 'mock' → 'test' / 'real'
  //   4. Pass RAZORPAY_KEY_ID via --dart-define in dev builds
  F = FlavorConfig(
    flavor: Flavor.dev,
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
    sentryEnabled: false,
    otpMode: otpModeFrom(
      const String.fromEnvironment('OTP_MODE', defaultValue: 'mock'),
    ),
  );
  assertSafeRazorpayKeys(F);
  await bootstrap();
}
