enum Flavor { dev, staging, prod }

/// OTP delivery mode (Session 4).
/// * `mock` — auth-otp Edge Function accepts only "123456"; no SMS sent.
/// * `real` — Edge Function calls MSG91 (Supabase secrets wired in Session 12).
enum OtpMode { mock, real }

class FlavorConfig {
  final Flavor flavor;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String razorpayKeyId; // TEST keys for dev/staging; LIVE only for prod
  final String sentryDsn;
  final String branchKey;
  final bool sentryEnabled;
  final OtpMode otpMode;

  const FlavorConfig({
    required this.flavor,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.razorpayKeyId,
    required this.sentryDsn,
    required this.branchKey,
    required this.sentryEnabled,
    required this.otpMode,
  });

  bool get isProd => flavor == Flavor.prod;
  bool get isDev => flavor == Flavor.dev;
  bool get isMockOtp => otpMode == OtpMode.mock;
  String get name => flavor.name;
}

/// Resolves an OTP_MODE dart-define string to the enum.
/// Defaults to `real` — a misconfigured build never accidentally accepts the
/// mock code in staging/prod. Mock mode must be opted into explicitly.
OtpMode otpModeFrom(String raw) =>
    raw.toLowerCase() == 'mock' ? OtpMode.mock : OtpMode.real;

late FlavorConfig F;

/// Compile-time guard against shipping live Razorpay keys in non-prod builds.
/// Fires in debug only (assert), so a debug dev build with rzp_live_ keys halts.
void assertSafeRazorpayKeys(FlavorConfig f) {
  if (f.flavor != Flavor.prod) {
    assert(
      f.razorpayKeyId.startsWith('rzp_test_'),
      'Non-prod flavor MUST use rzp_test_ keys. Got: ${f.razorpayKeyId}',
    );
  }
}
