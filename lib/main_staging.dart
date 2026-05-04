import 'bootstrap.dart';
import 'flavors.dart';

void main() async {
  F = FlavorConfig(
    flavor: Flavor.staging,
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
    sentryEnabled: true,
    otpMode: otpModeFrom(
      const String.fromEnvironment('OTP_MODE', defaultValue: 'real'),
    ),
  );
  assertSafeRazorpayKeys(F);
  await bootstrap();
}
