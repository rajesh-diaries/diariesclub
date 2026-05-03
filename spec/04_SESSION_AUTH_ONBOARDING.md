# Session 4 — Authentication + Onboarding

> Paste `00_CONTEXT.md` first, then this file. Fresh Claude Code conversation.
> **Prerequisites:** Sessions 1, 2, 3 complete (database, RPCs, Flutter foundation).

---

## Session Header

```
I am building Diaries Club. Database, RPCs, and Flutter foundation are live.
This session: build the complete auth + onboarding flow.

Estimated time: 4-5 hours
What to build:
  - Phone-based OTP authentication via Supabase + MSG91 custom provider
  - Splash screen with version check + auth state routing
  - 6-step onboarding wizard with progress indicator
  - Cafe-only signup path (skip-kids escape with friction)
  - Family record creation tied to Supabase auth.uid()
  - Child record creation with hero selection
  - Onboarding state persistence (resumable if app killed mid-flow)
  - 18+ guardian declaration gate
  - Phone normalization (E.164) before submission
  - All screens accessible (VoiceOver/TalkBack)
  - Error states for every network call

What NOT to build:
  - Marketing consent (deferred to Home tab card)
  - Welcome credit reactivation matching (deferred to deep-link handler)
  - Account deletion (Profile session)

Output expected:
  - Complete auth flow from splash to home
  - All screens implemented in lib/features/auth/ and lib/features/onboarding/
  - State managed via Riverpod
  - Routing integrated with GoRouter (already set up)

Acceptance:
  - New user with valid phone → through to Home tab in <2 minutes
  - OTP retry, OTP expiry, OTP wrong-code all handled gracefully
  - Killing app at step 3 → reopening resumes at step 3
  - Cafe-only path reaches Home with no children, family.is_cafe_only = true
  - Screen reader reads every interactive element correctly
```

---

## 1. Auth Architecture

### 1.1 Supabase + MSG91 SMS OTP

Supabase Auth supports phone OTP with custom SMS providers. Configure MSG91 as the provider:

**Supabase dashboard → Authentication → Providers → Phone:**
- Enable Phone provider
- Choose Custom Provider
- Endpoint: `https://api.msg91.com/api/v5/otp`
- Auth key + template ID: from MSG91 console (see Pre-Launch Checklist 1.1)
- Message template (must be DLT-approved):
  ```
  Your Diaries Club code is {{otp}}. Valid for 10 minutes. Do not share.
  ```

**OTP rules:**
- 6-digit numeric
- Valid for 10 minutes
- Max 3 verification attempts before the OTP is invalidated
- Max 5 resend requests per phone per 24h (rate-limited server-side)

### 1.2 Auth flow at a glance

```
Splash
  │
  ├─ Auth state: signed in? ─→ check onboarding complete
  │                              │
  │                              ├─ Yes ─→ Home
  │                              └─ No  ─→ resume at saved step
  │
  └─ Auth state: signed out ─→ Phone Entry
                                  │
                                  ▼
                              OTP Verify
                                  │
                                  ▼
                              Family Name
                                  │
                                  ▼
                              Add Child (with skip link)
                                  │
                       ┌──────────┴──────────┐
                       ▼                     ▼
                  Child Details         Cafe-only confirm
                       │                     │
                       ▼                     │
                   Hero Pick                 │
                       │                     │
                       └──────────┬──────────┘
                                  ▼
                           Home (with first-time tour)
```

### 1.3 State persistence

Use `flutter_secure_storage` for sensitive items, `shared_preferences` for the rest:

```dart
// secure_storage keys
'auth_session'         // Supabase session JSON
'idempotency_keys'     // map of pending operation keys

// shared_preferences keys
'onboarding_step'      // last completed step (0-5)
'onboarding_data'      // partial JSON of family/child data
'theme_mode'           // existing
```

---

## 2. Splash Screen — `lib/features/auth/splash_screen.dart`

Always the first screen. Three responsibilities: app version check, auth state check, route to next screen.

### 2.1 Layout

- Centered logo (Diaries Club wordmark or icon)
- Subtle Lottie animation underneath (gentle pulse or float)
- No interactive elements
- Loading indicator IF version check or session restore is taking longer than 1 second
- Background: navy gradient

### 2.2 Logic

```dart
class SplashScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // 1. Check app version
    final versionStatus = await ref.read(appVersionStatusProvider.future);
    if (versionStatus == AppVersionStatus.forceUpdate) {
      if (mounted) context.go('/update-required');
      return;
    }

    // 2. Sync server clock (one-time, prevents timer drift later)
    ref.read(serverClockProvider.notifier).sync();

    // 3. Wait minimum 800ms for splash polish
    await Future.delayed(const Duration(milliseconds: 800));

    // 4. Check auth state
    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      // Not signed in → check for deferred deep link (reactivation)
      final branchData = await FlutterBranchSdk.getLatestReferringParams();
      if (branchData['route'] == 'welcome-back') {
        if (mounted) context.go('/welcome-back?contact_id=${branchData['contact_id']}');
        return;
      }
      if (mounted) context.go('/auth/phone');
      return;
    }

    // 5. Signed in — check if onboarding complete
    final family = await ref.read(currentFamilyProvider.future);
    if (family == null) {
      // Auth user exists but no family record → onboarding incomplete
      final lastStep = await _getLastOnboardingStep();
      if (mounted) context.go(_routeForStep(lastStep));
      return;
    }

    // 6. Onboarded → home
    if (mounted) context.go('/home');
  }

  Future<int> _getLastOnboardingStep() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('onboarding_step') ?? 0;
  }

  String _routeForStep(int step) {
    return switch (step) {
      0 => '/onboarding/welcome',
      1 => '/onboarding/family-name',
      2 => '/onboarding/add-child',
      3 => '/onboarding/child-details',
      4 => '/onboarding/hero-pick',
      _ => '/home',
    };
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    backgroundColor: AppColors.navy,
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo
          Image.asset('assets/images/logo_white.png', width: 160),
          const SizedBox(height: 32),
          // Lottie pulse
          SizedBox(
            width: 80, height: 80,
            child: Lottie.asset('assets/lottie/splash_pulse.json'),
          ),
        ],
      ),
    ),
  );
}
```

---

## 3. Phone Entry Screen — `lib/features/auth/phone_entry_screen.dart`

### 3.1 Layout

```
APP BAR — none (full screen, no back since this IS the start)

HEADER
  - Hero illustration top (small group of all 4 heroes, ~120 height)
  - Title (h1): "Welcome to Diaries Club"
  - Subtitle (body): "Enter your phone number to get started."

PHONE INPUT
  - Country code chip (read-only, shows "🇮🇳 +91")
  - Phone number field (10 digits, numeric keyboard)
  - Live validation: green check appears when 10 digits + starts with 6/7/8/9

LEGAL CHECKBOX (REQUIRED to enable button)
  - Checkbox + text:
    "I am 18+ and a parent/guardian. I agree to the [Privacy Policy] and [Terms]."
  - Each link opens in-app browser to diariesclub.com/privacy or /terms

PRIMARY CTA
  - Full-width button: "Send code"
  - Disabled state until phone valid AND checkbox ticked
  - Loading spinner inside button on tap

FOOTER
  - "Need help?" → opens WhatsApp deep link
```

### 3.2 Interaction

```dart
class PhoneEntryScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final _phoneController = TextEditingController();
  bool _consentChecked = false;
  bool _isLoading = false;
  String? _errorText;

  bool get _canSubmit =>
    _consentChecked &&
    PhoneNormalizer.isValid(_phoneController.text) &&
    !_isLoading;

  Future<void> _sendOtp() async {
    setState(() { _isLoading = true; _errorText = null; });

    final phone = PhoneNormalizer.toE164(_phoneController.text)!;

    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: phone,
        // Supabase routes to MSG91 per provider config
      );

      // Persist phone for OTP screen
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_otp_phone', phone);

      if (mounted) context.push('/auth/otp');
    } on AuthException catch (e) {
      setState(() {
        _errorText = _mapAuthError(e);
        _isLoading = false;
      });
    } catch (e, stack) {
      Sentry.captureException(e, stackTrace: stack);
      setState(() {
        _errorText = "Something went wrong. Please try again.";
        _isLoading = false;
      });
    }
  }

  String _mapAuthError(AuthException e) {
    if (e.message.contains('rate limit')) {
      return "Too many attempts. Please wait a few minutes.";
    }
    if (e.message.contains('invalid')) {
      return "That phone number doesn't look right. Please check.";
    }
    return "Couldn't send code. Please try again.";
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40),
            Image.asset('assets/images/heroes_group_small.png', height: 120),
            const SizedBox(height: 32),
            Text("Welcome to Diaries Club", style: AppTextStyles.h1(c)),
            const SizedBox(height: 8),
            Text("Enter your phone number to get started.",
                 style: AppTextStyles.body(c)),
            const SizedBox(height: 40),

            // Phone field
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.lightBorder),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text("🇮🇳 +91", style: AppTextStyles.body(c)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: "98765 43210",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: PhoneNormalizer.isValid(_phoneController.text)
                        ? const Icon(Icons.check_circle, color: AppColors.activeGreen)
                        : null,
                    ),
                    style: AppTextStyles.body(c),
                  ),
                ),
              ],
            ),

            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(_errorText!, style: AppTextStyles.caption(c, color: AppColors.adminRed)),
            ],

            const SizedBox(height: 24),

            // Consent
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _consentChecked,
                  onChanged: (v) => setState(() => _consentChecked = v ?? false),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _consentChecked = !_consentChecked),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: RichText(
                        text: TextSpan(
                          style: AppTextStyles.caption(c),
                          children: [
                            const TextSpan(text: "I am 18+ and a parent/guardian. I agree to the "),
                            TextSpan(
                              text: "Privacy Policy",
                              style: const TextStyle(decoration: TextDecoration.underline),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => launchUrl(Uri.parse('https://diariesclub.com/privacy')),
                            ),
                            const TextSpan(text: " and "),
                            TextSpan(
                              text: "Terms",
                              style: const TextStyle(decoration: TextDecoration.underline),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => launchUrl(Uri.parse('https://diariesclub.com/terms')),
                            ),
                            const TextSpan(text: "."),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            PrimaryButton(
              label: "Send code",
              onPressed: _canSubmit ? _sendOtp : null,
              isLoading: _isLoading,
            ),

            const SizedBox(height: 24),

            Center(
              child: TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://wa.me/919XXXXXXXXX?text=Need+help+signing+up'),
                ),
                child: Text("Need help?", style: AppTextStyles.caption(c)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
```

### 3.3 Accessibility notes

- `Semantics` wrapper on phone field: `label: "Phone number"`, `hint: "Enter 10-digit Indian mobile number"`
- Consent checkbox: `Semantics(checked: _consentChecked, label: "I agree to terms and privacy policy")`
- Error text uses `Semantics(liveRegion: true)` so screen readers announce on appearance

---

## 4. OTP Verify Screen — `lib/features/auth/otp_verify_screen.dart`

### 4.1 Layout

```
APP BAR
  - Back arrow → returns to phone entry (preserves entered phone)

HEADER
  - Title (h1): "Enter the code"
  - Subtitle: "We sent a 6-digit code to +91 98765-43210"
  - "Wrong number?" link → back to phone entry

OTP FIELD
  - 6 separate input boxes (auto-advance to next, auto-submit on 6th digit)
  - Each box: 48×56, large rounded border
  - Numeric keyboard

ERROR/STATUS REGION
  - "Code expired" / "Wrong code" / "Too many attempts"

RESEND ROW
  - "Resend code in 0:30" countdown
  - After 30s: "Resend code" tappable text link
  - Tracks attempts: 5 max per 24h

FOOTER
  - "Need help?" WhatsApp link
```

### 4.2 Implementation pattern

```dart
class OtpVerifyScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  String? _phone;
  int _resendSeconds = 30;
  int _resendAttempts = 0;
  Timer? _timer;
  bool _isVerifying = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadPhone();
    _startResendTimer();
  }

  Future<void> _loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _phone = prefs.getString('pending_otp_phone'));
  }

  void _startResendTimer() {
    _resendSeconds = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds > 0) {
        setState(() => _resendSeconds--);
      } else {
        t.cancel();
      }
    });
  }

  Future<void> _verify() async {
    final code = _controllers.map((c) => c.text).join();
    if (code.length != 6) return;
    if (_phone == null) return;

    setState(() { _isVerifying = true; _errorText = null; });

    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.sms,
        phone: _phone!,
        token: code,
      );

      if (response.user == null) {
        throw const AuthException('No user returned');
      }

      // Check if family record exists for this auth user
      final family = await Supabase.instance.client
        .from('families').select().eq('id', response.user!.id).maybeSingle();

      if (family == null) {
        // New user — create family row with auth UID, then go to onboarding
        await Supabase.instance.client.from('families').insert({
          'id': response.user!.id,           // CRITICAL: must equal auth.uid()
          'phone': _phone,
          'name': 'Pending',                  // placeholder — set during onboarding
        });

        // Save onboarding step
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('onboarding_step', 1);

        if (mounted) context.go('/onboarding/family-name');
      } else {
        // Returning user with full account → home
        if (mounted) context.go('/home');
      }
    } on AuthException catch (e) {
      setState(() {
        _errorText = _mapOtpError(e);
        _isVerifying = false;
        // Clear all OTP boxes
        for (final c in _controllers) c.clear();
        _focusNodes[0].requestFocus();
      });
    }
  }

  String _mapOtpError(AuthException e) {
    if (e.message.contains('expired')) return "Code expired. Tap resend below.";
    if (e.message.contains('invalid')) return "Wrong code. Please check and try again.";
    return "Couldn't verify. Please try again.";
  }

  Future<void> _resend() async {
    if (_resendAttempts >= 5) {
      setState(() => _errorText = "Too many resends. Please try again in a few hours.");
      return;
    }
    setState(() { _resendAttempts++; _errorText = null; });
    try {
      await Supabase.instance.client.auth.signInWithOtp(phone: _phone!);
      _startResendTimer();
    } catch (e) {
      setState(() => _errorText = "Couldn't resend. Please try again.");
    }
  }

  // Build method renders the 6-box OTP input with auto-advance,
  // resend timer, error region. (Standard pattern, omitted for brevity.)
}
```

### 4.3 OTP UX rules

- **Auto-paste support**: iOS auto-fills 6-digit codes from SMS — let it work (use `keyboardType: TextInputType.number` + `autofillHints: [AutofillHints.oneTimeCode]`)
- **Auto-submit on 6th digit**: don't make the user tap a button
- **Auto-advance focus**: typing a digit moves focus to next box
- **Backspace on empty box**: moves focus to previous box, clears that box
- **All-digits-or-nothing**: paste a 6-digit string → fills all boxes, auto-submit

---

## 5. Onboarding Step 1 — Family Name — `lib/features/onboarding/family_name_screen.dart`

After OTP verify, new user lands here.

### 5.1 Layout

```
APP BAR
  - Progress indicator (1 of 4): "1 ●○○○"
  - No back button (can't go back from here)

HEADER
  - Title: "What should we call you?"
  - Subtitle: "We'll use this on receipts and to greet you."

INPUT
  - Single text field, large
  - Placeholder: "Your name"
  - Auto-focus on mount

PRIMARY CTA
  - Full-width: "Continue"
  - Disabled until name has 2+ characters
```

### 5.2 Logic

On submit:
1. UPDATE the existing families row (created at OTP verify) with the entered name
2. Save `onboarding_step = 2` to SharedPreferences
3. Navigate to `/onboarding/add-child`

```dart
Future<void> _submit() async {
  final name = _controller.text.trim();
  if (name.length < 2) return;

  setState(() => _isLoading = true);
  try {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    await Supabase.instance.client
      .from('families').update({'name': name}).eq('id', userId);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('onboarding_step', 2);

    if (mounted) context.go('/onboarding/add-child');
  } catch (e, stack) {
    Sentry.captureException(e, stackTrace: stack);
    setState(() {
      _errorText = "Couldn't save. Please try again.";
      _isLoading = false;
    });
  }
}
```

---

## 6. Onboarding Step 2 — Add Child Decision — `lib/features/onboarding/add_child_screen.dart`

This is where the cafe-only-with-friction decision lives.

### 6.1 Layout

```
APP BAR
  - Progress: "2 ●●○○"

HEADER
  - Hero illustration (small, friendly)
  - Title: "Tell us about your kid"
  - Subtitle: "We'll set up their adventure profile."

PRIMARY CTA (BIG, prominent)
  - Full-width button: "Add child"
  - Navigates to /onboarding/child-details

SKIP LINK (small, below, de-emphasized)
  - Text only, muted color
  - Label: "I'm just here for coffee — skip for now"
  - Tap → opens confirmation sheet

CONFIRMATION SHEET (bottom sheet, on skip tap)
  Title: "Skip child setup?"
  Body: "You can still order from Coffee Diaries and FIT Diaries.
         You can add a child anytime from your Profile."
  Actions:
    - "Skip for now" → cafe-only path
    - "Add child" → child-details (cancel skip)
```

### 6.2 Logic

```dart
Future<void> _skipToCafeOnly() async {
  // Show confirmation sheet first
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SkipConfirmationSheet(),
  );

  if (confirmed != true) return;

  setState(() => _isLoading = true);
  try {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    await Supabase.instance.client.from('families').update({
      'is_cafe_only': true,
      'has_children': false,
    }).eq('id', userId);

    // Onboarding complete (no child step needed)
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('onboarding_step');
    await prefs.setBool('onboarding_complete', true);

    if (mounted) context.go('/home');
  } catch (e) {
    setState(() {
      _errorText = "Couldn't continue. Please try again.";
      _isLoading = false;
    });
  }
}
```

### 6.3 Friction notes

- The "Add child" button is a full-width primary button — visually dominant
- The skip link is a centered text link below the button — clearly secondary
- Confirmation sheet exists to give one more chance to reconsider
- No skip link on subsequent runs of this screen (if user adds a 2nd child via Profile)

---

## 7. Onboarding Step 3 — Child Details — `lib/features/onboarding/child_details_screen.dart`

### 7.1 Layout

```
APP BAR
  - Progress: "3 ●●●○"
  - Back button (returns to add-child decision)

HEADER
  - Title: "About your kid"

FIELDS (vertical stack):
  1. Photo upload (optional)
     - Tap circle (96×96) → image picker
     - Auto-compresses via PhotoCompressService
     - Upload to Supabase Storage; save URL
     - Skip-able

  2. Child's name (required)
     - Text field, placeholder "First name"

  3. Date of birth (required)
     - Date picker (max date: today, min date: 14 years ago)
     - Display: "DD MMM YYYY"

  4. Delivery address (optional, for milestone gift mailing)
     - Text area, 3 lines
     - Caption: "We'll mail special prizes here"

PRIMARY CTA
  - "Continue" (disabled until name + DOB filled)
```

### 7.2 Logic

On submit:
1. INSERT into `children` (does NOT set favourite_hero yet — that's next screen)
2. Save child ID to SharedPreferences (so hero-pick screen knows which child)
3. Navigate to `/onboarding/hero-pick`

---

## 8. Onboarding Step 4 — Hero Pick — `lib/features/onboarding/hero_pick_screen.dart`

The fun screen. Lock locked decision: cosmetic favorite only — all 4 heroes earn XP.

### 8.1 Layout

```
APP BAR
  - Progress: "4 ●●●●"

HEADER
  - Title: "Pick [Child]'s favourite hero"
  - Subtitle: "They'll all be along for the adventure — pick the one [Child]
              loves the most."

HERO GRID (2x2)
  - Each card 156×210
  - Top: hero illustration (full body, idle pose, ~120 high)
  - Below: hero name + trait pill
    - Rafi (Brave) — coral pill
    - Ellie (Kind) — sky blue pill
    - Gerry (Curious) — amber pill
    - Zena (Creative) — green pill
  - Tap to select → border highlights, gentle scale animation

PRIMARY CTA
  - "Start the adventure!" (disabled until selection made)
```

### 8.2 Logic

```dart
Future<void> _submit() async {
  if (_selectedHero == null) return;

  setState(() => _isLoading = true);
  try {
    final childId = ref.read(currentOnboardingChildIdProvider);
    await Supabase.instance.client
      .from('children')
      .update({'favourite_hero': _selectedHero})
      .eq('id', childId);

    // Onboarding complete
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('onboarding_step');
    await prefs.setBool('onboarding_complete', true);

    if (mounted) context.go('/home?showWelcomeTour=true');
  } catch (e) {
    setState(() {
      _errorText = "Couldn't save. Please try again.";
      _isLoading = false;
    });
  }
}
```

---

## 9. Resume Logic — Killing the App Mid-Flow

If a user closes the app at, say, hero-pick (step 4) without completing:
- `onboarding_step = 4` is saved
- Auth session restored on next launch (Supabase handles this)
- Splash routes to `/onboarding/hero-pick`
- The child record already exists; user just picks hero

If user closes the app at child-details (step 3) without saving:
- `onboarding_step = 3`, no child record exists yet
- Splash routes to `/onboarding/child-details`
- Form starts empty (we don't save partial child data — too much complexity for v1)

---

## 10. Welcome Tour (Post-Onboarding)

When user lands on Home with `?showWelcomeTour=true`, show a 3-step coach-marks tour:

1. **"This is your wallet"** → highlights wallet card
2. **"Tap here to start a session"** → highlights session start CTA
3. **"Find your hero's adventure here"** → highlights Adventure tab

Use `tutorial_coach_mark` package or build simple overlay. Skippable. Show once, never again (track via SharedPreferences `welcome_tour_complete`).

---

## 11. Marketing Consent Card (Home Tab)

Per the locked decision, this lives on Home tab — NOT in onboarding. Briefly described here for handoff to Session 5:

- After 1st session OR 24h post-onboarding, whichever comes first
- Dismissible card on Home: "Get updates from Diaries Club?"
  - "Yes, send me birthday tips and offers" → updates `families.marketing_consent = true`
  - "No thanks" → dismissed, never shown again
- Card persists if not interacted with, until acted on

---

## 12. Common Patterns / Gotchas

### 12.1 Phone re-use prevention

If a user signs out and a different person signs up with the same phone → Supabase Auth treats it as the same auth.uid(). Family record persists. **This is intended behavior** for "I changed phones" cases. If concerns arise about account takeover, add re-verification step (out of scope for v1).

### 12.2 Idempotency on family creation

The OTP verify step inserts a families row. If this runs twice (e.g., user backgrounds app right after OTP success), the second insert fails on PRIMARY KEY conflict. Wrap in try/catch and proceed if conflict — the row is already there.

```dart
try {
  await client.from('families').insert({...});
} on PostgrestException catch (e) {
  if (e.code != '23505') rethrow; // 23505 = unique violation, expected on retry
}
```

### 12.3 Network failure mid-OTP

If user has shaky internet and OTP submit fails:
- Show error, keep OTP digits in field
- "Try again" button re-submits same code
- Don't auto-clear unless server explicitly says wrong code

### 12.4 Audit log

Every successful auth event writes an audit_log row:
```sql
actor_type = 'customer'
actor_id = auth.uid()
action = 'auth.signup' OR 'auth.login'
entity_type = 'family'
entity_id = auth.uid()
```

This happens via Supabase trigger on `families` insert/update — already in Session 1 schema.

---

## 13. Files to Create

```
lib/
├── features/
│   ├── auth/
│   │   ├── splash_screen.dart
│   │   ├── phone_entry_screen.dart
│   │   └── otp_verify_screen.dart
│   └── onboarding/
│       ├── family_name_screen.dart
│       ├── add_child_screen.dart
│       ├── skip_confirmation_sheet.dart
│       ├── child_details_screen.dart
│       └── hero_pick_screen.dart
├── core/
│   ├── providers/
│   │   ├── current_family_provider.dart
│   │   ├── current_onboarding_child_id_provider.dart
│   │   └── onboarding_step_provider.dart
│   └── widgets/
│       ├── primary_button.dart            (if not already from Session 3)
│       ├── progress_dots.dart             (the 4-dot onboarding indicator)
│       └── force_update_screen.dart       (if not already)
```

---

## 14. Acceptance Tests (Manual)

```
TEST 1 — Happy path (new user with child)
  1. Fresh install → Splash → Phone Entry
  2. Enter +91 9876543210, check consent, tap Send Code
  3. Receive OTP via test SMS, enter 6 digits → auto-submit
  4. Family Name screen → enter "Test Family" → Continue
  5. Add Child → tap "Add child"
  6. Child Details → name "Aarav", DOB 2018-05-10 → Continue
  7. Hero Pick → tap Rafi → "Start the adventure!"
  8. Home tab loads with 3-step welcome tour
  9. Database check: families row, children row, wallets row all exist

TEST 2 — Cafe-only path
  1-4 as above
  5. Add Child → tap "I'm just here for coffee — skip for now"
  6. Confirmation sheet → "Skip for now"
  7. Lands on Home directly
  8. Database: families.is_cafe_only = true, no children row

TEST 3 — Resume after kill
  1. Reach hero-pick screen
  2. Force-quit app
  3. Reopen → splash → goes directly to hero-pick (auth restored)
  4. Pick hero → completes onboarding

TEST 4 — Wrong OTP
  1. Reach OTP screen
  2. Enter wrong 6-digit code
  3. Error: "Wrong code. Please check and try again."
  4. Boxes clear, focus returns to first

TEST 5 — Resend cooldown
  1. Reach OTP screen
  2. Resend button shows "0:30" countdown
  3. Cannot tap until 0:00
  4. Tap resend → new OTP sent, counter resets

TEST 6 — Force update
  1. In Supabase, set ios_min_supported_version = '99.0.0'
  2. Restart app → Splash routes to /update-required
  3. Cannot proceed to phone entry

TEST 7 — Accessibility (iOS VoiceOver enabled)
  1. Phone entry: VoiceOver reads "Welcome to Diaries Club, heading"
  2. Phone field announces "Phone number, text field, double tap to edit"
  3. Consent checkbox announces state changes
  4. Send Code button announces enabled/disabled state
```

---

## 15. Open Items for Founder

- [ ] Confirm WhatsApp support number for "Need help?" links (currently `+919XXXXXXXXX`)
- [ ] Provide hero illustrations or use placeholder PNGs (per art track in pre-launch)
- [ ] Confirm OTP message template wording for MSG91 DLT registration
- [ ] Decide tour copy details (3 coach-mark screens)
- [ ] Approve Privacy Policy + Terms drafts before linking from consent checkbox

---

## What's NOT in this session

- Marketing consent card (Session 5 — Home Tab)
- Welcome credit reactivation matching (Session 12 — Integrations)
- Account deletion / anonymisation (Session 5b — Profile)
- Child name during anonymisation flow (Session 5b)
- Editing family name after onboarding (Session 5b)
- Multiple children at signup (always 1 in v1; add more from Profile)
