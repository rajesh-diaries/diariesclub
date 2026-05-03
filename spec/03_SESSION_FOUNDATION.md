# Session 3 — Flutter Foundation

> Paste `00_CONTEXT.md` first, then this file. Fresh Claude Code conversation.
> **Prerequisite:** Sessions 1 + 2 (database + RPCs) live on a Supabase project.

---

## Session Header

```
I am building Diaries Club. Database and RPCs from Sessions 1+2 are live on Supabase.
This session: build the Flutter project foundation — no feature screens yet.

Estimated time: 2–3 hours
What to build:
  - Complete project structure (folders + pubspec.yaml)
  - Flavor configuration (dev/staging/prod) with Razorpay test/live separation
  - Theme system: colours, typography, light + dark, Dynamic Type support
  - Router with all routes registered (placeholder screens for unbuilt features)
  - All core providers (auth, current family, server clock, wallet stream, etc.)
  - Bottom navigation shell with 4 tabs: Home | Club | Adventure | Profile
  - Supabase client init + Realtime + RLS context
  - Server-clock-offset session timer widget
  - Force-update screen + version check on app start
  - Friendly error screen with copyable error code
  - Phone normaliser utility (E.164)
  - Currency formatter utility (Indian comma format via intl)
  - IST date utilities (week math, etc.)
  - Photo compression service (1080×1080, ~500KB)
  - Branch.io SDK init (deferred deep links)
  - Sentry init with PII stripping

What NOT to build: any feature screens (auth, home, etc. — later sessions).

Output expected:
  - Buildable Flutter project that launches to a placeholder Home tab
  - Tapping bottom nav switches tabs
  - Theme toggle works
  - Logs Sentry test event on debug startup
  - Version check screen blocks app if app_version < min_supported (test by manually setting min_supported_version high)

Acceptance:
  - flutter run on iOS sim and Android emulator both launch
  - Hot reload works
  - flutter analyze returns zero issues
```

---

## 1. `pubspec.yaml`

```yaml
name: diaries_club
description: "Diaries Club — Premium kids play area app"
publish_to: none
version: 1.0.0+1

environment:
  sdk: '>=3.2.0 <4.0.0'
  flutter: '>=3.16.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter

  # Backend
  supabase_flutter: ^2.5.0

  # State management
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5

  # Routing
  go_router: ^14.0.0

  # Payments
  razorpay_flutter: ^1.3.6

  # Animations
  rive: ^0.13.0
  lottie: ^3.1.0

  # Fonts and icons
  google_fonts: ^6.2.1
  phosphor_flutter: ^2.1.0

  # Utils
  intl: ^0.19.0
  uuid: ^4.4.0
  shared_preferences: ^2.2.2
  flutter_secure_storage: ^9.2.2
  cached_network_image: ^3.3.1
  qr_flutter: ^4.1.0
  mobile_scanner: ^5.1.1
  url_launcher: ^6.2.5
  share_plus: ^9.0.0
  package_info_plus: ^8.0.0
  device_info_plus: ^10.1.0
  connectivity_plus: ^6.0.0
  wakelock_plus: ^1.2.5

  # Photo handling
  image_picker: ^1.1.0
  image: ^4.1.7              # for compression

  # Notifications
  firebase_core: ^3.1.1
  firebase_messaging: ^15.1.1
  flutter_local_notifications: ^17.1.2

  # Crash reporting
  sentry_flutter: ^8.5.0

  # Deep links — IMPORTANT: NOT firebase_dynamic_links
  flutter_branch_sdk: ^8.0.0

  # Misc
  collection: ^1.18.0
  freezed_annotation: ^2.4.1
  json_annotation: ^4.9.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  build_runner: ^2.4.10
  freezed: ^2.5.0
  json_serializable: ^6.8.0
  riverpod_generator: ^2.4.0

flutter:
  uses-material-design: true
  generate: true
  assets:
    - assets/rive/
    - assets/lottie/
    - assets/images/
    - assets/hero/
```

---

## 2. Folder Structure (create with placeholder files)

See `00_CONTEXT.md §1.5` for the full tree. Every directory should at minimum have a `_placeholder.dart` so the structure is committed.

---

## 3. `lib/flavors.dart` — environment separation

```dart
enum Flavor { dev, staging, prod }

class FlavorConfig {
  final Flavor flavor;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String razorpayKeyId;     // TEST keys for dev/staging; LIVE only for prod
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
  String get name => flavor.name;
}

late FlavorConfig F;

// Compile-time guard against shipping live keys in non-prod
void assertSafeRazorpayKeys(FlavorConfig f) {
  if (f.flavor != Flavor.prod) {
    assert(
      f.razorpayKeyId.startsWith('rzp_test_'),
      'Non-prod flavor MUST use rzp_test_ keys. Got: ${f.razorpayKeyId}',
    );
  }
}
```

Three entry points: `lib/main_dev.dart`, `lib/main_staging.dart`, `lib/main_prod.dart`. Each sets `F` and calls `bootstrap()`.

---

## 4. `lib/main_dev.dart` example

```dart
import 'package:flutter/material.dart';
import 'app.dart';
import 'flavors.dart';
import 'bootstrap.dart';

void main() async {
  F = const FlavorConfig(
    flavor: Flavor.dev,
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    razorpayKeyId: String.fromEnvironment('RAZORPAY_KEY_ID', defaultValue: 'rzp_test_xxx'),
    sentryDsn: String.fromEnvironment('SENTRY_DSN'),
    branchKey: String.fromEnvironment('BRANCH_KEY'),
    sentryEnabled: false,
  );
  assertSafeRazorpayKeys(F);
  await bootstrap();
}
```

`prod` build is invoked with `--dart-define-from-file=env/prod.json` containing live keys.

---

## 5. `lib/bootstrap.dart`

```dart
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sentry first so it captures init errors
  if (F.sentryEnabled) {
    await SentryFlutter.init((options) {
      options.dsn = F.sentryDsn;
      options.environment = F.name;
      options.beforeSend = (event, hint) {
        // PII strip: remove names, phones, child names from anywhere we control
        return _stripPii(event);
      };
    });
  }

  // Supabase
  await Supabase.initialize(
    url: F.supabaseUrl,
    anonKey: F.supabaseAnonKey,
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
  );

  // Firebase
  await Firebase.initializeApp();

  // Branch.io
  await FlutterBranchSdk.init(enableLogging: !F.isProd);

  runApp(const ProviderScope(child: DiariesClubApp()));
}

SentryEvent? _stripPii(SentryEvent event, [Hint? hint]) {
  // Strip user context's name/phone if present
  if (event.user != null) {
    event = event.copyWith(
      user: event.user!.copyWith(
        username: null, email: null, name: null,
        // Keep id (anonymised UUID)
      ),
    );
  }
  // Scrub message text for digit sequences that look like phones
  // ... (full implementation)
  return event;
}
```

---

## 6. `lib/core/theme/app_colors.dart`

```dart
import 'package:flutter/material.dart';

class AppColors {
  // Brand
  static const navy = Color(0xFF1E3A7B);
  static const gold = Color(0xFFF5C442);

  // Neutral / surfaces — light theme
  static const lightBackground = Color(0xFFF7FBFF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightTextPrimary = Color(0xFF1A1A2E);
  static const lightTextSecondary = Color(0xFF6B7280);
  static const lightBorder = Color(0xFFE2EBF5);

  // Neutral / surfaces — dark theme
  static const darkBackground = Color(0xFF0F1626);
  static const darkSurface = Color(0xFF1A2238);
  static const darkTextPrimary = Color(0xFFE8EEF7);
  static const darkTextSecondary = Color(0xFFA0AAC0);
  static const darkBorder = Color(0xFF2A334A);

  // Semantic
  static const activeGreen = Color(0xFF5BAD4E);
  static const warningYellow = Color(0xFFF5C442);
  static const xpPurple = Color(0xFF9B6BC8);

  // Hero traits
  static const rafiCoral = Color(0xFFE8524A);   // Brave
  static const ellieBlue = Color(0xFF5BC8E8);   // Kind
  static const gerryAmber = Color(0xFFF0A830);  // Curious
  static const zenaGreen = Color(0xFF7BC74D);   // Creative

  // Sub-brands
  static const coffeeBrown = Color(0xFFD4A473);
  static const fitGreen = Color(0xFF0D4A2E);

  // Session card states
  static const sessionGreenBorder = Color(0xFF5BAD4E);
  static const sessionYellowBorder = Color(0xFFF5C442);
  static const sessionYellowBg = Color(0xFFFFFBEE);

  // Admin only — never use in customer app
  static const adminRed = Color(0xFFE8524A);
}
```

---

## 7. `lib/core/theme/app_text_styles.dart` — Dynamic Type aware

```dart
class AppTextStyles {
  // All sizes are FONTSIZE units that respect MediaQuery.textScaler.
  // Do NOT hardcode pixel dimensions in screens; use these helpers.

  static TextStyle display(BuildContext c, {Color? color}) => GoogleFonts.nunito(
    fontSize: 40, fontWeight: FontWeight.w900,
    color: color ?? Theme.of(c).colorScheme.onSurface,
  );

  static TextStyle h1(BuildContext c, {Color? color}) => GoogleFonts.nunito(
    fontSize: 32, fontWeight: FontWeight.w800,
    color: color ?? Theme.of(c).colorScheme.onSurface,
  );

  static TextStyle h2(BuildContext c, {Color? color}) => GoogleFonts.nunito(
    fontSize: 26, fontWeight: FontWeight.w700,
    color: color ?? Theme.of(c).colorScheme.onSurface,
  );

  static TextStyle h3(BuildContext c, {Color? color}) => GoogleFonts.nunito(
    fontSize: 22, fontWeight: FontWeight.w600,
    color: color ?? Theme.of(c).colorScheme.onSurface,
  );

  static TextStyle bodyLarge(BuildContext c, {Color? color}) => GoogleFonts.nunito(
    fontSize: 18, fontWeight: FontWeight.w600,
    color: color ?? Theme.of(c).colorScheme.onSurface,
  );

  static TextStyle body(BuildContext c, {Color? color}) => GoogleFonts.nunito(
    fontSize: 16, fontWeight: FontWeight.w400,
    color: color ?? Theme.of(c).colorScheme.onSurface,
  );

  static TextStyle caption(BuildContext c, {Color? color}) => GoogleFonts.nunito(
    fontSize: 13, fontWeight: FontWeight.w600,
    color: color ?? Theme.of(c).colorScheme.onSurfaceVariant,
  );

  // Session timer — dominant element. NOTE: this respects textScaler too;
  // accessibility users with large fonts will see an even bigger timer (good).
  static TextStyle timer(BuildContext c, {Color? color}) => GoogleFonts.nunito(
    fontSize: 72, fontWeight: FontWeight.w900,
    color: color ?? Theme.of(c).colorScheme.onSurface,
    letterSpacing: -2, height: 1,
  );

  static TextStyle button(BuildContext c, {Color? color}) => GoogleFonts.nunito(
    fontSize: 17, fontWeight: FontWeight.w700,
    color: color ?? Colors.white,
  );
}
```

**MediaQuery setup in `app.dart`:** wrap MaterialApp's builder so `textScaler` clamps to a sensible max (1.5× max), preventing UI breakage on extreme sizes:

```dart
MaterialApp.router(
  builder: (ctx, child) => MediaQuery(
    data: MediaQuery.of(ctx).copyWith(
      textScaler: MediaQuery.of(ctx).textScaler.clamp(maxScaleFactor: 1.5),
    ),
    child: child!,
  ),
  // ...
)
```

---

## 8. `lib/core/theme/app_theme.dart`

Standard Material 3 ThemeData using Nunito + AppColors. Two themes: `lightTheme` and `darkTheme`. The toggle is driven by a `themeModeProvider` (`StateNotifierProvider<ThemeMode>`) persisted to `shared_preferences` (key: `theme_mode`).

```dart
@riverpod
class AppThemeMode extends _$AppThemeMode {
  @override
  ThemeMode build() {
    final raw = SharedPreferences.getInstance().then((p) => p.getString('theme_mode'));
    return ThemeMode.system; // initial; refreshed by load()
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('theme_mode');
    state = switch (s) {
      'light' => ThemeMode.light,
      'dark'  => ThemeMode.dark,
      _       => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('theme_mode', mode.name);
    state = mode;
  }
}
```

---

## 9. `lib/core/router/app_router.dart`

A `GoRouter` with all routes from §4.3 of the v1.4 spec PLUS:

```dart
// Birthday booking funnel (NEW)
GoRoute(path: '/birthday', name: 'birthday_discovery', builder: ...),
GoRoute(path: '/birthday/packages', name: 'birthday_packages', builder: ...),
GoRoute(path: '/birthday/reserve/:packageId', name: 'birthday_reserve', builder: ...),
GoRoute(path: '/birthday/status/:reservationId', name: 'birthday_status', builder: ...),
GoRoute(path: '/birthday/album/:reservationId', name: 'birthday_album', builder: ...),

// Session pre-booking
GoRoute(path: '/session/pre-book', name: 'session_pre_book', builder: ...),

// Reactivation welcome (deep-linked from SMS install)
GoRoute(path: '/welcome-back', name: 'reactivation_welcome', builder: ...),

// Force update gate
GoRoute(path: '/update-required', name: 'force_update', builder: ...),

// Wall of Legends
GoRoute(path: '/wall-of-legends', name: 'wall_of_legends', builder: ...),

// Reflection screen (entered from Hero Recap card tap)
GoRoute(path: '/reflection/:sessionId', name: 'reflection', builder: ...),
```

The router has a top-level `redirect`:
1. If app version below `min_supported` → redirect to `/update-required`.
2. If not authenticated and not on `/auth/*` → redirect to `/auth/phone`.
3. If authenticated but onboarding incomplete (no name on family record) → redirect to `/onboarding/name`.

---

## 10. `lib/core/providers/server_clock_provider.dart` — fixes timer drift

```dart
@riverpod
class ServerClock extends _$ServerClock {
  Duration _offset = Duration.zero;
  DateTime _lastSync = DateTime(1970);

  @override
  Duration build() => _offset;

  Future<void> sync() async {
    if (DateTime.now().difference(_lastSync) < const Duration(minutes: 5)) return;

    final t0 = DateTime.now().toUtc();
    // Lightweight RPC that returns now() server-side. Round-trip /2 ≈ network latency.
    final response = await Supabase.instance.client.rpc('server_now');
    final t1 = DateTime.now().toUtc();
    final serverTime = DateTime.parse(response['now']).toUtc();
    final rtt = t1.difference(t0);
    final approximatedDispatchTime = t0.add(rtt ~/ 2);
    _offset = serverTime.difference(approximatedDispatchTime);
    _lastSync = DateTime.now();
    state = _offset;
  }

  DateTime get serverNow => DateTime.now().toUtc().add(_offset);
}
```

Tiny RPC needed in DB:
```sql
CREATE OR REPLACE FUNCTION server_now() RETURNS JSONB
LANGUAGE sql STABLE AS $$ SELECT jsonb_build_object('now', now()::text) $$;
```

---

## 11. `lib/core/widgets/session_timer.dart` — server-clock-driven

```dart
class SessionTimerWidget extends ConsumerStatefulWidget {
  final Session session;
  const SessionTimerWidget({super.key, required this.session});
  @override
  ConsumerState<SessionTimerWidget> createState() => _SessionTimerState();
}

class _SessionTimerState extends ConsumerState<SessionTimerWidget> {
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  bool _isGrace = false;

  @override
  void initState() {
    super.initState();
    ref.read(serverClockProvider.notifier).sync();
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return; // guard against setState-after-dispose
    final now = ref.read(serverClockProvider.notifier).serverNow;
    final diff = widget.session.expiresAt.difference(now);
    setState(() {
      if (diff.isNegative) {
        _isGrace = true;
        _remaining = diff.abs();
      } else {
        _isGrace = false;
        _remaining = diff;
      }
    });
  }

  @override
  void dispose() { _ticker?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext c) => Column(
    children: [
      Text(
        _format(_remaining),
        style: AppTextStyles.timer(c, color: _isGrace ? AppColors.warningYellow : null),
        semanticsLabel: _semantics(),
      ),
      Text(
        _isGrace ? 'Planning to extend?' : 'time remaining',
        style: AppTextStyles.caption(c,
          color: _isGrace ? AppColors.warningYellow : null,
        ),
      ),
    ],
  );

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _semantics() => _isGrace
    ? 'Session in grace period, ${_remaining.inMinutes} minutes overrun'
    : '${_remaining.inMinutes} minutes ${_remaining.inSeconds.remainder(60)} seconds remaining';
}
```

---

## 12. `lib/core/utils/phone.dart`

```dart
class PhoneNormalizer {
  /// Returns canonical E.164 (+91XXXXXXXXXX) or null if invalid.
  static String? toE164(String input) {
    var digits = input.replaceAll(RegExp(r'[^\d]'), '');

    // Strip 91 prefix if present (without +)
    if (digits.length == 12 && digits.startsWith('91')) digits = digits.substring(2);

    // Strip leading 0
    if (digits.length == 11 && digits.startsWith('0')) digits = digits.substring(1);

    if (digits.length != 10) return null;
    if (!RegExp(r'^[6-9]').hasMatch(digits)) return null;

    return '+91$digits';
  }

  static bool isValid(String input) => toE164(input) != null;

  /// Format for display: +91 98765-43210
  static String forDisplay(String e164) {
    if (!RegExp(r'^\+91\d{10}$').hasMatch(e164)) return e164;
    return '+91 ${e164.substring(3, 8)}-${e164.substring(8)}';
  }
}
```

---

## 13. `lib/core/utils/currency.dart` — Indian comma format

```dart
class Money {
  static final _formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static final _formatterWithDecimals = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  /// 80000 paise → "₹800"
  /// 110050 paise → "₹1,100.50"
  static String fromPaise(int paise, {bool forceDecimals = false}) {
    final rupees = paise / 100;
    if (!forceDecimals && rupees == rupees.truncate()) {
      return _formatter.format(rupees);
    }
    return _formatterWithDecimals.format(rupees);
  }

  /// Without symbol — for invoice line items
  static String fromPaiseNoSymbol(int paise) =>
    NumberFormat.decimalPattern('en_IN').format(paise / 100);
}
```

---

## 14. `lib/core/utils/ist_dates.dart` — Indian time helpers

```dart
class IstDates {
  static const istOffset = Duration(hours: 5, minutes: 30);

  static DateTime nowInIst() => DateTime.now().toUtc().add(istOffset);

  /// Returns IST date as `YYYY-MM-DD`-aligned local-midnight time
  static DateTime istDate(DateTime utc) {
    final ist = utc.toUtc().add(istOffset);
    return DateTime(ist.year, ist.month, ist.day);
  }

  /// Returns the Monday of the IST week containing the given date.
  /// Streaks count weeks Mon–Sun.
  static DateTime istWeekStart(DateTime utc) {
    final d = istDate(utc);
    // weekday: Monday=1 ... Sunday=7
    return d.subtract(Duration(days: d.weekday - 1));
  }

  static int daysBetween(DateTime fromUtc, DateTime toUtc) =>
    istDate(toUtc).difference(istDate(fromUtc)).inDays;
}
```

---

## 15. `lib/core/services/photo_compress_service.dart`

```dart
class PhotoCompressService {
  /// Resizes to 1080×1080 max, JPEG ~80% quality, ~500 KB cap.
  /// Returns null if image unreadable; throws if compression can't get under cap.
  static Future<Uint8List> compress(Uint8List input) async {
    var img = img_lib.decodeImage(input);
    if (img == null) throw const FormatException('unreadable_image');

    if (img.width > 1080 || img.height > 1080) {
      img = img_lib.copyResize(
        img,
        width: img.width > img.height ? 1080 : null,
        height: img.height > img.width ? 1080 : null,
        interpolation: img_lib.Interpolation.cubic,
      );
    }

    var quality = 85;
    Uint8List jpeg;
    while (true) {
      jpeg = Uint8List.fromList(img_lib.encodeJpg(img, quality: quality));
      if (jpeg.length <= 500 * 1024) return jpeg;
      quality -= 10;
      if (quality < 50) throw const StateError('photo_too_large');
    }
  }
}
```

---

## 16. `lib/core/widgets/error_screen.dart` — friendly error with code

```dart
class FriendlyErrorScreen extends StatelessWidget {
  final String code;          // E-247, etc.
  final String userMessage;
  final String? technicalDetails;
  const FriendlyErrorScreen({super.key, required this.code, required this.userMessage, this.technicalDetails});

  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PhosphorIcon(PhosphorIcons.warningCircle(PhosphorIconsStyle.fill), size: 64, color: AppColors.warningYellow),
          const SizedBox(height: 24),
          Text(userMessage, style: AppTextStyles.h2(c), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text('Error $code', style: AppTextStyles.caption(c)),
          const SizedBox(height: 32),
          PrimaryButton(
            label: 'Copy code & contact support',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: 'Diaries Club error: $code'));
              await launchUrl(Uri.parse('https://wa.me/919XXXXXXXXX?text=Diaries+Club+error:+$code'));
            },
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/home'),
            child: Text('Back to Home', style: AppTextStyles.button(c, color: AppColors.navy)),
          ),
        ],
      ),
    )),
  );
}
```

---

## 17. App Version Gate

Provider that fetches latest min_supported_version from `venue_config` on app start; compares to `package_info_plus`. If app < min_supported, redirect to `/update-required` (a screen with App Store/Play Store buttons).

```dart
@riverpod
Future<AppVersionStatus> appVersionStatus(AppVersionStatusRef ref) async {
  final info = await PackageInfo.fromPlatform();
  final platform = Platform.isIOS ? 'ios' : 'android';
  final config = await Supabase.instance.client
    .from('venue_config').select('${platform}_min_supported_version, ${platform}_latest_version')
    .single();

  final current = Version.parse(info.version);
  final min = Version.parse(config['${platform}_min_supported_version']);
  final latest = Version.parse(config['${platform}_latest_version']);

  if (current < min) return AppVersionStatus.forceUpdate;
  if (current < latest) return AppVersionStatus.softUpdate;
  return AppVersionStatus.upToDate;
}
```

---

## 18. Bottom Navigation Shell

`AppShell` widget hosts a `Scaffold` with `BottomNavigationBar`. 4 tabs:

| Tab | Icon (regular) | Icon (filled) | Route |
|---|---|---|---|
| Home | `house` | `house` (fill) | `/home` |
| Club | `martini` | `martini` (fill) | `/club` |
| Adventure | `compass` | `compass` (fill) | `/adventure` |
| Profile | `user` | `user` (fill) | `/profile` |

Use `phosphor_flutter` Regular weight default, switch to Fill style for the active tab.

---

## Acceptance Tests

```bash
flutter pub get
flutter analyze              # zero issues required
flutter run --flavor dev     # launches into placeholder home
flutter run --flavor prod    # only with prod env file with rzp_live_ keys

# Test version gate
# 1. In Supabase dashboard, set venue_config.ios_min_supported_version = '99.0.0'
# 2. Hot restart app → should redirect to /update-required
# 3. Reset version → app proceeds normally

# Test theme toggle
# Profile → Settings → Theme → Dark → all screens reflow correctly

# Test screen reader
# iOS Simulator → Accessibility Inspector → enable VoiceOver simulation
# Tab through Home → every interactive element should announce its label
```

---

## What's NOT in this session

- Auth screens (Session 4)
- Onboarding (Session 4)
- All actual feature screens (Sessions 5–11)
- Edge Functions (Session 13)
- Tests (Session 14)
