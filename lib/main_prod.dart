import 'bootstrap.dart';
import 'flavors.dart';

void main() async {
  F = FlavorConfig(
    flavor: Flavor.prod,
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    razorpayKeyId: const String.fromEnvironment('RAZORPAY_KEY_ID'),
    razorpayMode: razorpayModeFrom(
      const String.fromEnvironment('RAZORPAY_MODE', defaultValue: 'live'),
    ),
    otpMode: otpModeFrom(
      const String.fromEnvironment('OTP_MODE', defaultValue: 'real'),
    ),
  );
  assertSafeRazorpayKeys(F);
  await bootstrap();
}
