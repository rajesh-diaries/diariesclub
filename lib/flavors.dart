enum Flavor { dev, staging, prod }

class FlavorConfig {
  final Flavor flavor;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String razorpayKeyId; // TEST keys for dev/staging; LIVE only for prod
  final String sentryDsn;
  final String branchKey;
  final bool sentryEnabled;

  const FlavorConfig({
    required this.flavor,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.razorpayKeyId,
    required this.sentryDsn,
    required this.branchKey,
    required this.sentryEnabled,
  });

  bool get isProd => flavor == Flavor.prod;
  bool get isDev => flavor == Flavor.dev;
  String get name => flavor.name;
}

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
