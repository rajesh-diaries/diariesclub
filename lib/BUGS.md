# BUGS

Running log of post-merge bugs. New entries at the top.

---

## BUG-003: Admin read-only impersonation deferred (DEFERRED v1.1)

- Discovered: 2026-05-05 during Session 13 planning
- Symptom: admin web has no way to view a customer's app from their
  perspective; support questions require direct DB queries from admin
  web's customers screen.
- Reason for deferral: building only the `admin-impersonate-token`
  Edge Function is unsafe — without a customer-side guard
  (`is_impersonation` JWT-claim detection + global write block) the
  short-lived token grants real session privileges. Building both ends
  in one session adds ~1h that we'd rather sink into v1.0-critical
  Edge Functions.
- v1.1 plan:
  1. Build `admin-impersonate-token` Edge Function. JWT signed with
     `IMPERSONATION_JWT_SECRET` (already generated, in 1Password).
  2. Customer app reads JWT claim `is_impersonation` on session
     resumption; if true:
     - Show a yellow banner at the top of every screen
     - Block all non-GET Supabase operations (wallet, sessions,
       reflection, birthday — every mutation surface)
     - Token expiry (5 min) re-prompts via /auth/phone
  3. Audit log entry on each impersonation use with admin_id +
     family_id + duration.
- Status: Deferred to v1.1.
- Workaround until then: admin web's Customers screen surfaces enough
  of the customer state (wallet history, sessions, orders, birthdays)
  for most support cases.

---

## BUG-002: Unsigned QR — forgery risk (DEFERRED v1.1)

- Discovered: 2026-05-05 during Session 13 planning
- Symptom: customer's session_qr_screen emits a base64-encoded JSON
  payload (not a signed JWT). Anyone with a valid `session_id` UUID
  can fabricate a QR and trick staff into marking it scanned.
- Mitigation today:
  - `staff_scanned_at` column on sessions enforces single-use scan
  - Venue scoping in `qr_scan_validate` RPC blocks cross-venue replay
  - Staff visually verify the customer + child before scanning
- Acceptable risk for: friends-and-family beta, early launch
- Not acceptable for: mass launch with significant customer volume
  where staff can't recognise every parent
- v1.1 plan:
  1. Build `generate-session-qr` Edge Function. Mints a signed JWT
     (HMAC-SHA256 with `QR_SIGNING_KEY`) including a one-time-use
     nonce inserted into `qr_nonces`.
  2. Build `verify-session-qr` Edge Function. Verifies signature,
     consumes nonce, returns session metadata to staff app.
  3. Update `lib/features/sessions/session_qr_screen.dart` (customer)
     to call `generate-session-qr` instead of base64-encoding.
  4. Update `lib/staff/qr_scanner_screen.dart` (staff) to call
     `verify-session-qr` instead of `qr_scan_validate` RPC.
  5. Deprecate `qr_scan_validate` RPC (keep for backwards-compat one
     release, then drop).
- Status: Deferred to v1.1.

---

## BUG-001: dart:io Platform usage breaks web build (FIXED)

- Discovered: 2026-05-04 post-Session 10
- Symptom: splash screen hangs forever
- Fix: kIsWeb + defaultTargetPlatform pattern
- Status: Fixed

### Files changed

- `lib/core/providers/app_version_provider.dart` — dropped `dart:io`,
  added `kIsWeb` early-return that short-circuits the version check to
  `upToDate` (web has no app store), used `defaultTargetPlatform` to
  pick the venue_config column on mobile.
- `lib/features/force_update/force_update_screen.dart` — same swap;
  store-URL button gated through a private `_isIOS()` helper. Web
  visitors who somehow hit this screen now get the Play Store URL as a
  sensible fallback (shouldn't happen because the version check exits
  before reaching this screen on web).

### Pattern to use going forward

```dart
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
```

Never `import 'dart:io'` for Platform checks — only acceptable use of
`dart:io` in the Flutter codebase is `File` for path-based bytes, and
even that breaks on web (see follow-ups below).

### Follow-ups (not yet broken on web, same anti-pattern)

These files still import `dart:io` for `File` (image picker results).
They don't crash splash, but adding/editing a child photo from Chrome
will fail. Web fix is `XFile` + `await xfile.readAsBytes()`:

- `lib/features/profile/edit_child_screen.dart`
- `lib/features/profile/add_child_screen.dart`
- `lib/features/onboarding/child_details_screen.dart`
