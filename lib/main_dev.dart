import 'bootstrap.dart';
import 'flavors.dart';

void main() async {
  F = const FlavorConfig(
    flavor: Flavor.dev,
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    razorpayKeyId: String.fromEnvironment(
      'RAZORPAY_KEY_ID',
      defaultValue: 'rzp_test_placeholder',
    ),
    sentryDsn: String.fromEnvironment('SENTRY_DSN'),
    branchKey: String.fromEnvironment('BRANCH_KEY'),
    sentryEnabled: false,
  );
  assertSafeRazorpayKeys(F);
  await bootstrap();
}
