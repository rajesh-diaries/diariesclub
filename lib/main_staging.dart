import 'bootstrap.dart';
import 'flavors.dart';

void main() async {
  F = const FlavorConfig(
    flavor: Flavor.staging,
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    razorpayKeyId: String.fromEnvironment(
      'RAZORPAY_KEY_ID',
      defaultValue: 'rzp_test_placeholder',
    ),
    sentryDsn: String.fromEnvironment('SENTRY_DSN'),
    branchKey: String.fromEnvironment('BRANCH_KEY'),
    sentryEnabled: true,
  );
  assertSafeRazorpayKeys(F);
  await bootstrap();
}
