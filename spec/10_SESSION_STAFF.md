# Session 10 — Staff App

> Paste `00_CONTEXT.md` first, then this file. Fresh Claude Code conversation.
> **Prerequisites:** Sessions 1-9 + 5b complete.

---

## Session Header

```
I am building Diaries Club. Customer-facing app is fully spec'd through Session 9.
This session: build the Staff app — used by venue staff on a shared tablet at
the Kondapur location. Same Flutter codebase, separate flavor.

Locked decisions:
  - Same Flutter codebase as customer app, separate flavor (staff_dev / staff_prod)
  - Shared tablet login (one device, multiple staff via PIN per action)
  - KDS = horizontal swipeable tabs (Pending | Preparing | Ready)
  - Staff CAN toggle menu item availability (in addition to admin web)
  - Birthday photo capture: REMOVED (admin uploads from web instead)

Estimated time: 6-7 hours
What to build:
  - Staff flavor build target (lib/main_staff_dev.dart, lib/main_staff_prod.dart)
  - Tablet login screen (venue auth, shared device)
  - Per-staff PIN entry sheet (opens before sensitive actions)
  - Staff home dashboard
  - QR scanner for session check-in
  - Manual session creation (when phone QR is unavailable)
  - Lookup-by-phone for dead-phone scenarios
  - Active sessions monitor (real-time list of all venue sessions)
  - Session extension on behalf of parent
  - Healthy Bite distribution flow
  - Kitchen Display System (KDS) — order management
  - Menu availability toggle
  - Refund issuance (≤₹500 staff cap; >₹500 needs admin approval)
  - End-of-shift cash reconciliation
  - Audit trail per PIN

What NOT to build:
  - Customer-facing screens (already done)
  - Birthday photo capture (REMOVED)
  - Admin web (Session 11)
  - Edge Function: verify-session-qr backend (Session 13)

Output expected:
  - Working staff app build (separate flavor)
  - All staff actions write per-PIN audit_log entries
  - Real-time updates between customer app + staff app (e.g., parent extends → staff sees)

Acceptance:
  - Staff opens app on tablet → tablet login (venue-level auth)
  - Tap "Start session" → PIN sheet → enter 4-digit PIN → action proceeds
  - Scan parent's QR → session marked active server-side
  - Manual session: enter parent phone, look up family, pick child + duration → start
  - End-of-shift: cash count vs expected, discrepancy logged
  - Refund of ₹400 → succeeds via staff PIN
  - Refund of ₹800 → goes to pending admin approval
```

---

## 1. Staff Flavor Setup

### 1.1 Flavor configuration

Add to `lib/flavors.dart`:

```dart
enum Flavor { dev, staging, prod, staffDev, staffProd }

class FlavorConfig {
  // ... existing fields
  final bool isStaffApp;

  bool get isStaffDev => flavor == Flavor.staffDev;
  bool get isStaffProd => flavor == Flavor.staffProd;
  bool get isStaff => isStaffDev || isStaffProd;
}
```

### 1.2 Entry points

**`lib/main_staff_dev.dart`:**

```dart
import 'package:flutter/material.dart';
import 'app_staff.dart';
import 'flavors.dart';
import 'bootstrap.dart';

void main() async {
  F = const FlavorConfig(
    flavor: Flavor.staffDev,
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    razorpayKeyId: String.fromEnvironment('RAZORPAY_KEY_ID', defaultValue: 'rzp_test_xxx'),
    sentryDsn: String.fromEnvironment('SENTRY_DSN_STAFF'),
    branchKey: '', // not used in staff app
    sentryEnabled: false,
    isStaffApp: true,
  );
  assertSafeRazorpayKeys(F);
  await bootstrap();
}
```

`lib/main_staff_prod.dart` mirrors above with prod values + `Flavor.staffProd`.

### 1.3 App entry

```dart
// lib/app.dart — modified to route based on flavor
class DiariesClubApp extends ConsumerWidget {
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    if (F.isStaff) return const StaffApp();
    return const CustomerApp();
  }
}

class StaffApp extends ConsumerWidget {
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);

    return MaterialApp.router(
      title: 'Diaries Club Staff',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: ref.watch(staffRouterProvider),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(
          textScaler: MediaQuery.of(ctx).textScaler.clamp(maxScaleFactor: 1.3), // tighter on tablet
        ),
        child: child!,
      ),
    );
  }
}
```

### 1.4 Build commands

```bash
# Dev
flutter run --flavor staffDev -t lib/main_staff_dev.dart \
  --dart-define-from-file=env/staff_dev.json

# Prod
flutter build apk --flavor staffProd -t lib/main_staff_prod.dart \
  --dart-define-from-file=env/staff_prod.json
```

Android tablet preferred for the venue. iOS support optional for v1.

---

## 2. Tablet Login (Venue-Level Auth)

The tablet itself logs in once per venue. Then individual staff identify themselves per action via PIN.

### 2.1 Tablet login flow

```
┌─────────────────────────────────────┐
│ FULL SCREEN                          │
│                                     │
│         [Diaries Logo]              │
│                                     │
│       Diaries Staff Tablet          │
│                                     │
│       Venue ID                      │
│       ┌──────────────────┐          │
│       │ KONDAPUR-001     │          │
│       └──────────────────┘          │
│                                     │
│       Tablet password               │
│       ┌──────────────────┐          │
│       │ ••••••••         │          │
│       └──────────────────┘          │
│                                     │
│       [Sign in tablet] PRIMARY      │
│                                     │
└─────────────────────────────────────┘
```

The "tablet password" is a long-lived credential created in Supabase Auth as a "tablet user" (e.g., `tablet-kondapur-001@diariesclub.local`). One auth user per venue tablet. This auth session lasts indefinitely (refresh tokens auto-renew).

### 2.2 Schema: tablet_devices table

```sql
-- Migration: 0005_staff_app.sql
CREATE TABLE IF NOT EXISTS tablet_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id),
  device_label TEXT NOT NULL,                -- 'Kondapur Front Desk', 'Kondapur Cafe'
  auth_user_id UUID UNIQUE NOT NULL,         -- tablet's Supabase auth.users row
  is_active BOOLEAN DEFAULT true,
  last_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

When a tablet signs in, its `auth.uid()` is mapped to a venue via this table. All RPCs check this mapping to resolve `venue_id` for staff-side actions.

### 2.3 Sign-out / kill device

Admin web has a "Revoke tablet" button — sets `tablet_devices.is_active = false`. The next API call from that tablet fails, the app shows a re-auth screen.

---

## 3. Per-Staff PIN Sheet

Critical UX: staff identify themselves via 4-digit PIN before any sensitive action. PIN is hashed with bcrypt in `staff.pin_hash`.

### 3.1 PIN entry sheet

```dart
class StaffPinSheet extends ConsumerStatefulWidget {
  final String actionLabel;       // e.g., "Start session", "Issue refund ₹400"
  final Function(String staffId) onSuccess;

  const StaffPinSheet({
    super.key,
    required this.actionLabel,
    required this.onSuccess,
  });
}

class _StaffPinSheetState extends ConsumerState<StaffPinSheet> {
  final _digits = List.filled(4, '');
  bool _isVerifying = false;
  String? _errorText;

  Future<void> _verify() async {
    final pin = _digits.join();
    if (pin.length != 4) return;

    setState(() { _isVerifying = true; _errorText = null; });

    try {
      // RPC verifies PIN against staff table for current venue
      final result = await Supabase.instance.client.rpc(
        'verify_staff_pin',
        params: {'p_pin': pin},
      );

      final staffId = result['staff_id'];
      if (staffId == null) {
        setState(() {
          _errorText = "Invalid PIN. Try again.";
          _isVerifying = false;
          for (int i = 0; i < _digits.length; i++) _digits[i] = '';
        });
        return;
      }

      // Update last_pin_used_at
      await Supabase.instance.client
        .from('staff').update({'last_pin_used_at': DateTime.now().toIso8601String()})
        .eq('id', staffId);

      Navigator.pop(context);
      widget.onSuccess(staffId);
    } catch (e) {
      setState(() {
        _errorText = "Couldn't verify. Try again.";
        _isVerifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Theme.of(c).scaffoldBackgroundColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _DragHandle(),
        const SizedBox(height: 24),
        Text("Enter your PIN", style: AppTextStyles.h2(c)),
        const SizedBox(height: 8),
        Text(widget.actionLabel,
          style: AppTextStyles.caption(c, color: AppColors.lightTextSecondary)),
        const SizedBox(height: 32),

        // 4-digit input (auto-advance)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: 64, height: 80,
              child: TextField(
                autofocus: i == 0,
                keyboardType: TextInputType.number,
                obscureText: true,
                obscuringCharacter: '●',
                textAlign: TextAlign.center,
                style: AppTextStyles.h1(c),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(1),
                ],
                onChanged: (v) {
                  setState(() => _digits[i] = v);
                  if (v.isNotEmpty && i < 3) {
                    FocusScope.of(c).nextFocus();
                  }
                  if (i == 3 && v.isNotEmpty) {
                    _verify();
                  }
                },
              ),
            ),
          )),
        ),

        if (_errorText != null) ...[
          const SizedBox(height: 16),
          Text(_errorText!, style: AppTextStyles.caption(c, color: AppColors.adminRed)),
        ],

        const SizedBox(height: 24),
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text("Cancel"),
        ),
        SizedBox(height: MediaQuery.of(c).viewInsets.bottom + 16),
      ],
    ),
  );
}
```

### 3.2 PIN verify RPC

```sql
CREATE OR REPLACE FUNCTION verify_staff_pin(p_pin TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_tablet tablet_devices%ROWTYPE;
  v_staff staff%ROWTYPE;
BEGIN
  -- Find which venue this tablet belongs to
  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

  -- Find staff with this PIN at this venue
  SELECT * INTO v_staff FROM staff
    WHERE venue_id = v_tablet.venue_id AND is_active = true
      AND pin_hash = crypt(p_pin, pin_hash);
  -- Note: bcrypt comparison via pgcrypto extension

  IF NOT FOUND THEN
    RETURN jsonb_build_object('staff_id', null);
  END IF;

  RETURN jsonb_build_object(
    'staff_id', v_staff.id,
    'staff_name', v_staff.name,
    'role', v_staff.role
  );
END $$;

GRANT EXECUTE ON FUNCTION verify_staff_pin TO authenticated;
```

### 3.3 PIN setup

PINs are set by admin from Admin web (Session 11). Each staff has unique 4-digit PIN. Reset on suspicion of compromise.

---

## 4. Staff Home Dashboard

After tablet login, staff see this:

### 4.1 Layout

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ Diaries Staff · Kondapur            │
│                  [Settings] [≡]     │
├─────────────────────────────────────┤
│ TOP STATS BAR                       │
│ ┌──────┬──────┬──────┬──────┐       │
│ │ 5    │ 12   │ 3    │ ₹4.2K│       │
│ │Active│Today │Pend. │Today │       │
│ │sess. │sess. │orders│cash  │       │
│ └──────┴──────┴──────┴──────┘       │
├─────────────────────────────────────┤
│ QUICK ACTIONS (large cards, 2x3)    │
│ ┌──────────┐  ┌──────────┐          │
│ │ 📷       │  │ 📱       │          │
│ │ Scan QR  │  │ Manual   │          │
│ │          │  │ session  │          │
│ └──────────┘  └──────────┘          │
│ ┌──────────┐  ┌──────────┐          │
│ │ ⏰        │  │ 🍽       │          │
│ │ Active   │  │ Kitchen  │          │
│ │ sessions │  │ display  │          │
│ └──────────┘  └──────────┘          │
│ ┌──────────┐  ┌──────────┐          │
│ │ 🥕       │  │ ↺        │          │
│ │ Healthy  │  │ Refund   │          │
│ │ Bite     │  │          │          │
│ └──────────┘  └──────────┘          │
├─────────────────────────────────────┤
│ END SHIFT CTA (bottom, prominent)   │
│ [End shift & reconcile cash]        │
└─────────────────────────────────────┘
```

### 4.2 Implementation

```dart
class StaffHomeScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    return Scaffold(
      appBar: StaffAppBar(),
      body: SafeArea(child: SingleChildScrollView(
        child: Column(
          children: [
            const StaffStatsBar(),
            const SizedBox(height: 24),
            const QuickActionsGrid(),
            const SizedBox(height: 24),
            const EndShiftCta(),
            const SizedBox(height: 24),
          ],
        ),
      )),
    );
  }
}

class QuickActionsGrid extends StatelessWidget {
  @override
  Widget build(BuildContext c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.4,
        children: [
          _ActionCard(
            icon: PhosphorIcons.qrCode(),
            label: "Scan QR",
            onTap: () => _showPinSheet(c, 'Scan session QR', '/staff/scan'),
          ),
          _ActionCard(
            icon: PhosphorIcons.phoneCall(),
            label: "Manual session",
            onTap: () => _showPinSheet(c, 'Create manual session', '/staff/manual'),
          ),
          _ActionCard(
            icon: PhosphorIcons.clock(),
            label: "Active sessions",
            onTap: () => context.push('/staff/sessions'),
          ),
          _ActionCard(
            icon: PhosphorIcons.cookingPot(),
            label: "Kitchen display",
            onTap: () => context.push('/staff/kds'),
          ),
          _ActionCard(
            icon: PhosphorIcons.carrot(),
            label: "Healthy Bite",
            onTap: () => _showPinSheet(c, 'Distribute Healthy Bite', '/staff/healthy-bite'),
          ),
          _ActionCard(
            icon: PhosphorIcons.arrowUUpLeft(),
            label: "Refund",
            onTap: () => _showPinSheet(c, 'Issue refund', '/staff/refund'),
          ),
        ],
      ),
    );
  }
}
```

The `_showPinSheet` helper opens the PIN sheet, then on success navigates to the route with `?staffId=...` so the destination screen knows which staff member is acting.

---

## 5. QR Scanner — `lib/features/staff/qr_scanner_screen.dart`

### 5.1 Layout

Full-screen camera with overlay:

```
┌─────────────────────────────────────┐
│ [back]                       [flash]│
├─────────────────────────────────────┤
│                                     │
│      Camera viewport                │
│      ┌──────────────────┐           │
│      │                  │           │
│      │   QR scan box    │           │
│      │   (shaded outside)│          │
│      │                  │           │
│      └──────────────────┘           │
│                                     │
│      Scan parent's QR               │
├─────────────────────────────────────┤
│ Trouble scanning?                   │
│ [Manual session →]                  │
└─────────────────────────────────────┘
```

### 5.2 Implementation

```dart
class QrScannerScreen extends ConsumerStatefulWidget {
  final String staffId;
  const QrScannerScreen({super.key, required this.staffId});
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null) return;

    setState(() => _isProcessing = true);
    HapticFeedback.lightImpact();

    try {
      // Verify QR via Edge Function
      final result = await Supabase.instance.client.functions.invoke(
        'verify-session-qr',
        body: {
          'qr_payload': code,
          'staff_id': widget.staffId,
        },
      );

      if (result.data['valid'] == true) {
        // Navigate to confirmation screen
        if (mounted) {
          context.go('/staff/scan-success?sessionId=${result.data['session_id']}');
        }
      } else {
        _showError(result.data['error'] ?? 'Invalid QR');
        await Future.delayed(const Duration(seconds: 2));
        setState(() => _isProcessing = false);
      }
    } catch (e) {
      _showError('Network error');
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text("Scan QR"),
      actions: [
        IconButton(
          icon: PhosphorIcon(PhosphorIcons.flashlight()),
          onPressed: () => _controller.toggleTorch(),
        ),
      ],
    ),
    body: Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
        ),

        // Scan box overlay
        Center(
          child: Container(
            width: 280, height: 280,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.gold, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),

        // Bottom helper
        Positioned(
          bottom: 32, left: 0, right: 0,
          child: Center(
            child: TextButton(
              onPressed: () => context.go('/staff/manual'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text("Trouble scanning? Manual session →",
                  style: AppTextStyles.button(c, color: Colors.white)),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
```

### 5.3 Scan success screen

After successful QR verification, show confirmation:

```
┌─────────────────────────────────────┐
│ ✓ CHECKED IN                        │
│                                     │
│   Aarav (Sharma family)             │
│   2-hour session                    │
│   Started at 4:32 PM                │
│   Will end: 6:32 PM                 │
│                                     │
│   Healthy Bite earned ✓             │
│                                     │
│   [Done]                             │
└─────────────────────────────────────┘
```

Auto-dismisses after 5 seconds OR tap Done → returns to scanner.

---

## 6. Manual Session — `lib/features/staff/manual_session_screen.dart`

For when parent's phone is dead or QR isn't loading.

### 6.1 Layout

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [back] Manual session               │
├─────────────────────────────────────┤
│ STEP 1: FIND FAMILY                 │
│ Phone number:                       │
│ ┌──────────────────────┐            │
│ │ 🇮🇳 +91 [98765 43210] │            │
│ └──────────────────────┘            │
│ [Look up]                           │
├─────────────────────────────────────┤
│ STEP 2: PICK CHILD                  │
│ Family: Sharma                      │
│ Wallet: ₹1,250                      │
│                                     │
│ ○ Aarav (5 yrs)                     │
│ ○ Riya (8 yrs)                      │
├─────────────────────────────────────┤
│ STEP 3: DURATION + PAYMENT          │
│ Duration:                           │
│ ○ 1 hour (₹800)  ○ 2 hours (₹1,100) │
│                                     │
│ Payment:                            │
│ ○ Wallet (₹1,250 available)         │
│ ○ Cash                              │
│ ○ UPI/Card via terminal             │
├─────────────────────────────────────┤
│ STICKY BOTTOM                       │
│ [Start session ₹800]   PRIMARY       │
└─────────────────────────────────────┘
```

### 6.2 Lookup-by-phone

```dart
Future<void> _lookupFamily() async {
  final phone = PhoneNormalizer.toE164(_phoneController.text);
  if (phone == null) {
    setState(() => _errorText = "Invalid phone number");
    return;
  }

  setState(() => _isLoading = true);

  try {
    final result = await Supabase.instance.client.rpc(
      'staff_lookup_family',
      params: {'p_phone': phone},
    );

    setState(() {
      _family = Family.fromJson(result['family']);
      _children = (result['children'] as List).map((c) => Child.fromJson(c)).toList();
      _wallet = Wallet.fromJson(result['wallet']);
      _isLoading = false;
    });
  } catch (e) {
    setState(() {
      _errorText = "Family not found. Try a different number?";
      _isLoading = false;
    });
  }
}
```

### 6.3 New RPC: `staff_lookup_family`

```sql
CREATE OR REPLACE FUNCTION staff_lookup_family(p_phone TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_family families%ROWTYPE;
  v_wallet wallets%ROWTYPE;
  v_children JSONB;
  v_tablet tablet_devices%ROWTYPE;
BEGIN
  -- Authorise: caller must be a tablet device
  SELECT * INTO v_tablet FROM tablet_devices WHERE auth_user_id = auth.uid() AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

  SELECT * INTO v_family FROM families WHERE phone = p_phone AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'family_not_found'; END IF;

  SELECT * INTO v_wallet FROM wallets WHERE family_id = v_family.id;

  SELECT jsonb_agg(to_jsonb(c)) INTO v_children
  FROM (SELECT id, name, date_of_birth, photo_url, favourite_hero, current_level, current_overall_stage
        FROM children WHERE family_id = v_family.id) c;

  RETURN jsonb_build_object(
    'family', to_jsonb(v_family) - 'fcm_token',  -- strip sensitive fields
    'children', COALESCE(v_children, '[]'::jsonb),
    'wallet', to_jsonb(v_wallet)
  );
END $$;

GRANT EXECUTE ON FUNCTION staff_lookup_family TO authenticated;
```

### 6.4 Start session via session_create RPC

Standard `session_create` with `p_staff_pin_id` set to the authenticated staff. The RPC was already built in Session 2.

---

## 7. Active Sessions Monitor — `lib/features/staff/active_sessions_screen.dart`

Real-time list of all active and grace sessions at this venue.

### 7.1 Layout

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [back] Active sessions (5)          │
├─────────────────────────────────────┤
│ ACTIVE                              │
│ ┌─────────────────────────────────┐ │
│ │ Aarav · 2hr session             │ │
│ │ Sharma · 4:32 PM start          │ │
│ │ ⏰ 1:23:45 remaining             │ │
│ │ [Extend] [Force close]          │ │
│ └─────────────────────────────────┘ │
│ ...                                 │
├─────────────────────────────────────┤
│ GRACE (over time)                   │
│ ┌─────────────────────────────────┐ │
│ │ Riya · 2hr session              │ │
│ │ ⚠ +12:30 over                   │ │
│ │ [Nudge parent] [Extend] [Close] │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### 7.2 Logic

```dart
@riverpod
Stream<List<Session>> venueActiveSessions(VenueActiveSessionsRef ref) async* {
  final venueId = await ref.watch(currentVenueIdProvider.future);

  await for (final rows in Supabase.instance.client
      .from('sessions')
      .stream(primaryKey: ['id'])
      .eq('venue_id', venueId)
      .order('started_at', ascending: true)) {

    yield rows
      .where((r) => ['active', 'grace'].contains(r['status']))
      .map((r) => Session.fromJson(r))
      .toList();
  }
}
```

### 7.3 Staff actions on session

| Action | RPC called | Notes |
|---|---|---|
| Extend | `session_extend` with `p_initiated_by='staff_on_behalf'` | Parent gets push notification confirming staff extended |
| Force close | `session_force_close` (new RPC) | Used in grace state when parent hasn't returned |
| Nudge parent | Insert notifications row + push fires | Type: `extend_nudge` |

### 7.4 New RPC: `session_force_close`

```sql
CREATE OR REPLACE FUNCTION session_force_close(
  p_session_id UUID,
  p_staff_pin_id UUID,
  p_reason TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_session sessions%ROWTYPE;
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id FOR UPDATE;
  IF v_session.status NOT IN ('active', 'grace') THEN
    RAISE EXCEPTION 'session_not_active';
  END IF;

  UPDATE sessions SET
    status = 'completed',
    completed_at = now(),
    notes = COALESCE(notes, '') || ' | force-closed: ' || p_reason
  WHERE id = p_session_id;

  -- Audit
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_staff_pin_id, 'staff', 'session.force_close', 'session', p_session_id, v_session.venue_id,
          jsonb_build_object('reason', p_reason));

  RETURN jsonb_build_object('success', true);
END $$;

GRANT EXECUTE ON FUNCTION session_force_close TO authenticated, service_role;
```

---

## 8. Healthy Bite Distribution

When session_create runs with `healthy_bite_earned = true` (per existing logic), staff sees a pending claim. Here they distribute it.

### 8.1 Layout

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [back] Healthy Bite                 │
├─────────────────────────────────────┤
│ PENDING CLAIMS (3)                  │
│ ┌─────────────────────────────────┐ │
│ │ Aarav · earned 2:30 PM          │ │
│ │ Sharma family                   │ │
│ │ [Distribute card]                │ │
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │ Riya · earned 2:45 PM           │ │
│ │ ...                             │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### 8.2 Distribute action

Staff hands a Healthy Bite snack to the child, then taps "Distribute card." The app calls `healthy_bite_distribute` RPC (already in Session 2). This generates a hero card (10% chance rare) and:
- Inserts hero_card_collection row
- Marks session.healthy_bite_distributed = true
- Notifies parent (push: "[Child] earned a hero card!")

The parent's app shows the unboxing flow on their next visit to the app.

```dart
Future<void> _distribute(Session session, String staffId) async {
  try {
    final result = await Supabase.instance.client.rpc(
      'healthy_bite_distribute',
      params: {
        'p_session_id': session.id,
        'p_child_id': session.childId,
        'p_staff_pin_id': staffId,
      },
    );

    final cardName = result['card_name'];
    final isRare = result['is_rare'];

    _showSuccess(
      "Card given: $cardName${isRare ? ' (RARE!)' : ''}",
    );
  } catch (e) {
    _showError("Couldn't distribute. Try again.");
  }
}
```

---

## 9. Kitchen Display System (KDS) — `lib/features/staff/kds_screen.dart`

### 9.1 Layout

Per locked decision, horizontal swipeable tabs:

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [back] Kitchen     [auto-refresh]   │
├─────────────────────────────────────┤
│ Pending (3) | Preparing (2) | Ready │
│ ─────────                           │
├─────────────────────────────────────┤
│ ORDER CARDS (visible per-tab)       │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ Order #1234         Coffee+FIT  │ │
│ │ Aarav · 4:32 PM (3 min ago)     │ │
│ │                                 │ │
│ │ COFFEE:                         │ │
│ │ • Cappuccino x2                 │ │
│ │ • Croissant                     │ │
│ │                                 │ │
│ │ FIT:                            │ │
│ │ • Quinoa Bowl                   │ │
│ │                                 │ │
│ │ Notes: extra hot, no nuts       │ │
│ │                                 │ │
│ │ [Mark preparing →]              │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### 9.2 Implementation

```dart
class KdsScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends ConsumerState<KdsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _autoRefresh = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext c) {
    final orders = ref.watch(venueOrdersStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Kitchen"),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            _CountTab(label: "Pending", count: _countByStatus(orders, 'pending')),
            _CountTab(label: "Preparing", count: _countByStatus(orders, 'preparing')),
            _CountTab(label: "Ready", count: _countByStatus(orders, 'ready')),
          ],
        ),
        actions: [
          IconButton(
            icon: PhosphorIcon(_autoRefresh ? PhosphorIcons.lightning(PhosphorIconsStyle.fill) : PhosphorIcons.lightning()),
            onPressed: () => setState(() => _autoRefresh = !_autoRefresh),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OrdersList(orders: orders, status: 'pending'),
          _OrdersList(orders: orders, status: 'preparing'),
          _OrdersList(orders: orders, status: 'ready'),
        ],
      ),
    );
  }
}

@riverpod
Stream<List<Order>> venueOrdersStream(VenueOrdersStreamRef ref) async* {
  final venueId = await ref.watch(currentVenueIdProvider.future);

  await for (final rows in Supabase.instance.client
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('venue_id', venueId)
      .order('created_at', ascending: true)) {
    yield rows
      .where((r) => ['pending', 'preparing', 'ready'].contains(r['status']))
      .map((r) => Order.fromJson(r))
      .toList();
  }
}
```

### 9.3 Order card with status transition

```dart
class KdsOrderCard extends ConsumerWidget {
  final Order order;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final items = ref.watch(orderItemsProvider(order.id));
    final ageMinutes = DateTime.now().difference(order.createdAt).inMinutes;
    final isOld = ageMinutes > 15; // visual warning

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(c).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOld ? AppColors.adminRed : AppColors.lightBorder,
          width: isOld ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text("Order #${order.id.substring(0,4).toUpperCase()}",
                  style: AppTextStyles.h3(c)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _ageColor(ageMinutes).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text("${ageMinutes}m ago",
                    style: AppTextStyles.caption(c, color: _ageColor(ageMinutes))),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text("Family: ${_familyDisplay(order)}",
              style: AppTextStyles.caption(c)),
            const SizedBox(height: 16),

            // Items grouped by brand
            items.when(
              data: (its) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _groupItemsByBrand(its).entries.expand((entry) => [
                  Text(entry.key.toUpperCase(),
                    style: AppTextStyles.caption(c).copyWith(letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  ...entry.value.map((i) => Text(
                    "• ${i.nameSnapshot} ${i.quantity > 1 ? 'x${i.quantity}' : ''}",
                    style: AppTextStyles.body(c),
                  )),
                  const SizedBox(height: 12),
                ]).toList(),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            // Special instructions / notes
            // (would come from order_items.notes if any)

            const SizedBox(height: 8),

            // Action button
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: _nextActionLabel(order.status),
                onPressed: () => _advanceStatus(c, ref, order),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _nextActionLabel(String status) => switch (status) {
    'pending' => "Mark preparing →",
    'preparing' => "Mark ready →",
    'ready' => "Mark served ✓",
    _ => "",
  };

  Future<void> _advanceStatus(BuildContext c, WidgetRef ref, Order order) async {
    final nextStatus = switch (order.status) {
      'pending' => 'preparing',
      'preparing' => 'ready',
      'ready' => 'served',
      _ => order.status,
    };

    try {
      await Supabase.instance.client
        .from('orders')
        .update({'status': nextStatus})
        .eq('id', order.id);
      // Realtime will update both staff KDS and customer's order tracking screen
    } catch (e) {
      _showError(c, "Couldn't update");
    }
  }
}
```

### 9.4 Audio cue for new orders (optional)

When a new order with `status='pending'` appears, play a soft chime. Use `audioplayers` package. Toggle in settings.

---

## 10. Menu Availability Toggle

Quick action from staff app (per locked decision, in addition to admin web).

### 10.1 Layout — `/staff/menu-availability`

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [back] Menu availability            │
├─────────────────────────────────────┤
│ Tabs: Coffee | FIT                  │
├─────────────────────────────────────┤
│ ITEM ROWS WITH TOGGLES              │
│ Cappuccino           [TOGGLE: ON ]  │
│ Croissant            [TOGGLE: OFF]  │
│ Quinoa Bowl          [TOGGLE: ON ]  │
│ ...                                 │
└─────────────────────────────────────┘
```

### 10.2 Toggle action

```dart
Future<void> _toggleAvailability(MenuItem item, bool newValue) async {
  // Per-action PIN check
  final pinResult = await showModalBottomSheet<String>(
    context: context,
    builder: (_) => StaffPinSheet(
      actionLabel: 'Toggle ${item.name} availability',
      onSuccess: (staffId) => Navigator.pop(c, staffId),
    ),
  );

  if (pinResult == null) return;

  await Supabase.instance.client
    .from('menu_items')
    .update({'is_available': newValue, 'updated_at': DateTime.now().toIso8601String()})
    .eq('id', item.id);

  // Audit
  await Supabase.instance.client.from('audit_log').insert({
    'actor_id': pinResult,
    'actor_type': 'staff',
    'action': newValue ? 'menu.enable' : 'menu.disable',
    'entity_type': 'menu_item',
    'entity_id': item.id,
    'venue_id': await ref.read(currentVenueIdProvider.future),
    'new_value': {'is_available': newValue},
  });

  // Customer-side menu_items stream picks this up within ~2s
}
```

---

## 11. Refund Flow

### 11.1 Layout — `/staff/refund`

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [back] Issue refund                 │
├─────────────────────────────────────┤
│ FIND ORIGINAL TRANSACTION           │
│                                     │
│ Phone:                              │
│ ┌──────────────────────┐            │
│ │ +91 [98765 43210]    │            │
│ └──────────────────────┘            │
│ [Look up]                           │
├─────────────────────────────────────┤
│ RECENT TRANSACTIONS                 │
│ ○ Order #1234 - ₹325 (Coffee)       │
│ ○ Session 4:32 PM - ₹800            │
│ ○ Wallet topup - ₹500               │
├─────────────────────────────────────┤
│ REFUND DETAILS                      │
│ Amount: ₹400 (auto-filled from txn) │
│ ┌───────────────┐                   │
│ │ ₹ 400         │ ← editable        │
│ └───────────────┘                   │
│                                     │
│ Reason (required):                  │
│ ┌──────────────────────────────┐    │
│ │ Wrong order delivered        │    │
│ └──────────────────────────────┘    │
│                                     │
│ Destination:                        │
│ ○ Wallet (faster, recommended)      │
│ ○ Razorpay (3-5 business days)      │
├─────────────────────────────────────┤
│ STAFF CAP NOTICE (if amount >₹500)  │
│ ⚠ Above ₹500 — needs admin approval │
├─────────────────────────────────────┤
│ STICKY BOTTOM                       │
│ [Issue refund]   PRIMARY             │
└─────────────────────────────────────┘
```

### 11.2 Refund logic

```dart
Future<void> _issueRefund(String staffId) async {
  final amountPaise = (_amountController.text.toDouble() * 100).round();
  final reason = _reasonController.text.trim();

  if (amountPaise <= 0 || reason.isEmpty) {
    _showError("Amount and reason are required");
    return;
  }

  try {
    final result = await Supabase.instance.client.rpc(
      'refund_issue',
      params: {
        'p_family_id': _selectedFamilyId,
        'p_reference_id': _selectedTransactionId,
        'p_reference_type': _selectedReferenceType,
        'p_amount_paise': amountPaise,
        'p_destination': _destination,
        'p_initiated_by': 'staff',
        'p_staff_pin_id': staffId,
        'p_reason': reason,
      },
    );

    if (result['status'] == 'completed') {
      _showSuccess("Refund of ${Money.fromPaise(amountPaise)} issued.");
    } else if (result['status'] == 'pending') {
      _showInfo("Refund request submitted. Admin will approve.");
    }
  } on PostgrestException catch (e) {
    if (e.message.contains('exceeds_staff_cap')) {
      _showError("Above ₹500 — admin approval required");
    } else {
      _showError("Couldn't issue refund");
    }
  }
}
```

### 11.3 New RPC: `refund_issue`

```sql
CREATE OR REPLACE FUNCTION refund_issue(
  p_family_id UUID,
  p_reference_id UUID,
  p_reference_type TEXT,
  p_amount_paise INTEGER,
  p_destination TEXT,
  p_initiated_by TEXT,            -- 'staff' or 'admin'
  p_staff_pin_id UUID DEFAULT NULL,
  p_reason TEXT,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_existing refunds%ROWTYPE;
  v_refund refunds%ROWTYPE;
  v_status TEXT;
  v_wallet wallets%ROWTYPE;
BEGIN
  -- Idempotency
  IF p_idempotency_key IS NOT NULL THEN
    -- (check existing refunds with same key — pattern as before)
  END IF;

  -- Staff cap: ≤ ₹500 auto-approved, otherwise pending
  IF p_initiated_by = 'staff' AND p_amount_paise > 50000 THEN
    v_status := 'pending';
  ELSE
    v_status := 'approved';
  END IF;

  INSERT INTO refunds(
    family_id, reference_id, reference_type, amount_paise, destination,
    initiated_by, staff_pin_id, status, reason
  ) VALUES (
    p_family_id, p_reference_id, p_reference_type, p_amount_paise, p_destination,
    p_initiated_by, p_staff_pin_id, v_status, p_reason
  ) RETURNING * INTO v_refund;

  -- If approved, execute the refund immediately (wallet credit)
  IF v_status = 'approved' AND p_destination = 'wallet' THEN
    UPDATE wallets SET balance_paise = balance_paise + p_amount_paise, updated_at = now()
      WHERE family_id = p_family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise,
      payment_method, reference_id, reference_type
    ) VALUES (
      p_family_id, 'refund', p_amount_paise, v_wallet.balance_paise,
      'system', v_refund.id, 'refund'
    );

    UPDATE refunds SET status = 'completed' WHERE id = v_refund.id;

    -- Notify customer
    INSERT INTO notifications(family_id, type, title, body, deep_link)
    VALUES (p_family_id, 'refund_processed',
            '${Money.fromPaise(p_amount_paise)} refunded to your wallet',
            'Reason: ' || p_reason,
            '/profile/wallet-history');
  END IF;

  -- Audit
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, p_family_id),
    p_initiated_by,
    'refund.' || v_status,
    'refund', v_refund.id,
    jsonb_build_object('amount', p_amount_paise, 'reason', p_reason)
  );

  RETURN jsonb_build_object(
    'success', true,
    'refund_id', v_refund.id,
    'status', v_refund.status
  );
END $$;

GRANT EXECUTE ON FUNCTION refund_issue TO authenticated, service_role;
```

---

## 12. End-of-Shift Cash Reconciliation

### 12.1 End shift CTA on home

Tap "End shift & reconcile cash" → opens flow.

### 12.2 Reconciliation screen

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [back] End shift                    │
├─────────────────────────────────────┤
│ SHIFT SUMMARY                       │
│ Started: Today 10:00 AM             │
│ Now: 9:32 PM                        │
│ Sessions: 18                        │
│ Orders: 24                          │
│ Refunds: 1                          │
├─────────────────────────────────────┤
│ EXPECTED CASH                       │
│ Cash payments collected: ₹4,250     │
│ Cash refunds given: -₹0             │
│ Expected in drawer: ₹4,250          │
├─────────────────────────────────────┤
│ COUNTED CASH (manual entry)         │
│ ┌──────────────┐                    │
│ │ ₹ 4,200      │                    │
│ └──────────────┘                    │
│ Discrepancy: -₹50                   │
├─────────────────────────────────────┤
│ NOTES (optional)                    │
│ ┌──────────────────────────────┐    │
│ │ Found ₹50 missing — checking │    │
│ └──────────────────────────────┘    │
├─────────────────────────────────────┤
│ STICKY BOTTOM                       │
│ [Close shift]   PRIMARY              │
└─────────────────────────────────────┘
```

### 12.3 Logic

```dart
Future<void> _closeShift(String staffId) async {
  setState(() => _isLoading = true);

  try {
    final result = await Supabase.instance.client.rpc(
      'shift_close',
      params: {
        'p_counted_cash_paise': (_countedAmount * 100).round(),
        'p_notes': _notesController.text.trim(),
        'p_staff_pin_id': staffId,
      },
    );

    final discrepancy = result['discrepancy_paise'] as int;
    if (discrepancy.abs() > 10000) { // >₹100 discrepancy
      _showWarning("Large discrepancy logged. Admin will be notified.");
    } else {
      _showSuccess("Shift closed.");
    }

    if (mounted) context.go('/staff/home');
  } catch (e) {
    _showError("Couldn't close shift");
    setState(() => _isLoading = false);
  }
}
```

### 12.4 New RPC: `shift_close`

```sql
CREATE OR REPLACE FUNCTION shift_close(
  p_counted_cash_paise INTEGER,
  p_notes TEXT DEFAULT NULL,
  p_staff_pin_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_tablet tablet_devices%ROWTYPE;
  v_shift shift_logs%ROWTYPE;
  v_expected INTEGER;
BEGIN
  SELECT * INTO v_tablet FROM tablet_devices WHERE auth_user_id = auth.uid() AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

  -- Find open shift for this venue
  SELECT * INTO v_shift FROM shift_logs
    WHERE venue_id = v_tablet.venue_id AND status = 'open' FOR UPDATE;

  IF NOT FOUND THEN
    -- No open shift — auto-create one based on today's transactions
    INSERT INTO shift_logs(venue_id, shift_start, status)
    VALUES (v_tablet.venue_id, DATE_TRUNC('day', now()), 'open')
    RETURNING * INTO v_shift;
  END IF;

  -- Compute expected cash (sum of cash transactions since shift_start)
  SELECT COALESCE(SUM(amount_paise * -1), 0) INTO v_expected
  FROM wallet_transactions
  WHERE created_at >= v_shift.shift_start
    AND payment_method = 'cash'
    AND amount_paise < 0; -- debits only (cash payments come in, not out)

  -- Plus cash refunds (rare — refunds usually go to wallet/razorpay)
  -- Skipped for v1 simplicity

  UPDATE shift_logs SET
    shift_end = now(),
    expected_cash_paise = v_expected,
    counted_cash_paise = p_counted_cash_paise,
    notes = p_notes,
    closed_by_pin = p_staff_pin_id,
    status = 'closed'
  WHERE id = v_shift.id RETURNING * INTO v_shift;

  -- If big discrepancy, alert admin (notification + Sentry)
  IF ABS(v_shift.discrepancy_paise) > 10000 THEN
    -- Insert admin alert (separate notifications for admin role)
    INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
    VALUES (p_staff_pin_id, 'staff', 'shift.discrepancy_alert', 'shift_log', v_shift.id, v_tablet.venue_id,
            jsonb_build_object('discrepancy', v_shift.discrepancy_paise));
  END IF;

  -- Audit
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_staff_pin_id, 'staff', 'shift.close', 'shift_log', v_shift.id, v_tablet.venue_id,
          jsonb_build_object(
            'expected', v_expected,
            'counted', p_counted_cash_paise,
            'discrepancy', v_shift.discrepancy_paise
          ));

  RETURN jsonb_build_object(
    'success', true,
    'shift_id', v_shift.id,
    'expected_cash_paise', v_expected,
    'counted_cash_paise', p_counted_cash_paise,
    'discrepancy_paise', v_shift.discrepancy_paise
  );
END $$;

GRANT EXECUTE ON FUNCTION shift_close TO authenticated;
```

---

## 13. Files to Create

```
lib/
├── main_staff_dev.dart                  // entry
├── main_staff_prod.dart                 // entry
├── app_staff.dart                       // top-level Staff app widget
└── features/
    └── staff/
        ├── tablet_login_screen.dart
        ├── staff_home_screen.dart
        ├── widgets/
        │   ├── staff_app_bar.dart
        │   ├── staff_stats_bar.dart
        │   ├── quick_actions_grid.dart
        │   ├── action_card.dart
        │   ├── end_shift_cta.dart
        │   ├── staff_pin_sheet.dart
        │   └── kds_order_card.dart
        ├── qr_scanner_screen.dart
        ├── scan_success_screen.dart
        ├── manual_session_screen.dart
        ├── active_sessions_screen.dart
        ├── healthy_bite_screen.dart
        ├── kds_screen.dart
        ├── menu_availability_screen.dart
        ├── refund_screen.dart
        ├── shift_close_screen.dart
        └── providers/
            ├── current_tablet_venue_provider.dart
            ├── venue_active_sessions_provider.dart
            ├── venue_orders_stream_provider.dart
            ├── venue_pending_bites_provider.dart
            └── current_shift_provider.dart
```

---

## 14. Acceptance Tests

```
TEST 1 — Tablet login
  1. Fresh staff app install on tablet
  2. Tablet login screen
  3. Enter venue ID + tablet password (test creds)
  4. Auth via Supabase, lands on staff home
  5. Tablet session persists across app kills

TEST 2 — PIN entry on action
  1. From home, tap "Scan QR"
  2. PIN sheet appears
  3. Enter wrong PIN → error, sheet stays open
  4. Enter correct PIN → sheet closes, scanner opens
  5. staff.last_pin_used_at updated

TEST 3 — Scan QR end-to-end
  1. Customer app: start session → QR generated
  2. Staff app: scan QR
  3. verify-session-qr Edge Function (Session 13 stub for now) marks nonce used
  4. Success screen shows family + child + duration
  5. sessions row already has status='active' (created at session_create)
  6. Audit log entry created

TEST 4 — Manual session
  1. Tap "Manual session" → PIN sheet → enter PIN
  2. Enter parent phone +919876543210
  3. Look up → family details + children + wallet shown
  4. Pick child, 1hr, wallet payment
  5. Tap "Start session ₹800"
  6. session_create fires with p_staff_pin_id
  7. Wallet debited, session created
  8. Customer app sees new active session in their Home tab

TEST 5 — Force close grace session
  1. Session in grace state
  2. Active sessions screen shows yellow card
  3. Tap "Force close" → confirmation
  4. session_force_close fires, status='completed'
  5. Customer app updates within 5s

TEST 6 — Distribute Healthy Bite
  1. Session has healthy_bite_earned=true, healthy_bite_distributed=false
  2. Healthy Bite screen shows pending claim
  3. Tap "Distribute card" → PIN
  4. healthy_bite_distribute RPC fires
  5. hero_card_collection row created
  6. Customer notification fires
  7. session.healthy_bite_distributed=true

TEST 7 — KDS happy path
  1. Customer places order → status='pending'
  2. Staff KDS Pending tab shows order
  3. Tap "Mark preparing" → status='preparing'
  4. Order moves to Preparing tab
  5. Customer's order tracking screen updates within 5s
  6. Repeat to "ready" then "served"

TEST 8 — Audio chime on new order (if enabled)
  1. KDS open
  2. New order arrives via Realtime
  3. Soft chime plays once
  4. Order appears with subtle animation

TEST 9 — Toggle menu availability
  1. Menu availability screen
  2. Toggle Croissant to OFF → PIN sheet
  3. Verify PIN → menu_items.is_available = false
  4. Customer app menu updates, "Sold out" badge appears

TEST 10 — Staff refund ≤₹500
  1. Refund screen
  2. Look up family, pick a transaction
  3. Amount: ₹400, reason: "wrong order"
  4. Wallet destination, issue refund
  5. PIN check
  6. RPC succeeds, status='completed'
  7. Customer wallet credited immediately
  8. Customer notification

TEST 11 — Staff refund >₹500 escalation
  1. Same as above with amount ₹800
  2. RPC creates refund row with status='pending'
  3. Customer wallet NOT credited yet
  4. Admin web shows pending refund (Session 11)

TEST 12 — End-of-shift reconciliation
  1. Tap End shift CTA
  2. Reconcile screen shows expected cash from txns
  3. Counted: ₹4,200, expected: ₹4,250
  4. Discrepancy: -₹50
  5. Notes: "Looking into it"
  6. Tap Close shift → PIN
  7. shift_close fires, shift_logs row updated
  8. Discrepancy < ₹100 → no admin alert
  9. Audit log entry per PIN
```

---

## 15. Open Items for Founder

- [ ] Decide tablet password rotation cadence (suggested: every 6 months)
- [ ] Confirm staff PIN policy (4 digits, no repeats? Random assigned by admin?)
- [ ] Approve KDS audio cue (yes/no, which sound)
- [ ] Decide if cash refund destination is supported (currently spec assumes wallet/razorpay only)
- [ ] Confirm staff cap of ₹500 for refunds (or different threshold)
- [ ] Decide if multiple tablets per venue are allowed (yes — schema supports it)
- [ ] Approve "Manual session" UX vs. "Self check-in" alternative (currently manual via staff)
- [ ] Decide what happens to QR if scanned twice (currently rejected as nonce already used)

---

## What's NOT in this session

- Admin web app (Session 11)
- Birthday photo capture (REMOVED by decision)
- Edge Function: verify-session-qr (Session 13)
- Edge Function: razorpay-webhook (Session 13)
- Tablet provisioning UI (admin web in Session 11)
