enum Flavor {
  dev,
  staging,
  prod,
  // Staff app flavors (Session 10). Same Flutter codebase, separate build
  // target → bundle id com.diariesclub.staff(.dev). Staff flavors render
  // StaffApp instead of DiariesClubApp; see lib/app.dart.
  staffDev,
  staffProd,
  // Admin web flavors (Session 11). Web-first; bundle id
  // com.diariesclub.admin reserved for a future Electron wrap. Admin
  // flavors render AdminApp.
  adminDev,
  adminProd,
}

/// OTP delivery mode (Session 4).
/// * `mock` — auth-otp Edge Function accepts only "123456"; no SMS sent.
/// * `real` — Edge Function calls MSG91 (Supabase secrets wired in Session 12).
enum OtpMode { mock, real }

/// Razorpay delivery mode (Session 5).
/// * `mock` — razorpay-topup Edge Function fakes the order + skips the
///            Razorpay sheet entirely. Used for emulator dev when the
///            tester doesn't have Razorpay test keys configured yet.
/// * `test` — real Razorpay test mode with rzp_test_* keys (use card
///            4111 1111 1111 1111).
/// * `live` — production. Only allowed with rzp_live_* keys.
enum RazorpayMode { mock, test, live }

class FlavorConfig {
  final Flavor flavor;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String razorpayKeyId; // TEST keys for dev/staging; LIVE only for prod
  final RazorpayMode razorpayMode;
  final String sentryDsn;
  final bool sentryEnabled;
  final OtpMode otpMode;

  const FlavorConfig({
    required this.flavor,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.razorpayKeyId,
    required this.razorpayMode,
    required this.sentryDsn,
    required this.sentryEnabled,
    required this.otpMode,
  });

  bool get isProd =>
      flavor == Flavor.prod ||
      flavor == Flavor.staffProd ||
      flavor == Flavor.adminProd;
  bool get isDev =>
      flavor == Flavor.dev ||
      flavor == Flavor.staffDev ||
      flavor == Flavor.adminDev;
  bool get isStaff =>
      flavor == Flavor.staffDev || flavor == Flavor.staffProd;
  bool get isStaffDev => flavor == Flavor.staffDev;
  bool get isStaffProd => flavor == Flavor.staffProd;
  bool get isAdmin =>
      flavor == Flavor.adminDev || flavor == Flavor.adminProd;
  bool get isAdminDev => flavor == Flavor.adminDev;
  bool get isAdminProd => flavor == Flavor.adminProd;
  bool get isMockOtp => otpMode == OtpMode.mock;
  bool get isMockRazorpay => razorpayMode == RazorpayMode.mock;
  String get name => flavor.name;
}

/// Resolves an OTP_MODE dart-define string to the enum.
/// Defaults to `real` — a misconfigured build never accidentally accepts the
/// mock code in staging/prod. Mock mode must be opted into explicitly.
OtpMode otpModeFrom(String raw) =>
    raw.toLowerCase() == 'mock' ? OtpMode.mock : OtpMode.real;

/// Resolves a RAZORPAY_MODE dart-define string to the enum.
/// Defaults to `live` — same safety reasoning as `otpModeFrom`. A missing
/// or unknown env value MUST NOT silently fall back to mock in production.
RazorpayMode razorpayModeFrom(String raw) {
  switch (raw.toLowerCase()) {
    case 'mock':
      return RazorpayMode.mock;
    case 'test':
      return RazorpayMode.test;
    default:
      return RazorpayMode.live;
  }
}

late FlavorConfig F;

/// Razorpay key guard.
///
/// Originally asserted that non-prod flavors used rzp_test_ keys to keep
/// developers from accidentally charging real cards. Relaxed 2026-05-19:
/// founder explicitly runs dev against the LIVE Razorpay account with ₹1
/// recharges as his standard pre-launch test (the Supabase Edge Function
/// secrets are also pinned to live). Test-mode keys never matched the
/// server's live order_id and produced INVALID_OPTIONS / "Uh! oh!" on the
/// checkout sheet.
///
/// Guard kept only to catch a hard misconfiguration: an empty key string.
void assertSafeRazorpayKeys(FlavorConfig f) {
  assert(
    f.razorpayKeyId.startsWith('rzp_'),
    'razorpayKeyId must be a Razorpay key (rzp_test_* or rzp_live_*). Got: ${f.razorpayKeyId}',
  );
}
