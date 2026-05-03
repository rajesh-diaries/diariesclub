import 'bootstrap.dart';
import 'flavors.dart';

void main() async {
  F = const FlavorConfig(
    flavor: Flavor.prod,
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    razorpayKeyId: String.fromEnvironment('RAZORPAY_KEY_ID'),
    sentryDsn: String.fromEnvironment('SENTRY_DSN'),
    branchKey: String.fromEnvironment('BRANCH_KEY'),
    sentryEnabled: true,
  );
  assertSafeRazorpayKeys(F);
  await bootstrap();
}
