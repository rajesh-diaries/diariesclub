import 'bootstrap.dart';
import 'flavors.dart';

void main() async {
  // Dev now defaults to REAL Razorpay test mode + real MSG91 SMS so
  // E2E testing actually exercises the integrations. To force the old
  // fully-fake behavior, build with:
  //   --dart-define=RAZORPAY_MODE=mock --dart-define=OTP_MODE=mock
  //
  // RAZORPAY_MODE=test still needs a real rzp_test_XXXXXXX key passed
  // via --dart-define=RAZORPAY_KEY_ID=... — the placeholder default
  // makes assertSafeRazorpayKeys pass but the Razorpay SDK call will
  // throw "invalid key" at runtime if you don't override it.
  //
  // OTP_MODE=real requires MSG91_AUTH_KEY / MSG91_TEMPLATE_ID /
  // MSG91_SENDER_ID secrets configured on the auth-otp Edge Function
  // in Supabase. Without them, OTP send fails with "Couldn't reach
  // the server".
  F = FlavorConfig(
    flavor: Flavor.dev,
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    razorpayKeyId: const String.fromEnvironment(
      'RAZORPAY_KEY_ID',
      defaultValue: 'rzp_test_placeholder',
    ),
    razorpayMode: razorpayModeFrom(
      const String.fromEnvironment('RAZORPAY_MODE', defaultValue: 'test'),
    ),
    sentryDsn: const String.fromEnvironment('SENTRY_DSN'),
    branchKey: const String.fromEnvironment('BRANCH_KEY'),
    sentryEnabled: false,
    otpMode: otpModeFrom(
      const String.fromEnvironment('OTP_MODE', defaultValue: 'real'),
    ),
  );
  assertSafeRazorpayKeys(F);
  await bootstrap();
}
