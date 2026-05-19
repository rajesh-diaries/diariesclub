import 'package:flutter/widgets.dart';

import 'bootstrap.dart';
import 'flavors.dart';

/// Dev entry point for the admin web flavor.
///
/// Run with:
///   flutter run -d chrome --web-port=5060 \
///     -t lib/main_admin_dev.dart \
///     --dart-define-from-file=env/admin_dev.json
///
/// Note: don't pass --flavor on web — Flutter web doesn't honour Android/
/// iOS productFlavors. The flavor is set in Dart at runtime via the
/// FlavorConfig below; the customer / staff / admin branch happens in
/// lib/app.dart.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  F = const FlavorConfig(
    flavor: Flavor.adminDev,
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    // Admin web doesn't take payments → no Razorpay key needed.
    razorpayKeyId: 'rzp_test_placeholder',
    razorpayMode: RazorpayMode.mock,
    sentryDsn: String.fromEnvironment('SENTRY_DSN'),
    sentryEnabled: false,
    otpMode: OtpMode.mock,
  );
  assertSafeRazorpayKeys(F);
  await bootstrap();
}
