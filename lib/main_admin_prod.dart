import 'package:flutter/widgets.dart';

import 'bootstrap.dart';
import 'flavors.dart';

/// Prod entry point for the admin web flavor.
///
/// Build with:
///   flutter build web --release \
///     -t lib/main_admin_prod.dart \
///     --dart-define-from-file=env/admin_prod.json
///
/// Deploy with:
///   npx wrangler pages deploy build/web --project-name=diariesclub-admin
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  F = const FlavorConfig(
    flavor: Flavor.adminProd,
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    // Admin web doesn't take payments → no Razorpay key needed.
    razorpayKeyId: 'rzp_test_placeholder',
    razorpayMode: RazorpayMode.mock,
    otpMode: OtpMode.mock,
  );
  assertSafeRazorpayKeys(F);
  await bootstrap();
}
