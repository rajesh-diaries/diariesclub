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

### FEATURE-001 + FEATURE-002 interaction (CLARIFIED 2026-05-05)

The birthday wish on DOB is a UNIVERSAL brand commitment and is NOT gated by FEATURE-002's `birthday_interest_state`. The two features serve different concerns:

- **'Not this year'** (FEATURE-002) → commercial interest in booking a party. Silences the funnel (journey-cron, sales reminders).
- **Birthday wish** (FEATURE-001) → brand love. Universal — fires for every active child on their DOB regardless of interest state.

| State | Journey nudges | Sales reminders | Wish on DOB |
|---|---|---|---|
| `birthday_interest_state='interested'` | ✓ | ✓ | ✓ |
| `birthday_interest_state='not_this_year'` | ✗ | ✗ | **✓** |
| `notification_preferences.birthday_wish_enabled=false` | (per FEATURE-002 state above) | (per FEATURE-002 state above) | ✗ |

The only opt-out path for the wish itself is the per-family toggle in Profile → Notifications.

The warm decline modal on the discovery page deliberately does NOT mention the wish — the wish is a delightful surprise on the day, and foreshadowing it would defeat the purpose. Customers who explicitly want to opt out can do so from the existing settings toggle.

The `child-birthday-wishes-cron` Edge Function does NOT filter on `birthday_interest_state` — only on `notification_preferences.birthday_wish_enabled`. A header comment in the function documents this.

---


## FEATURE-001: Universal child birthday wishes (SHIPPED — Phase 3c)
- Status: customer-facing UI shipped. Schema (0020) + cron (Phase 2) live. Notifications settings screen now has "Birthday wishes for my children" toggle backed by `families.notification_preferences.birthday_wish_enabled`. Per-child toggle remains v1.1 deferral.
- Universal-by-design: NOT gated by FEATURE-002's `birthday_interest_state`. See "FEATURE-001 + FEATURE-002 interaction" section above for the full matrix. The only opt-out is the family-level toggle in Profile → Notifications.
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

## FEATURE-002: Birthday interest opt-out (SHIPPED — Phase 3b)
- Status: customer-facing UI shipped. Schema (0021), RPC (`family_set_birthday_interest`), cron filter (birthday-journey-cron skips 'not_this_year') all live. Discovery page renders the radio card; "Not this year" triggers the warm decline modal.
- Decline-modal copy revised 2026-05-05: deliberately silent on the universal birthday wish (FEATURE-001) so it remains a surprise. The wish-mention lines were removed; only the warm acknowledgement and the two CTAs remain. See the "FEATURE-001 + FEATURE-002 interaction" clarification above for the full design rationale.
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

## BUG-018: Smart birthday card on home + simpler decline modal (FIXED)
- Discovered: 2026-05-05 Phase 1A web testing (FEATURE-002 follow-up)
- Severity: 🟡 IMPORTANT (UX consistency with the new opt-out model)
- App: Customer Web + Mobile
- Location: lib/features/home/widgets/birthday_card.dart, lib/features/birthday/birthday_discovery_screen.dart, supabase/migrations/0029_birthday_home_card_threshold.sql
- Two changes shipped together:
  1. **Home birthday card** — collapsed the prior multi-prompting-card behavior into ONE residual card representing the family's no-reservation state. Per-child reservation cards (interested / admin_contacted / confirmed / album) preserved unchanged.

     **Render rules:**
     - **Rich variant**: child opted-in (`birthday_interest_state='interested'`), birthday within threshold (`days_until <= venue_config.birthday_home_card_threshold_days`, default 30), AND no active reservation. Closest-upcoming such child wins. Gradient styling + "Plan the party →".
     - **Discovery variant**: no eligible "rich" child AND not all kids have active reservations. Lighter outlined card with "Explore birthday packages →". Covers: no children at all, all children opted out, all eligible birthdays past threshold.
     - **No residual card**: every child has an active reservation (their status cards cover the state — a discovery prompt would be redundant).
  2. **Decline modal** — single full-width Done button that routes to /home (replaces the previous two-button [Done] / [Browse other things to do] layout). Customer chose to opt out — give them one clear exit, don't push further engagement.
- Schema: migration 0029 adds `venue_config.birthday_home_card_threshold_days INT DEFAULT 30 CHECK BETWEEN 1 AND 365`. Default replaces the previous hardcoded 90-day prompting window.
- Status: FIXED 2026-05-05

---

## BUG-017: +30 min session extension fails, +60 min works (FIXED)
- Discovered: 2026-05-05 Phase 1A web testing
- Severity: 🟡 IMPORTANT (revenue path — every short-extend attempt failed)
- App: Customer Web + Mobile
- Location: supabase/migrations/0003_rpc_functions.sql:440 (session_extend body); lib/features/sessions/widgets/extend_session_sheet.dart
- Root cause: PostgreSQL integer division. `v_amount := session_extension_per_hour_paise * (p_duration_minutes / 60)` truncated 30/60 → 0, raised `invalid_duration`. Only +60 worked because 60/60 = 1.
- Fix applied:
  - Migration 0027 — adds `venue_config.session_extension_options` JSONB column with default `[{minutes:30,price_paise:15000,label:"+30 min"},{minutes:60,price_paise:30000,label:"+60 min"}]`. Preserves current effective prices.
  - Migration 0028 — `session_extend` v2 looks up `price_paise` from the JSONB list by `minutes`. Drops the formula entirely. Signature unchanged.
  - Client (`extend_session_sheet.dart`) renders one tile per option dynamically; falls back to the same hardcoded defaults if venue_config hasn't loaded.
  - Legacy `session_extension_per_hour_paise` column kept for back-compat with admin web's Config screen; cleanup deferred to Phase 2.
- Smoke test: spoofed auth.uid() inside BEGIN/ROLLBACK, called session_extend with both 30 and 60 — both returned `success:true` with correct amounts (₹150, ₹300). expires_at advanced 30+60=90 min as expected.
- Status: FIXED 2026-05-05. Admin can extend the option list (90, 120, etc.) via the Phase 2 admin Config UI without code changes.

---

## BUG-016: SessionQrScreen doesn't auto-dismiss after staff scan (FIXED)
- Discovered: 2026-05-05 Phase 1A web testing (during BUG-004 verification via SQL bypass)
- Severity: 🟡 IMPORTANT (UX confusion — customer doesn't know scan worked)
- App: Customer Web + Mobile
- Location: lib/features/sessions/session_qr_screen.dart
- Symptom: After staff scans the QR, session.status flips to 'active' on the server but the QR screen stayed visible — customer had to back-nav manually to see the running session on Home.
- Root cause: `_pollStatus` updated `_session` and stopped tickers when status left 'pending', but never navigated. The `_CancelledBody` rendered for 'cancelled_pre_scan' but required a manual tap.
- Fix applied: `_pollStatus` now detects the pending → active and pending → cancelled_pre_scan transitions, shows a celebratory ("Session started! Have fun ✨") or informational ("Session cancelled, hold released.") snackbar, waits 1.5s for the user to register the message, then `context.go('/home')`. Manual cancel path is unchanged (it already navigates).
- Status: FIXED 2026-05-05

Note: BUG-004 hold-then-charge architecture verified working in this session via SQL — wallet held ₹300, released hold, debited ₹300 cleanly; status pending → active flow correct; realtime updates flowed to home (wallet, timer). The architecture is sound; only the QR-screen auto-dismiss UX was missing, now fixed as BUG-016.

---

## BUG-015: Journey timeline shows on /birthday discovery without active reservation (FIXED)
- Fix applied: lib/features/birthday/birthday_discovery_screen.dart no longer renders `JourneyProgressBar`. Discovery is by definition the no-reservation state (page redirects to status screen when an active reservation exists). The timeline widget itself was retained and updated for BUG-009 cadence in case future surfaces reuse it.
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

## BUG-014: Back button on Birthday discovery page doesn't navigate to home (FIXED)
- Fix applied: lib/features/birthday/birthday_discovery_screen.dart back-arrow now uses `context.canPop() ? context.pop() : context.go('/home')` so direct-entry / refresh users on web aren't trapped.
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

## BUG-013: Customer cancellation flow on Reservation status screen (FIXED)
- Fix applied: lib/features/birthday/reservation_status_screen.dart kebab item is now conditional on status IN ('interested','admin_contacted'); confirmed/completed hide it. `_confirmCancel` replaced with the spec'd bottom sheet ("Cancel this reservation? You can submit again anytime." with "Keep it"/"Yes, cancel" buttons). RPC call switched to the new 1-arg signature; on success shows snackbar "Reservation cancelled" and `context.go('/birthday')` (replace stack). Old `_showWhatsAppSheet` helper removed.
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

## BUG-011: No back navigation on Reservation status screen (FIXED)
- Fix applied: lib/features/birthday/reservation_status_screen.dart AppBar now has explicit `leading: IconButton` with web-safe fallback `context.canPop() ? context.pop() : context.go('/birthday')`.
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

## BUG-009: Birthday journey timeline shows internal D-N labels (FIXED v1)
- v1 fix applied: lib/features/birthday/widgets/journey_progress_bar.dart milestones list is now `[(28,'4 weeks'),(14,'2 weeks'),(7,'1 week'),(3,'3 days'),(0,'Today!')]`. Edge function birthday-journey-cron updated to match (BUG-009 + dropped d_zero in favour of FEATURE-001's universal wishes). v1.1 admin-configurable milestones still deferred.
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

## BUG-008: PrimaryButton Row overflows by 17px on ChildDetailsScreen (FIXED)
- Fix applied: lib/core/widgets/primary_button.dart wraps the label `Text` in `Flexible` with `overflow: TextOverflow.ellipsis`. Long labels truncate with ellipsis instead of overflowing; short labels behave as before.
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

## BUG-007: "Form submission canceled because form is not connected" warning (FIXED)
- Fix applied: lib/features/auth/otp_verify_screen.dart `_verify()` now early-returns `if (_isVerifying) return;`. Root cause was paste handler + per-box completion both calling `_verify` in the same frame; the second HTTP submit was being aborted, which is what triggers the browser warning.
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

## BUG-004: Session starts + wallet deducted before staff QR scan (FIXED)
- Status: shipped end-to-end. DB layer: wallets.held_paise + sessions.status extended (0022); session_create v2 holds instead of debits, qr_scan_validate v2 converts hold to debit, session_cancel_pending releases (0023). Edge layer: session-autocancel-pending-cron sweeps every minute (Phase 2). UI layer: SessionQrScreen now switches on status — pending shows "Auto-cancels in MM:SS" + cancel button, active stays as before, cancelled_pre_scan shows the released-hold confirmation. Countdown derives deadline from server-stamped `created_at`; client clock skew only affects the visual timer, not money math.
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
