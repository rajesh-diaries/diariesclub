# BUGS

Running log of post-merge bugs. New entries at the top.

---

# Phase 1A: Customer App Web Testing
Started: 2026-05-05

For each bug, use this format:

```
## BUG-XXX: <short description> (OPEN/FIXED/DEFERRED)
- Discovered: 2026-05-05 Phase 1A web testing
- Severity: 🔴 BLOCKER / 🟡 IMPORTANT / 🟢 POLISH
- App: Customer Web
- Location: <screen + URL/path>
- Steps to reproduce: <numbered>
- Expected: <what should happen>
- Actual: <what actually happens>
- Notes: <web-specific quirks or context>
```

## Features (planned, build in fix-batch)

## FEATURE-001: Universal child birthday wishes (DECIDED — build in fix-batch)
- Discovered: 2026-05-05 Phase 1A founder request
- Severity: 🟢 BRAND FEATURE (high-impact differentiator)
- App: Customer notification system + new cron
- Concept: Wish every active child in DB on their actual DOB, regardless of whether family booked a party with us. Reinforces brand love + family-feel.

### Two flavors based on context
- Celebrating with us today (confirmed/completed birthday_reservation): "Happy birthday [Child]! 🎂 Thank you for celebrating with your Play Diaries family today. May your day be filled with joy ✨"
- Not celebrating with us: "Happy birthday [Child]! 🎂 Wishing you joy and lots of laughter today, from your Play Diaries family ✨"

### Schema
- venue_config.child_birthday_wish_enabled BOOLEAN DEFAULT TRUE
- venue_config.child_birthday_wish_time TIME DEFAULT '00:30 UTC' (06:00 IST)
- venue_config.child_birthday_wish_copy_celebrating TEXT (configurable)
- venue_config.child_birthday_wish_copy_default TEXT (configurable)
- notification_preferences.birthday_wish_enabled BOOLEAN DEFAULT TRUE (per family)
- New table child_birthday_wishes_sent (idempotency + audit):
  - id UUID PRIMARY KEY
  - child_id UUID REFERENCES children(id)
  - year INTEGER
  - sent_at TIMESTAMPTZ
  - was_celebrating BOOLEAN
  - channel TEXT
  - UNIQUE(child_id, year)

### Edge Function: child-birthday-wishes
- Scheduled daily 00:30 UTC via pg_cron
- Selects active children where MONTH(dob)=MONTH(today) AND DAY(dob)=DAY(today)
- Filters: family.is_walk_in=FALSE, prefs.birthday_wish_enabled=TRUE
- Filters: family inactive >6 months → skip; child created <30 days ago → skip
- Idempotency: skip if child_birthday_wishes_sent row exists for this child + year
- Branches: if confirmed/completed birthday_reservation today → celebrating copy; else default copy
- Sends both push (FCM) and SMS (MSG91)
- Inserts row into child_birthday_wishes_sent
- Audit logs each wish

### Customer settings
- Profile → Notifications: per-family "Birthday wishes for my children" toggle
- (per-child toggle deferred to v1.1)

### Estimated: 2.5 hours
### Status: DECIDED, applies in fix-batch phase
### Priority: HIGH (brand differentiator at launch)

---

## FEATURE-002: Birthday interest opt-out (DECIDED — build in fix-batch)
- Discovered: 2026-05-05 Phase 1A founder request
- Severity: 🟢 PRODUCT FEATURE (UX clarity + brand respect)
- App: Customer Web + Mobile + birthday cron systems
- Concept: Let customer self-declare interest level so we don't push birthday content to disengaged families.

### Two states (per child)
- 'interested' (default) — full notification cadence applies
- 'not_this_year' — silence ALL birthday content (no journey, no sales reminders)
  - EXCEPT: birthday wish on actual DOB still fires (FEATURE-001) unless separately disabled

### UI on birthday discovery page
Card at top of page:

  "Tell us about [Child]'s birthday"

  ◉ Yes, we'd love to celebrate here  (default)
  ○ Not this year, thanks

When customer taps "Not this year":
- Save state: birthday_interest_state = 'not_this_year'
- Show warm confirmation modal:

  "Got it. Whatever you celebrate with this year, [Child] is still part of our Play Diaries family.

  We'll just send a happy birthday wish on the day 🎂
  (you can turn that off in Settings too if you'd like)

  [Done]   [Browse other things to do]"

"Browse other things to do" CTA routes to home or cafe.

### Schema
- ALTER TABLE children ADD COLUMN birthday_interest_state TEXT
  CHECK (birthday_interest_state IN ('interested', 'not_this_year'))
  DEFAULT 'interested'
- ALTER TABLE children ADD COLUMN birthday_interest_updated_at TIMESTAMPTZ

### RPC
- family_set_birthday_interest(p_child_id, p_interest_state)

### Cron filter updates
- birthday-journey-cron: skip kids with 'not_this_year'
- child-birthday-wishes-cron: STILL fires for 'not_this_year' (separate per-child wish toggle handles that)

### Settings UI (Profile → Notifications)
- Per-child toggle: "Birthday content for [Child]"
- Per-child toggle: "Birthday wish for [Child]" (separate, defaults ON)

### Estimated: 1 hour
### Status: DECIDED, applies in fix-batch phase

---

## BUG-015: Journey timeline shows on /birthday discovery without active reservation (OPEN)
- Discovered: 2026-05-05 Phase 1A web testing
- Severity: 🟡 IMPORTANT (UX confusion + product clarity)
- App: Customer Web + Mobile
- Location: BirthdayDiscoveryScreen
- Symptom: Journey timeline (D-N progress dots) renders even when customer has NOT booked a party
- Current behavior: Shows progress based on child.dob countdown
- Expected: Journey timeline should ONLY show after status='confirmed' (paid reservation)
- Why this is wrong:
  - Customer hasn't engaged with birthday product yet
  - Showing "21 days to go" with progress dots implies they have a reservation
  - Confusing for customers who chose "Not interested" or didn't book
- Fix: Only render timeline if customer has an active reservation for this child. Otherwise just show "ssfdfo's birthday — 21 days to go" header without timeline OR a different "Plan ahead" CTA.

---

## BUG-014: Back button on Birthday discovery page doesn't navigate to home (OPEN)
- Discovered: 2026-05-05 Phase 1A web testing
- Severity: 🟡 IMPORTANT (UX trap — customer feels stuck)
- App: Customer Web + Mobile
- Location: BirthdayDiscoveryScreen at /birthday
- Steps to reproduce:
  1. From home, tap birthday card
  2. Land on /birthday discovery page
  3. Tap back arrow (top-left)
  4. Nothing happens OR navigates to wrong place (verify which)
- Expected: Back to home (/)
- Actual: TBD — need to verify exact behavior (no nav OR wrong route)
- Likely cause: GoRouter pop logic — if /birthday was opened directly (not via push from /home), there's nothing to pop to. Need to check if AppBar uses Navigator.pop OR context.go('/')
- Fix: Use context.go('/') for back button instead of context.pop() OR ensure home is always in the route stack

---

## BUG-013: Customer cancellation flow on Reservation status screen (OPEN — fix-batch)
- Discovered: 2026-05-05 Phase 1A web testing
- Severity: 🟡 IMPORTANT (customer needs self-serve cancellation pre-confirm)
- App: Customer Web + Mobile
- Location: lib/features/birthday/reservation_status_screen.dart — kebab menu (⋯) in AppBar
- Spec:
  - Kebab menu shows "Cancel reservation" ONLY if status IN ('interested', 'contacted')
  - For status='confirmed' or 'completed': HIDE cancel option (admin-only refund flow handles cancellations post-payment)
  - Tap "Cancel reservation" → bottom sheet:
    - Title: "Cancel this reservation?"
    - Body: "You can submit again anytime."
    - Buttons: "Keep it" (left, secondary) / "Yes, cancel" (right, primary destructive)
  - "Yes, cancel" calls birthday_reservation_cancel RPC
    - If RPC doesn't exist: write it. SECURITY DEFINER, idempotent, audit-logged.
    - Sets status='cancelled_by_customer', cancelled_at=now(), cancelled_reason='customer_initiated'
    - Returns updated reservation row
  - Customer app shows snackbar: "Reservation cancelled"
  - Routes back to /birthday discovery (replace stack, not push)
  - v1 omits "why are you cancelling?" survey — defer to v1.1
  - v1 omits cancellation-window restrictions — admin handles edge cases manually
- Status: OPEN — applies in fix-batch

---

## BUG-011: No back navigation on Reservation status screen (OPEN)
- Discovered: 2026-05-05 Phase 1A web testing
- Severity: 🟡 IMPORTANT (UX trap — customer cannot navigate back from reservation status)
- App: Customer Web + Mobile
- Location: BirthdayReservationStatusScreen at /birthday/reservations/[id]
- Symptom: AppBar shows "Your reservation" title + kebab menu (⋯) on right but NO back arrow on left
- Steps to reproduce:
  1. Submit a birthday reservation successfully
  2. Land on the status screen
  3. Try to navigate away — no back button visible
  4. Forced to use browser back button (web) or system back (mobile)
- Expected: Standard back arrow on left of AppBar that pops to /birthday or /home
- Actual: No back navigation; user is stuck
- Notes:
  - Likely AppBar has automaticallyImplyLeading: false OR was pushed via a route that loses back stack
  - Could be intentional but is bad UX
- Fix: ensure AppBar has back arrow that routes to /birthday discovery OR home
- Status: OPEN

---

## BUG-010: Birthday reservation submit fails — CHECK constraint rejects 'manual' (FIXED)
- Discovered: 2026-05-05 Phase 1A web testing
- Severity: 🔴 BLOCKER (revenue-critical — birthday is biggest lever)
- App: Customer Web (also affected mobile — server-side rejection)
- Location:
  - Constraint: supabase/migrations/0001_initial_schema.sql:687–691 (`birthday_reservations_triggered_by_check`)
  - RPC default: supabase/migrations/0014_birthday_funnel.sql:151 (`p_triggered_by TEXT DEFAULT 'manual'`)
  - Client fallback: lib/features/birthday/package_detail_screen.dart:117 (`widget.triggeredBy ?? 'manual'`)
- Symptom: Reserve interest submit failed with generic "Couldn't submit. Please try again." Surfaced via debugPrint added during diagnosis: `PostgrestException code=23514 message="new row for relation 'birthday_reservations' violates check constraint 'birthday_reservations_triggered_by_check'"`
- Root cause: CHECK constraint allowed 9 values (`home_card`, `day_minus_90/60/30/14/7/3`, `hero_progression`, `manual_admin`) but NOT `'manual'`. The 0014 RPC default and the client fallback both send `'manual'` (semantically: "user opened the app and reserved without arriving from a specific funnel touchpoint"). Constraint wasn't updated when 0014 introduced `'manual'` as the intended app-default.
- Fix applied (Option 1): supabase/migrations/0019_birthday_triggered_by_manual.sql — drops the old constraint, re-adds with `'manual'` appended. No client change needed. Verified in DB post-apply: constraint definition now includes `'manual'`.
- Status: FIXED 2026-05-05

---

## BUG-009: Birthday journey timeline shows internal D-N labels (DECIDED, SPLIT)
- Discovered: 2026-05-05 Phase 1A web testing
- Severity: 🟡 IMPORTANT
- App: Customer Web + Mobile + Admin Web
- Location: Birthday reservation status screen — JOURNEY timeline; birthday-journey-cron Edge Function

### v1 fix (apply in fix-batch — 30 min)
- Change default D-N list from [90, 60, 30, 14, 7, 3, 1, 0] to [28, 14, 7, 3, 0]
- Update timeline widget labels:
  - 28 → "4 weeks"
  - 14 → "2 weeks"
  - 7 → "1 week"
  - 3 → "3 days"
  - 0 → "Today!"
- Update birthday-journey-cron to use new day list
- Update notification copy templates accordingly

### v1.1 followup (post-launch — 4-5 hours)
Make milestones admin-configurable via venue_config.birthday_journey_milestones JSONB.

### Verification notes (2026-05-05 retest)
- Timeline labels still show old "D-90 / D-60 / D-30 / D-14 / D-7 / Day 0" — expected per deferred status. Will be replaced in fix-batch with new [28, 14, 7, 3, 0] cadence.
- Timeline only renders 6 of the 8 hardcoded milestones. Could be deliberate UI cap or a rendering bug — verify when applying the fix-batch cadence change.

Status: v1 fix DECIDED, applies in fix-batch. v1.1 deferred.

---

## BUG-008: PrimaryButton Row overflows by 17px on ChildDetailsScreen (OPEN)
- Discovered: 2026-05-05 Phase 1A web testing
- Severity: 🟢 POLISH
- App: Customer Web (likely also affects mobile narrow screens)
- Location: lib/core/widgets/primary_button.dart:37 — the Row inside button
- Symptom: RenderFlex overflowed by 17 pixels on the right (yellow stripe in dev mode, clipping in prod)
- Steps to reproduce:
  1. Onboarding → ChildDetailsScreen
  2. Open Chrome DevTools Console
  3. See exception
- Expected: Button content fits available width
- Actual: Button content (icon + label?) is 17px too wide
- Root cause likely: button label text doesn't have Flexible/Expanded wrapper, causing overflow on narrow widths
- Fix: wrap text widget in Flexible OR ellipsize OR reduce icon padding

---

## BUG-007: "Form submission canceled because form is not connected" warning (OPEN)
- Discovered: 2026-05-05 Phase 1A web testing
- Severity: 🟢 POLISH (not visible to user, but indicates lifecycle bug)
- App: Customer Web
- Location: OtpVerifyScreen → submit handler
- Steps to reproduce:
  1. Sign in, enter phone, tap Send OTP
  2. Type OTP 123456
  3. Either tap submit OR let auto-submit fire
  4. Console shows yellow warning twice
- Expected: No warnings — form should be connected when submission happens
- Actual: Warning fires twice, suggesting double-submit or widget-disposal race
- Notes:
  - User-facing impact unclear — onboarding still progresses
  - Root cause: likely auto-submit on 6th digit + manual submit firing simultaneously, OR navigation pop happening before form completes
  - Web-specific HTML form behavior, not seen on native

---

## BUG-006: Child photo upload fails on web — dart:io File on web (FIXED)
- Discovered: 2026-05-05 Phase 1A web testing
- Severity: 🟡 IMPORTANT (blocked photo flow on web; mobile unaffected)
- App: Customer Web (3 screens)
- Location:
  - lib/features/onboarding/child_details_screen.dart
  - lib/features/profile/add_child_screen.dart
  - lib/features/profile/edit_child_screen.dart
- Root cause: dart:io File() doesn't exist on web; XFile.path returns blob URL not filesystem path
- Fix applied: replaced `File(picked.path).readAsBytes()` with `picked.readAsBytes()` (XFile has cross-platform readAsBytes); removed `import 'dart:io';`
- Same anti-pattern as BUG-001 (Platform usage)
- Status: FIXED 2026-05-05

---

## BUG-005: Phone submit button missing loading spinner (FIXED)
- Discovered: 2026-05-05 Phase 1A web testing
- Severity: 🟢 POLISH (UX clarity)
- App: Customer Web
- Location: lib/features/auth/phone_entry_screen.dart:76
- Symptom: Tapping "Send OTP" gave no visual feedback; users could double-tap
- Fix applied: spinner shown during async OTP send call
- Status: FIXED in code; documented for traceability

---

## BUG-004: Session starts + wallet deducted before staff QR scan (DECIDED)
- Resolution: Option 2 — Switch to hold-then-charge architecture
- Implementation plan (defer to fix-batch phase):
  1. New session status: 'pending' (already exists, repurpose)
  2. session_create creates session in 'pending' state with wallet HOLD (not debit)
     - Add wallet_holds table + new column wallets.held_paise
     - Held amount cannot be re-spent until released or converted
  3. qr_scan_validate flips status pending → active + converts hold to debit
     - Existing wallet_transactions row is finalized at this moment
  4. New RPC session_cancel_pending — auto-callable by client (15min timeout) or manual
     - Releases hold, no debit
     - Updates session status to 'cancelled_pre_scan'
  5. Cron: auto-cancel pending sessions older than 15 minutes
  6. New venue_config.session_pre_scan_timeout_minutes (default 15)
  7. UI: SessionQrScreen shows countdown with "Auto-cancels in X:XX"
- Estimated effort: 3-4 hours including migration + RPCs + UI changes
- Status: DEFERRED until fix-batch phase post-Phase 1 testing

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
