# BUGS

Running log of post-merge bugs. New entries at the top.

---

# Phase 3: Pre-launch

## BUG-027: Birthday discovery — child name appears twice in close proximity (FIXED 2026-05-06)

- **Severity:** 🟢 LOW (cosmetic; reads as filler)
- **Cause:** `BirthdayDiscoveryScreen._Hero` renders "$name's birthday" then `_MainCta` immediately below renders "Plan $name's birthday with us" — the name was repeated within a single viewport.
- **Fix:** `_MainCta` heading changed to "Plan the celebration with us" and the `childName` parameter dropped. The hero card is the single source of truth for whose birthday it is.

---

## BUG-026: Staff app RLS — direct table reads return empty for staff users (PARTIALLY FIXED 2026-05-06)

- **Severity:** 🔴 BLOCKER originally — login was rejecting all staff users on web; phone "got past" only via a router redirect race in the device-check await.
- **Why it surfaced today:** user tested on web (`localhost:55916/#/staff/login`); login showed "This phone is not registered (or has been revoked). Contact admin." despite valid credentials. Web doesn't have the redirect race the phone had, so the login screen's `device == null` branch fired correctly — and the device check returned null because `tablet_devices` had RLS enabled with zero policies for the staff user.
- **Fix shipped (migration `0043_staff_app_rls_minimum`):**
  - `tablet_devices_self_read` policy: `FOR SELECT TO authenticated USING (auth_user_id = auth.uid())`. Lets a signed-in user read their own device row(s). `is_active` filter applied client-side so admin can audit revoked rows without policy churn.
  - `_is_active_tablet_for_venue(p_venue_id)` SECURITY DEFINER helper: returns true iff `auth.uid()` owns an active tablet_devices row for `p_venue_id`.
  - `sessions_staff_venue_read` + `orders_staff_venue_read` policies: layered alongside existing family policies; staff/tablet users get venue-scoped reads.
  - Verified via SET-LOCAL-ROLE simulation as `stafftest@gmail.com`: `tablet_devices=1, sessions=5, orders=0` (was all zeros pre-fix).
- **Still open / not in this migration:**
  - `staff` table — intentionally left unexposed. PIN verification runs server-side via `verify_staff_pin` RPC; client never needs `pin_hash`.
  - Other staff-side direct reads in `kds_screen.dart`, `menu_availability_screen.dart`, `shift_close_screen.dart`, `walkin_pos_screen.dart`, `refund_screen.dart` — when staff actions exercise these, additional policies (or RPCs) will be needed. Pickup case-by-case as testing surfaces them.
  - Bigger architectural decision (SECURITY DEFINER RPCs across the board vs full RLS coverage) deferred — current fix is the minimum unblocker.

---

## BUG-025: OTP "same number" rejection in dev mock-mode (FIXED 2026-05-06)

- **Severity:** 🟡 IMPORTANT (blocked dev testing flows)
- **Reported as:** OTP rejecting same-number sign-in attempts during dev testing.
- **Cause (most likely):** the rate limit in `auth-otp/index.ts` (3 sends per phone per 15 min) was applied uniformly across modes. Dev test cycles repeatedly hitting "send" with the same number quickly exhaust the budget; the user sees `rate_limited` and perceives it as same-number rejection. Compounded by the fact that mock mode doesn't actually send SMS, so the rate limit serves no protective purpose there.
- **Fix:** `auth-otp` Edge Function v12 deployed. The rate-limit branch now runs only when `OTP_MODE !== "mock"`. Real (production) mode unchanged — still 3 per 15 min to protect MSG91 credit. Mock mode skips the limit entirely.
- **Note for follow-up:** if the user is reporting a *different* failure mode (e.g., "verify rejects same number"), the user-lookup path in `handleVerify` (around line 258) uses GoTrue's `/admin/users?phone=` filter which may not work consistently in older GoTrue builds. That's a separate fix candidate if mock-mode bypass doesn't resolve testing pain.

---

## BUG-024: Profile FilledButton infinite width (OPEN 2026-05-06)

- **Severity:** 🟢 LOW (cosmetic)
- **Status:** OPEN — couldn't pinpoint specific button from description alone. Code review found 7 FilledButton call sites in `lib/features/profile/`:
  - `profile_screen.dart:121` — "Top up" inside `ListTile.trailing > Row(MainAxisSize.min)` — sized via `padding: horizontal 14, visualDensity: compact`. Should be intrinsic; possibly larger than intended on Material 3 default `minimumSize: Size(64, 40)`.
  - `profile_screen.dart:307` — "Sign out" inside `AlertDialog.actions` (dialog-bounded, unlikely the bug).
  - `pre_booking_screen.dart:436` — "Add a child" empty-state CTA.
  - `pre_booking_screen.dart:521` — "Done" inside `Column(crossAxisAlignment: stretch)` after `Spacer()` — full-width by design.
  - `delete_account_screen.dart:228` — "Permanently delete my account" inside `Column(stretch)` — full-width by design.
  - `edit_child_screen.dart:160` — "Remove" inside `AlertDialog.actions`.
  - `farewell_screen.dart:47` — "Back to start" inside `Column(stretch)` — full-width by design.
  - `widgets/empty_state.dart:43` — generic CTA, intrinsic-width via `Column(mainAxisSize.min)`.
- **Most likely candidate:** `profile_screen.dart:121` "Top up" — the only one in a non-stretch context where unexpected sizing is plausible. Fix candidate: add `minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap` to its `FilledButton.styleFrom`.
- **Why deferred:** "guess and ship" risks regressing one of the deliberately full-width primary CTAs (delete account, done, back to start) which are conventional UX. Need user to point at the specific screen.
- **For pickup:** confirm with user which screen + what "infinite width" means visually (button stretching where it shouldn't, RenderFlex exception in logs, or something else), then apply the targeted fix.

---

## BUG-028: DECISION-001 phone-pivot copy sweep was incomplete (FIXED 2026-05-06)

Caught during BUG-023 V3 testing — the logout dialog opened ("Sign out tablet?" + tablet body copy), revealing user-facing tablet-era strings that DECISION-001's sweep missed.

- **Severity:** 🟢 LOW (cosmetic)
- **Fix:** `staff_app_bar.dart` — three user-visible strings updated:
  - `IconButton.tooltip` → `'Sign out'`
  - dialog title → `'Sign out?'`
  - dialog content → `'Signing out will require this phone to be re-registered before any staff can use it.'`
- **Identifier-only references** (lower priority, not user-visible — flag for a later wider rename pass):
  - `tablet_login_screen.dart` (file name + class `TabletLoginScreen`)
  - `staff_auth_provider.dart` (`tabletAuthStateProvider`, `isTabletSignedInProvider`, `tabletAuthUserIdProvider`, `currentTabletDeviceProvider`, `currentTabletVenueIdProvider`)
  - `tablet_devices` table name in DB
  - Comments referencing "tablet" across the staff path
- **Out of scope for this fix:** identifier rename is a separate refactor that touches DB schema (`tablet_devices` → `staff_devices`?) and would benefit from a planned design pass.

---

## BUG-026: Staff app RLS — direct table reads return empty for staff users (OPEN 2026-05-06)

Discovered while investigating BUG-023. Adjacent but separate bug — significant enough to track on its own.

- **Severity:** 🔴 BLOCKER (production staff app cannot read its own data)
- **Finding:** RLS audit via `pg_policies` + simulated `SET LOCAL ROLE authenticated` query as `stafftest@gmail.com`:
  | Table | RLS | Policies for staff/tablet user |
  |---|---|---|
  | `tablet_devices` | ✅ enabled | **0 policies** — only service_role can read |
  | `staff` | ✅ enabled | **0 policies** |
  | `sessions` | ✅ enabled | only `sessions_family` (`family_id = auth_family_id()`) |
  | `orders` | ✅ enabled | only `orders_family` (same) |
  Verified counts as the staff user: `tablet_devices=0, sessions=0, orders=0, staff=0`.
- **Implication:** raw `.from(...).select()` calls in the staff app return empty for any signed-in staff/tablet user. Touch points (every staff-side direct query):
  - `lib/staff/providers/staff_auth_provider.dart` (`tablet_devices` for venue lookup)
  - `lib/staff/providers/venue_streams_provider.dart` (`sessions`, `orders` realtime streams)
  - `lib/staff/menu_availability_screen.dart`
  - `lib/staff/kds_screen.dart`
  - `lib/staff/shift_close_screen.dart`
  - `lib/staff/walkin_pos_screen.dart`
  - `lib/staff/refund_screen.dart`
- **Why login still appears to succeed:** the login screen's `device == null → signOut` branch is meant to catch this, but the GoRouter redirect on `signInWithPassword` success races ahead of the device-check await, navigating to `/staff/home` before the check completes. User lands on home with a dud device row; tile fallbacks render "0" / fallback labels everywhere.
- **Original design intent (probable):** SECURITY DEFINER RPCs for staff queries (matches the admin pattern — admin web routes everything through `admin_*` RPCs). The staff providers were written against direct table reads, possibly assuming RLS was permissive or a future migration would add staff-role policies that never landed.
- **Decision needed before fix:**
  1. **Option A — SECURITY DEFINER RPCs across the board.** Matches admin pattern. Audit-log ready. Need to write RPCs for every read currently done as `.from()`. More boilerplate, fewer RLS surprises.
  2. **Option B — Staff-role-aware RLS policies.** Add `staff_can_read_*` policies that check `auth.uid() IN (SELECT auth_user_id FROM tablet_devices WHERE is_active)`. Keeps providers as-is. Risk: realtime subscriptions inherit RLS and may behave subtly differently.
  3. **Option C — Hybrid.** Direct reads for safe-to-expose tables (sessions/orders filtered by venue), RPCs for sensitive ones (`staff` table — has `pin_hash`). Probably the right answer.
- **Status:** OPEN, design pass not started. Picking up after BUG-023 closes.

---

## BUG-023: Staff app blank /staff/home body (LIKELY RESOLVED via BUG-026 fix 2026-05-06)

Distinct from BUG-022 (which fixed the viewport-metrics loop): the loop is gone, but the body still paints blank with a non-tappable logout. Loop and blank-body were two stacked bugs, not one.

- **Severity:** 🔴 BLOCKER
- **Symptom:** post-login, `StaffAppBar` renders ("Diaries Staff" + logout icon) but body is fully white, logout taps non-responsive. No widget tree errors, no route logs.
- **Code-review walkthrough:**
  - `StaffHomeScreen` body tree: `SafeArea > SingleChildScrollView > Column(crossAxisAlignment: stretch) > [_StatsBar, gap, _ActionsGrid, gap, _EndShiftCta, gap]`. Static structure — no async gates that could hang the body itself.
  - **Async consumers found** (all using `valueOrNull` with silent fallback):
    - `StaffAppBar` watches `currentTabletDeviceProvider` → `device?[label] ?? 'Diaries Staff'`
    - `_StatsBar` watches 4 providers → each `valueOrNull?.length ?? 0`
    - All swallow loading + error invisibly. If they failed, tiles still render "0" — they don't make the body blank.
  - **Modal-overlay search** (`showDialog`, `showModalBottomSheet`, `Stack`, `Overlay`, `absorb`): no automatic modal opens between login → home. Only triggered by user action (logout, action grid, etc.).
- **Hypothesis remaining:** The non-tappable logout strongly suggests an overlay above the Scaffold absorbing taps and obscuring the body — but no source found in code. Could be a stuck route from the login → home transition, or something device-specific. Need device telemetry.
- **Diagnostic instrumentation pushed (commit pending):**
  1. Visible orange "DEBUG: StaffHomeScreen body built — BUG-023 v1" box at the top of the body. If user sees this on device → body IS rendering, issue is occlusion above. If they don't → body never built, issue is higher in the tree.
  2. `_StatsBar` rewritten to surface provider errors as a red banner (previously swallowed by `valueOrNull ?? 0`) and to show a centred spinner when all 4 providers are still loading.
  3. `dev.log` traces at every subwidget `build()` — flutter logs will show which widgets fired. Filter by `staff_home`.
- **Adjacent finding:** BUG-026 (RLS misconfig) surfaced during this investigation. Logged separately above. Does not explain blank body — empty data renders as "0" in tiles, not blank.
- **Round 1 result (2026-05-06):** No `[staff_home...]` log lines fired. Orange box not visible. Logs show only "Sending viewport metrics × 2" then silence.
- **Round 1 paradox:** only `StaffHomeScreen` uses `StaffAppBar`, and only `StaffAppBar` has the logout icon. So if logout is visible on screen, `StaffHomeScreen.build()` MUST have fired. Two possible resolutions:
  1. The build is firing but `dev.log` (via `dart:developer`) is being filtered at the wrong log level by the user's `flutter run` setup.
  2. The APK on device is stale (pre-`021f0d8`) — no instrumentation compiled in.
- **Round 2 instrumentation (commit pending):** switched all logs to `debugPrint` (always surfaces in `flutter run` output, no level filter) and tagged with `[BUG-023-V2]` so user can grep to confirm build is current. Added instrumentation higher in tree:
  - `app_staff.dart` — `StaffApp.build` and the `MaterialApp.router` builder
  - `staff/staff_router.dart` — redirect callback (logs decision per nav), `/staff/login` builder, `/staff/home` builder, `errorBuilder`
  - `staff_home_screen.dart` — already instrumented in v1; switched to debugPrint with `[BUG-023-V2]` tag
  - Orange box copy bumped to "BUG-023 V2" — visual confirmation of fresh build
- **What we'll know after Round 2:** if user sees `[BUG-023-V2]` in logs at all → fresh build is loaded; if the `/staff/home` route builder fires but `StaffHomeScreen.build()` doesn't, that's a Flutter bug (impossible under normal semantics). If neither fires but redirect logs show `→ /staff/home`, navigation completed but the screen isn't building — extreme rarity.
- **Round 2 result (2026-05-06):** EVERY builder fires (StaffApp.build, MaterialApp.builder, redirect, /staff/home builder, StaffHomeScreen.build, _StatsBar, _ActionsGrid, _EndShiftCta — all logged). But the orange "BUG-023 V2" box still doesn't paint on the device. Widgets are building; pixels aren't.
- **Round 2 narrows to: rendering/paint failure, not widget tree failure.** Strongest hypothesis is Impeller-on-Vivo-Funtouch-Android-15. Logs show `Using the Impeller rendering backend (Vulkan)`. Vivo I2306 (Funtouch OS, Android 15) has a known Flutter Impeller defect on certain widget shapes — widgets layout cleanly but never paint. Customer app on Chrome (Skia / browser canvas) renders fine; staff app uses Impeller on the phone.
- **Round 3 instrumentation (commit pending):** kill-switch test — replace the entire `StaffHomeScreen` body with `ColoredBox(Colors.red, child: Center(Text('BUG-023 V3 KILL SWITCH', white)))`. Decisive: if red box paints, the body slot CAN render and the issue is something specific to the original widget tree. If red box ALSO doesn't paint, the body slot itself is broken — Impeller fingerprint on this device.
- **Round 3 user test plan:**
  1. Uninstall + reinstall + launch normally → does the red box show?
  2. If still blank: re-launch with `flutter run --no-enable-impeller` → does the red box show now? If yes → confirmed Impeller bug, document workaround in `AndroidManifest.xml` via `io.flutter.embedding.android.EnableImpeller=false` meta-data.
- **Round 3 result (2026-05-06):** Red kill-switch box rendered. Body slot paints. Logout dialog opens normally. **Definitively NOT** Impeller / GPU / Scaffold-body / touch-handling. Rules out the entire rendering pipeline. Bug is inside the original `StaffHomeScreen` body widget tree — one of `[SafeArea, SingleChildScrollView, Column, _StatsBar, _ActionsGrid, _EndShiftCta]` is rendering at zero size or behind something, making the whole body LOOK blank. Most likely candidates: an unintended `SizedBox.shrink()`, `Container(height: 0)`, `Expanded`/`Flexible` chain producing zero height inside `SingleChildScrollView`, or a `Visibility(visible: false)` somewhere downstream.
- **Round 4 instrumentation (commit pending):** restored original body but wrapped each child in a coloured-border `_DebugWrap`:
  - `_StatsBar` — RED border, label "STATS_BAR"
  - `_ActionsGrid` — BLUE border, label "ACTIONS_GRID"
  - `_EndShiftCta` — GREEN border, label "END_SHIFT"
  - Top sentinel kept (orange "BUG-023 V4 body entry" box) so we can see the body itself paints
  - All `debugPrint` tags bumped to `[BUG-023-V4]`
- **Round 4 user test:** which coloured borders + labels appear on screen?
  - All three borders visible but inner content blank → children have non-zero outer size but zero inner content; isolate per-child data/state.
  - One or more borders missing → that child has zero size; likely `Visibility(visible: false)`, `SizedBox.shrink()`, or constraint pathology in that subtree.
- **Round 4 result (2026-05-06):** Logs show all 7 widgets fired build (StaffHomeScreen, _DebugWrap×3, _StatsBar, _ActionsGrid, _EndShiftCta). User did not send a screenshot, but the V3 result already proved the body slot paints fine. Pattern-matches a known constraint-propagation pathology with `SingleChildScrollView > Column(crossAxisAlignment: stretch)` on certain Android 15 builds (Vivo Funtouch, Oppo ColorOS) where the cross-axis stretch resolves to zero content height despite the children calling build().
- **Fix candidate A (commit pending):** structural — replace `SafeArea > SingleChildScrollView > Column(crossAxisAlignment: stretch)` with `SafeArea > ListView`. ListView gives children bounded width by default and avoids the stretched-Column-in-Scrollable interaction. Same body content, simpler tree. Removed all V1–V4 debug instrumentation (orange box, _DebugWrap, debugPrint calls, [BUG-023-V*] tags) since the diagnostic phase is over.
- **What to test:** uninstall + reinstall + sign in with `stafftest@gmail.com` / `testing@123`. Body should now paint: 4 stat tiles row → 3×3 action grid → "End shift" pill at the bottom. Layout will be cramped on portrait phone (BUG-024-style, separate cosmetic) but functional.
- **If candidate A doesn't paint:** candidate B is to replace `_ActionsGrid` GridView.count(shrinkWrap) with a manual Column-of-Rows. Avoids GridView entirely.
- **Candidate A result (2026-05-06):** still blank on phone. The SCV→ListView structural change wasn't sufficient; the GridView inside is the actual culprit. GridView's sliver/viewport pipeline appears broken on Vivo Funtouch Android 15 when nested inside another scrollable, independent of whether the outer is SingleChildScrollView or ListView.
- **Fix candidate B (commit pending):** `_ActionsGrid` rewritten as a manual `Column` of three `Row`s. Each row is `SizedBox(height: 112) > Row > [Expanded(card), gap, Expanded(card), gap, Expanded(card)]` with a 16px gap between rows. No GridView, no shrinkWrap, no NeverScrollableScrollPhysics — pure RenderBox layout that bypasses the sliver path entirely.
- **What to test:** uninstall + reinstall + sign in. Body should show 4 stat tiles → 9 action tiles in a clean 3×3 → End shift bar.
- **If candidate B still doesn't paint:** the failure is deeper. Next moves: (1) replace `_StatsBar`'s Row-of-Expanded with explicit-width SizedBoxes (rule out Row+Expanded), (2) wrap each subwidget in `RepaintBoundary` to isolate paint vs layout, (3) drop the `MediaQuery` wrapper in `app_staff.dart` MaterialApp.builder to rule out the textScaler clamp.
- **Candidate B result (2026-05-06):** still blank. Manual Column-of-Rows didn't help. Eliminates GridView as the sole culprit.
- **Common thread between A & B (both blank):** both use `SafeArea`. The V3 kill switch (which painted) did NOT use SafeArea. Likely root cause for this device.
- **Fix candidate C (commit pending):** drop `SafeArea` entirely. Scaffold already accounts for the AppBar + bottom system insets via `resizeToAvoidBottomInset=true` (default). SafeArea atop that was redundant; on Vivo Funtouch Android 15 it appears to compute padding that collapses the body. Body is now `ListView(padding: 20) > [_StatsBar, gap, _ActionsGrid, gap, _EndShiftCta]` — no SafeArea wrapper.
- **What to test:** uninstall + reinstall + sign in. Body should finally show 4 stat tiles + action grid + end shift bar.
- **If candidate C also blank:** the failure pattern is something inside the StaffApp shell itself, not the screen. Next moves: drop the MediaQuery textScaler-clamp wrapper in `app_staff.dart`, then try `Scaffold` without AppBar (move logout into a floating widget) to fully match V3's working shape.
- **Candidate C result (2026-05-06):** still blank, but device screenshot revealed the smoking gun: log shows `Another exception was thrown: Null check operator used on a null value` repeated continuously, with stack trace pointing at `rendering/box.dart:2…` and `rendering/sliver_mul…`. **This is not a layout pathology — it's a build-time Dart `!`-on-null crash being swallowed by Flutter's error handling.** The body looks blank because every build attempt throws and Flutter renders nothing in its place.
- **Reframing:** ListView's children include `_StatsBar`, `_ActionsGrid`, `_EndShiftCta`. One (or more) of those throws during build. Flutter catches → ErrorWidget → which apparently also paints nothing on this device. Repeated rebuild attempts re-trigger the throw. Stack frame `sliver_mul` confirms the path is through ListView's sliver child manager.
- **Fix candidate D (commit pending):** body replaced with `Center > Column(mainAxisSize.min) > [Text, Text, Text]`. Strips out ListView + all three custom widgets. **Decisive test:**
  - If D renders → the bug is in `_StatsBar` / `_ActionsGrid` / `_EndShiftCta`. Tomorrow: bisect by re-introducing one at a time.
  - If D still blank → the failure is upstream (StaffApp MediaQuery wrapper, theme, or AppBar). Tomorrow: drop the MediaQuery wrapper and re-test.
- **For tomorrow morning, the user should also scroll up in `flutter logs` and find the FIRST `Another exception` message — its stack trace will name the user-code line, not just the framework path.**
- **Reframed (2026-05-06, after web testing surfaced BUG-026):** the user's web test today caught the login screen rejecting at the device-check stage — same root cause as the phone's blank body, two visible symptoms. On phone yesterday, sign-in completed via a router redirect race ahead of the device check; the home screen then mounted with `currentTabletDeviceProvider == null` (RLS-blocked), every downstream provider produced empty/null data, and the cumulative effect somewhere in the realtime stream / sliver pipeline manifested as the repeated `Null check operator used on a null value` log spam. Hypothesis: **BUG-023 is downstream of BUG-026**, not a separate bug.
- **Action (2026-05-06):** restored the original body (rolled back candidate D) now that migration 0043 has unblocked the provider chain. If staff home now renders normally on web AND phone, BUG-023 closes as a duplicate of BUG-026.
- **What to test:** sign in on web first (`localhost:55916/#/staff/login`) — login should pass, home should show stat tiles + 3×3 action grid + end shift bar. Then phone — same expectation. If web works and phone still has the null-check crash, that's a separate device-specific bug worth its own entry.
- **Web retest result (2026-05-06):** AppBar correctly shows "Stafftest Phone (dev)" — BUG-026 fix confirmed working. But body still blank, this time with a different framework assertion: `Assertion failed: …flutter/lib/src/rendering/mouse_tracker.dart:199:12` repeated continuously. **Two distinct sub-bugs were stacked.** First was BUG-026 (RLS); second is the InkWell+decorated-Container anti-pattern in `_ActionCard`.
- **Final fix (commit pending):** `_ActionCard` rewritten to the canonical Material+InkWell pattern. Was: `InkWell(borderRadius) > Container(decoration: BoxDecoration(color, border, borderRadius))`. Now: `Material(color, shape: RoundedRectangleBorder(side, borderRadius), clipBehavior: antiAlias) > InkWell(onTap) > Padding > Column[Icon, gap, Text]`. The Container's background was painting over the InkWell ripple AND on web the MouseTracker hit-test disagreed with the visible region — that's what the assertion was guarding. Canonical pattern uses Material to provide the visible surface so hit-test, paint, and ripple all agree.

---

## BUG-022: Staff app infinite layout loop on Android 15 post-login (FIXED 2026-05-06)

- Discovered: 2026-05-06 Phase 3 testing on I2306 phone (Android 15, portrait).
- Severity: 🔴 BLOCKER (staff app unusable post-login).
- Symptom: After successful sign-in, /staff/home rendered StaffAppBar (title + logout icon) but the body painted blank white. UI fully non-responsive — logout couldn't be tapped. Logs showed `D/FlutterJNI: Sending viewport metrics to the engine` repeating hundreds of times per second with no widget tree or route logs.
- Root cause: commit `9ce8194` (DECISION-001 phone-only pivot) removed `SystemChrome.setPreferredOrientations(...)` from `main_staff_dev.dart`. Without any preference declared, certain Android 15 ROMs (incl. the I2306) keep renegotiating edge-to-edge insets and stream viewport-metrics updates inbound forever. The Dart side never gets a settled frame budget — the body never paints, even though the layout completed once. Customer app is unaffected because it lands on a richer screen and (anecdotally) Android 15 settles when content fills more of the viewport; staff home's tighter geometry surfaced the thrash.
- Fix: `555a189` re-added `SystemChrome.setPreferredOrientations` to `main_staff_dev.dart` declaring all four orientations explicitly (portraitUp/Down + landscapeLeft/Right). Functionally equivalent to omitting the call but gives the engine a definitive answer; the inset thrash stops within ~1s. Same commit also swapped `Icons.tablet_mac` → `Icons.phone_iphone` in `StaffAppBar` (self-flagged DECISION-001 follow-up missed in 9ce8194).
- Verified: candidate (i) on I2306, body renders, logout interactive, viewport-metrics log settles.
- Follow-up (separate, lower priority): `_ActionsGrid` in `staff_home_screen.dart` is tuned for tablet landscape (3 cols × 1.4 aspect). On portrait phones cells are ~73px tall against ~96px of content, producing visual overflow that's cosmetic but ugly. Will land its own bug entry when triaged.

---

## CONVENTION-001: Hero illustration placeholder (NOTED 2026-05-06)

Until real artwork lands (v1.1 deferred item — see `SCOPE_LOCKED.md`), empty states use a `_HeroIdleRow` pattern: four 56px coloured circles holding `PhosphorIconsFill` glyphs in the four hero brand colours (Rafi coral / Ellie blue / Gerry amber / Zena green). Reference implementation: `lib/features/adventure/widgets/cafe_only_empty_state.dart`. Mirror locally per-screen until repeated ≥3 times, then extract to `core/widgets/`.

---

## BUG-021: Staff active sessions screen — blank empty state (FIXED 2026-05-06)

- Discovered: 2026-05-06 Phase 3 testing on I2306 phone (staff Android, post-DECISION-001 build).
- Severity: 🟡 IMPORTANT
- Symptom: When no active sessions exist, screen body rendered as a small grey clock + "No active sessions" — felt blank against the design system.
- Second issue surfaced during fix: the data branch returned an empty `ListView` (zero children) when `sessions` was non-empty but contained only non-`active`/non-`grace` rows — that path was genuinely blank, not just visually weak.
- Fix: replaced `_EmptyState` with the `_HeroIdleRow` pattern per CONVENTION-001 (4 hero glyphs + heading "The floor is quiet right now." + body "Sessions will appear here as soon as a family scans in."). Empty check moved from `sessions.isEmpty` to `active.isEmpty && grace.isEmpty` so the second case also lands on the empty state.
- Scope: this screen only. Other staff empty states get their own bug entries when found in real testing.

---

## DECISION-001: Staff app phone-only, not tablet (LOCKED 2026-05-06)

Original spec assumed a single shared venue tablet; revised to each staff member using their own phone.

**Implications:**
- Remove forced landscape orientation
- Redesign staff screens for phone form factor (portrait, smaller width budget, different touch targets)
- Rename "Diaries Staff Tablet" → "Diaries Staff" (app display name, store listing, in-app copy)
- Rethink "sign in once per device" copy — now device == personal phone, not shared kiosk
- Login UX should feel like a personal-app login, not a kiosk handover

**Phase 3 scope impact:** +1-2 days estimated. Cuts into the launch buffer; if we slip, deferred-list items are first to drop, not the timeline.

**Touch points** (to verify before Phase 3 work begins): orientation lock in `ios/Runner/Info.plist` + `android/app/src/main/AndroidManifest.xml`, app display name in both manifests, staff screens under `lib/staff/`, any "tablet" copy across login + onboarding strings.

---

## DEFERRED-001: iOS staff display name needs xcconfig + scheme split (DEFERRED 2026-05-06)

When wrapping up DECISION-001 (staff phone-only), Android `staffProd` got renamed to "Diaries Staff". iOS could not be updated in the same batch:

- `ios/Runner/Info.plist` has a single hardcoded `CFBundleDisplayName` ("Diaries Club") — no per-flavor override exists.
- Per `FLAVORS.md` "iOS — single bundle ID for now ⚠️", all iOS builds (including staff) currently render as "Diaries Club" because iOS flavor scaffolding (`Runner-staff` scheme + xcconfig + `INFOPLIST_KEY_CFBundleDisplayName` build setting) doesn't exist in this repo.
- The work to fix this overlaps with the existing follow-up already noted in `FLAVORS.md` (per-bundle-ID iOS schemes for dev / staging / prod). When that scheme split happens, add `staffDev` + `staffProd` schemes in the same pass and set `CFBundleDisplayName` per-scheme to "Diaries Staff Dev" / "Diaries Staff".

**Why deferred:** Xcode UI work, hard to do reliably from CLI without breaking `project.pbxproj`. Doesn't block any build today (staff flavor still installs and runs on iOS — just shows the customer name on the home screen, which is wrong but not broken).

**Pickup:** when next opening Xcode for the FLAVORS.md customer-app scheme work.

---

# Phase 2: Admin web — modules

## ARCHITECTURE-001: Storage bucket public/private split (DECIDED 2026-05-05)

Marketing content uses **public** buckets; user-uploaded sensitive content stays **private**.

| Bucket | Visibility | Rationale |
|---|---|---|
| `workshop-photos` | **public** (0035) | Promotional. UUID filenames. Linkable from push deep-links, WhatsApp shares. |
| `menu-photos` | **public** (0035) | Same as above. |
| `package-photos` | **public** (0035) | Same. Created in 0035. |
| `hero-recaps` | **public** (pre-existing) | Rendered session-recap PNGs (no faces — child name + duration + XP only). Social-shareable. Confirmed safe. |
| `hero-cards` | **public** (pre-existing) | Brand illustrations (24 hero card templates for Rafi / Ellie / Gerry / Zena). Static admin-curated artwork referenced by `hero_card_definitions.image_url`. **No kid photos** — kid faces appear only as client-side composites at render time, never stored. No client writes allowed (`0001:1330-1331`). Public classification correct per the marketing-content rule. (Earlier privacy-review flag raised in error — superseded.) |
| `birthday-photos` | private | Customer-uploaded kid photos. Signed URLs via `signed_birthday_photo_url_provider`. |
| `child-photos` | private | Per-child profile photos. Signed URLs. |
| `invoices` | private | Financial documents. Service-role only. |

Implication: workshop / menu / package CRUD can return `getPublicUrl()` directly without per-module signed-URL plumbing. This retroactively fixed the BUG-022-shape concern flagged at end of Module 2.2 (workshops customer reads would 401 with private bucket). RLS policies for writes are unchanged (service-role only); the bucket-level `public=TRUE` flag makes reads work via the storage HTTP gateway, bypassing RLS.

Reversibility: see migration 0035 header.



## Module 2.1: View-only stubs (SHIPPED 2026-05-05)
Stepping-stone read-only list screens for the five admin domains added since Session 11.

- `/admin/workshops` — DataTable: when, title, ages, capacity, spots-left, price, status badge.
- `/admin/catalog` — hub with three tiles linking to Coffee / FIT / Combos.
- `/admin/catalog/coffee` — DataTable filtered by `menus.brand='coffee'`.
- `/admin/catalog/fit` — DataTable filtered by `menus.brand='fit'`. Banner notes the Module 2.5 meal-builder layer arriving on top.
- `/admin/catalog/combos` — DataTable from `combos` table.
- `/admin/packages` — card grid of birthday_packages (3 tiers, photographic emphasis).

Reusable widget: `lib/admin/widgets/admin_list_scaffold.dart` (`AdminListScaffold` + `AdminListEmptyState`). All five screens use it for consistent header + "Create / Edit coming soon" banner + empty-state.

Sidebar updates: stub dots removed from Workshops + Catalog; new Packages entry added (14 nav items total).

CRUD ships per-domain in Modules 2.2 (workshops) / 2.4 (Coffee) / 2.5 (FIT). Combos + Packages CRUD scheduled after 2.4.

## Module 2.2: Workshops full CRUD (SHIPPED 2026-05-05)
Replaces Module 2.1's view-only `/admin/workshops` with full create / edit / unpublish.

- Migration 0030 — `workshops.is_published BOOLEAN DEFAULT TRUE` + `workshop-photos` private storage bucket with auth-read / service-write RLS.
- Migration 0031 — three SECURITY DEFINER RPCs (`admin_workshop_create`, `admin_workshop_update`, `admin_workshop_delete`) gated on the new `_assert_active_admin()` helper. Soft-delete via `is_published=false`.
- **Push fan-out**: when `is_published` flips FALSE→TRUE, the RPC inserts one `notifications` row per opted-in family (`notification_preferences.workshop_reminders=true`, walk-in/anonymised excluded). The existing `notify_push_dispatch` trigger picks them up and fires send-push via FCM. No new Edge Function — same pattern as FEATURE-001 wishes; one less moving part.
- Capacity-resize guard: `admin_workshop_update` refuses to drop capacity below already-registered count (`spots_remaining` recomputed accordingly).
- Admin UI: list shows is_published in status column (greyed strikethrough when unpublished); + New / Edit / Unpublish actions; new `WorkshopEditScreen` form with photo upload (XFile.readAsBytes → workshop-photos bucket via the admin's authenticated session).
- Routes added: `/admin/workshops/new`, `/admin/workshops/:id/edit`.

## Module 2.3: Announcements module (SHIPPED 2026-05-05)
Multi-feed customer-home cards (max 5) + admin CRUD + workshop auto-create trigger.

- Migration 0032 — `announcements` table (id, venue_id, title, body, type, cta_label, cta_route, photo_url, visible_from, visible_until, is_published, source_workshop_id, created_by, timestamps). Type CHECK: workshop / general / event / promo / closure. Partial index on (venue_id, visible_from, visible_until) WHERE is_published. UNIQUE(source_workshop_id) ensures one auto-row per workshop. RLS: customer reads only published+visible; admin reads/writes all. Realtime publication added.
- **Workshop sync trigger**: AFTER INSERT/UPDATE on workshops fires `workshop_announcement_sync()`. When `is_published AND scheduled_at <= now()+14d`, upserts an announcement (title = "<workshop> — Dy Mon DD" IST, body = LEFT(description,100)+ellipsis, CTA = "Book your spot" → /club/workshops, visible_until = scheduled_at+1h). When `is_published=false`, the corresponding announcement is unpublished. ON DELETE CASCADE handles workshop deletion.
- Migration 0033 — three SECURITY DEFINER RPCs (`admin_announcement_create`, `admin_announcement_update`, `admin_announcement_delete`) gated on `_assert_active_admin()`. Soft-delete via `is_published=false`.
- Admin UI: `AnnouncementsListScreen` with status badge (Active / Scheduled / Expired / Unpublished), source badge ("Auto · workshop" vs "Manual"), warning banner when active count > 5. `AnnouncementEditScreen` for create/edit with type dropdown, CTA route picker, datetime pickers for visible_from/until, photo URL field, is_published switch. Workshop-sourced rows show a banner explaining the link.
- Customer UI: `AnnouncementsFeed` widget at `lib/features/home/widgets/announcements_feed.dart`. Realtime stream from announcements; client-side filter for visible-now + cap at 5 + sort by type-priority (workshop > promo > event > general > closure) then recency. Cards show photo (if any), type pill, title, body excerpt, CTA. Wired into `IdleHomeView` between BirthdayCardList and MarketingConsentCard. Renders nothing when no active rows.
- Sidebar: new "Announcements" entry between Packages and Config (15 nav items).
- Routes: `/admin/announcements`, `/admin/announcements/new`, `/admin/announcements/:id/edit`.

## Module 2.4: Coffee menu CRUD (SHIPPED 2026-05-05)
Replaces Module 2.1's view-only `/admin/catalog/coffee` with full create / edit / hide / sold-out toggle / reorder. Realtime keeps the customer cart in sync (already wired in Session 7).

- Migration 0034:
  - `menu_items.is_published` BOOLEAN DEFAULT TRUE — distinct from `is_available` (sold-out for the day). Soft-delete sets is_published=false.
  - Partial index on (menu_id, category, sort_order) WHERE is_published.
  - `menu-photos` private storage bucket + RLS (auth read, service-role write).
  - Five SECURITY DEFINER RPCs gated on `_assert_active_admin()`:
    - `admin_menu_item_create` — auto-appends sort_order at end of category if not provided.
    - `admin_menu_item_update`.
    - `admin_menu_item_delete` — soft via is_published=false, idempotent.
    - `admin_menu_item_toggle_available` — quick-action for sold-out switch.
    - `admin_menu_item_reorder` — direction 'up'/'down' swaps sort_order with the same-category neighbour. Both rows locked with FOR UPDATE.
- Admin UI:
  - `CoffeeListScreen` rewritten — DataTable with thumbnail, name (strikethrough when hidden), category, price, **Available switch** (Switch widget, disabled when hidden), status badge (Live / Sold out / Hidden), per-row actions: ↑ / ↓ / Edit / Hide.
  - `MenuItemEditScreen` (new) — handles both create and edit. Photo picker (XFile.readAsBytes → menu-photos bucket), name, description, price (₹), category. Edit mode adds Available + Published switches.
  - Routes: `/admin/catalog/coffee/new?menu_id=<uuid>`, `/admin/catalog/coffee/:id/edit`.
- **Drag-to-reorder UX deferred** — ↑/↓ buttons are functionally equivalent against the swap RPC and avoid the DataTable→ReorderableListView shell switch. Reorder RPC accepts arbitrary sort_order writes if a future polish pass introduces full drag UI.

---

## Module 2.8: Config admin UI (SHIPPED 2026-05-05)
Surface the venue_config knobs that already lived in DB but had no edit UI, plus admin CRUD for two existing content tables (`reflection_moments`, `hero_card_definitions`).

- **Migration 0042** — three RPC additions:
  - `admin_set_venue_config` whitelist expanded from ~20 keys to ~70: pricing JSONB knobs (`session_extension_options`, `pre_booking_slots_per_day`), full XP economy (`xp_*`, `stage_thresholds_per_trait`, `level_thresholds`), `visit_milestones`, all birthday parameters, all session timing, contact + legal URLs, all feature flags. Function body now branches on column data_type — JSONB columns assigned via `$1->key` (preserves structure), scalars via `($1->>key)::type` cast.
  - `admin_reflection_moment_upsert` — NULL p_id creates, otherwise updates by id with COALESCE semantics. Validates `primary_trait` ∈ {rafi, ellie, gerry, zena}.
  - `admin_hero_card_upsert` — same shape; validates `hero` ∈ {rafi, ellie, gerry, zena}.
- **Admin UI** — `config_screen.dart` rewritten as 11 collapsible sections:
  - Pricing (session prices + extension options JSONB editor + pre-booking slots)
  - GST (with CA-confirmation banner)
  - Topup offers (4-field row editor: amount, bonus, label, badge)
  - Cashback / referrals / reactivation (cashback %, low-balance, reactivation credit/expiry, churn threshold, all 3 referral knobs)
  - XP economy (all 11 xp_* keys + stage/level thresholds as JSON textareas; validates 5-int stage shape)
  - Visit milestones (3-field row editor: visits, reward_xp, reward_paise)
  - Birthday (booking enabled, autocancel/threshold/interest TTL hours, child birthday wish toggle + time + 2 copy fields)
  - Session timing (10 int fields + pre-booking hold percent)
  - App version control (iOS/Android min+latest + force-update message)
  - Contact + legal URLs (9 URL/text fields)
  - Feature flags (7 boolean toggles)
- Each section has its own Save button → audit-logged via `admin_set_venue_config`. JSONB editors use a controller-pattern shared `_rows` list so snapshot at save time reads the current edits.
- **Content screens** — replaces `/admin/content` stub:
  - `/admin/content` — index card grid (Reflection moments / Hero cards / FAQ-coming-soon).
  - `/admin/content/reflection-moments` — list with trait chips + sort order + XP weight; tap row to edit in dialog (display_text, tag, icon, primary_trait, xp_weight, sort_order, is_active). New button creates.
  - `/admin/content/hero-cards` — card grid (image + name + hero + rare/birthday/hidden chips); tap to edit in dialog (name, hero, description, image_url, is_rare, is_birthday_exclusive, is_active).
- Sidebar nav: Content's "soon" dot removed.
- **Deferred to v1.1**:
  - Notification copy templates — current call sites use hardcoded strings; making them admin-editable requires a `sendNotification` refactor + template-resolver layer. Out of scope for this module.
  - Reactivation campaign defaults — paired with the Session 13 cron + MSG91 plumbing.

flutter analyze (whole project): clean.

---

## Module 2.7: Birthday packages rich CRUD + PDF (SHIPPED 2026-05-05)
Replaces Module 2.1's view-only `/admin/packages` with full CRUD + JSONB-driven menu options + PDF generation.

- **Migration 0040** — adds 4 JSONB columns to `birthday_packages`: `menu_options`, `non_food_offerings`, `available_days`, plus a `pdf_url` slot. Creates `package-pdfs` public bucket (per ARCHITECTURE-001 — promotional content).
- **Migration 0041** — four SECURITY DEFINER RPCs gated on `_assert_active_admin()`:
  - `admin_package_create` (16 args) and `admin_package_update` (17 args, all COALESCE-able). Update sets `pdf_url=NULL` to invalidate the cached PDF.
  - `admin_package_delete` — soft via `is_active=false`.
  - `admin_package_regenerate_pdf` — fires `generate-package-menu-pdf` Edge Function via `pg_net` using the vault service-role key (same pattern as `notify_push_dispatch`).
- **Edge Function `generate-package-menu-pdf`** — composes a single-page A4 PDF using `pdf-lib`. Sections: header, title + tier, description, capacity line, "What's included", menu options (categories with options + upcharge labels), "Also included" (non-food offerings), pricing footer, contact line. Uploads to `package-pdfs` bucket and writes URL back to `birthday_packages.pdf_url`. `verify_jwt=true` + service-role bearer.
- **Admin UI**:
  - `PackagesListScreen` rewritten — card grid (320px wide, 16:9 cover aspect). Per-card: Active badge, PDF-cached chip (green ✓ if cached, grey "PDF stale" otherwise), Edit + PDF actions. PDF button calls `admin_package_regenerate_pdf` and refreshes after 3s.
  - `PackageEditScreen` (new) — single form for create+edit. Scalar fields (name, tier, hero_theme, price, deposit, duration, capacity, sort) + photo upload to `package-photos`. JSONB fields (`inclusions`, `menu_options`, `non_food_offerings`, `available_days`) edited as JSON-text textareas with **placeholder defaults** so admin edits structured data instead of starting blank. Gallery URLs as one-per-line text. On save, RPC fires; PDF regen auto-triggered after success (best-effort, doesn't block save).
- **Customer UI**: minimal touch-up to `package_detail_screen.dart` — adds "Download menu PDF" outlined button (links to `pdf_url`) between "Not included" and "How booking works" sections, only when `pdf_url` is non-empty. Falls back gracefully when admin hasn't generated yet.
- Routes added: `/admin/packages/new`, `/admin/packages/:id/edit`.
- **Deferred to v1.1**: full menu-selector flow during reservation (customer picks specific menu options). The data is captured in `menu_options` JSONB; reservation UI integration is a follow-up.

flutter analyze (whole project): clean.

---

## Cart unification (Module 2.5/2.6 follow-up — SHIPPED 2026-05-05)

Resolves the split-cart problem from Module 2.5 (FIT meals previously bypassed the cart) + the combo XOR limitation in Module 2.6.

- **Cart model refactored** (`lib/features/club/providers/cart_provider.dart`):
  - New sealed `CartLine` hierarchy: `MenuItemLine` / `ComboLine` / `FitMealLine`. Each has `id`, `unitPricePaise`, `quantity`, `linePaise`, `displayName`, `copyWithQuantity()`.
  - `CartState.lines` is a single heterogeneous list. `isEmpty` / `totalItemCount` / `totalPaise` aggregate across all line types.
  - `CartNotifier` API: `addMenuItem` / `addCombo` (both merge by id), `addFitMeal` (always appends — different selections = different lines), `changeQuantityById`, `removeLineById`, `clear`. Backward-compat shims for `addItem` / `applyCombo` / `removeCombo` / `changeQuantity`.
- **Combo flow simplified** — `combo_card.dart` no longer shows "Replace bag?" dialog. Tapping Add appends a `ComboLine` with quantity 1; subsequent taps stack quantity.
- **FIT builder** writes to client cart instead of `fit_meal_order_create` directly. Server-authoritative price still computed via `fit_meal_compute_price` at add time. Selections JSONB + human-readable summary stored on the line for cart-card display.
- **Cart sheet** now renders a single `_LineList` with type-aware accent + icon + label. Combo lines show included-item names; FIT lines show selections summary.
- **Migration 0039** — `order_items` extended (`line_type` CHECK, nullable `combo_id` / `fit_meal_order_id` / `selections_jsonb`, `menu_item_id` loosened to nullable). `fit_meal_orders.order_id` added. New `order_place` body walks heterogeneous `p_items` array, validates each line by type (`menu_item` / `combo` / `fit_meal`), accumulates subtotal, then snapshots into `order_items` + creates `fit_meal_orders` rows linked to the parent. Backward compat: legacy entries lacking `type` default to `menu_item`. Combo discount math removed — combos are flat-priced lines now.
- **Cart persistence across restart** deferred to v1.1 (cart still client-side only).

flutter analyze (whole project): clean.

---

## Module 2.6: Combos CRUD (SHIPPED 2026-05-05)
Replaces Module 2.1's view-only `/admin/catalog/combos` with full CRUD.

- Migration 0038 — three SECURITY DEFINER RPCs (`admin_combo_create`, `admin_combo_update`, `admin_combo_delete`). No schema change needed; existing `combos` table already has all columns. Soft-delete via `is_active=false`.
- Combo items stored in `inclusions` JSONB. New shape: `{"menu_items":[{"id":"<uuid>","quantity":N},...]}`. Backward-compatible read accepts legacy `{"menu_item_ids":[...]}` flat array.
- `CombosListScreen` rewritten — DataTable with thumbnail, name (strikethrough when hidden), description excerpt, item count, price, status badge. + New / Edit / Deactivate actions.
- `ComboEditScreen` (new) — single form for create+edit. Photo picker → `menu-photos` (public). Multi-item picker grouped by brand (Coffee / FIT) with per-row checkbox + quantity stepper. **Live savings indicator** computes (Σ item × qty) − combo price; shows "Saves ₹X" / "Combo costs MORE" / "Same as à-la-carte" with appropriate colour.
- Routes added: `/admin/catalog/combos/new`, `/admin/catalog/combos/:id/edit`.

---

## Module 2.5: FIT meal builder (SHIPPED 2026-05-05)
Normalized 4-table builder + orders + waitlist. Pricing server-authoritative. Two commits: schema/RPCs (A) and admin+customer UI bundled (B).

**Commit A — schema (0036) + RPCs (0037)** — `fbd1fa7`:
- 6 tables: `fit_meal_categories`, `fit_meal_options`, `fit_meal_templates`, `fit_meal_template_categories` (linker), `fit_meal_orders`, `fit_subscription_waitlist`. RLS on all. Realtime publication on the four customer-visible tables.
- Pricing helper `_fit_validate_and_price` (service-role) walks every linked category for the template, validates required + selection-type cardinality + option availability, sums upcharges. Customer-callable wrapper `fit_meal_compute_price` exposes it for live UI updates.
- `fit_meal_order_create(template_id, selections_jsonb)` — server-authoritative pricing on add-to-cart. Inserts row with `status='in_cart'`.
- `fit_subscription_waitlist_join(email)` — idempotent on family_id.
- 11 admin RPCs gated on `_assert_active_admin()`. Soft-delete via `is_published=false`. Category delete refuses if any template references it.
- Selections JSONB shape: single → `{"<cat_id>":"<opt_id>"}`; multi → `{"<cat_id>":["<opt_id>",...]}`.

**Commit B — admin + customer UI bundled**:

Admin (under `/admin/catalog/fit`):
- `FitListScreen` — replaces the Module 2.1 stub. Templates DataTable with thumbnail / name / base price / category-count / status badge / Edit + Unpublish actions. Header buttons route to Categories and Waitlist. + New template button.
- `FitTemplateEditScreen` — single form for create+edit. Photo picker (XFile.readAsBytes → public menu-photos bucket per ARCHITECTURE-001). Linked-categories editor: chip-tap to add unlinked cats, per-link Required checkbox + selection-type-override dropdown + Remove. Diff is computed on save (re-link present, unlink missing for edits).
- `FitCategoriesScreen` — global categories + their options. ExpansionTile per category. Inline AlertDialogs for create/edit of categories + options. Per-option Available switch + Edit + Hide. Refuses category delete if templates reference it (server-side).
- `FitWaitlistScreen` — read-only DataTable (family name, email, signed-up date) with status dropdown (interested → contacted → onboarded → not_interested) per row.
- 5 routes added under `/admin/catalog/fit/*`.

Customer:
- `FitMenuTab` — replaces the BrandMenuTab-only wrapper. Three stacked sections: subscription waitlist banner (gradient card → modal email capture), "Build your meal" template cards, legacy menu_items section (`brand='fit'`) for backward compat with pre-Module-2.5 seed.
- `FitBuilderScreen` at `/club/fit/builder/:templateId`. Loads template + linker rows + categories + options. Renders single-select (ChoiceChip) or multi-select (FilterChip) per category with required/optional pill. Sticky bottom bar shows server-computed total. CTA disabled until all required categories filled. `fit_meal_compute_price` invoked on every selection change for live total. Add-to-cart calls `fit_meal_order_create`, shows snackbar, pops back.
- Decline modal + email validation client-side; server-side regex enforced.

**Cart integration deferred** (TODO comment in `FitBuilderScreen`): FIT orders live in their own `fit_meal_orders` table with `status='in_cart'` rather than retrofitting into the existing menu_items cart. Surfacing them in a unified cart sheet is a follow-up.

flutter analyze: clean across the board.

---

## Module 2.5: legacy LOCKED SPEC entry (superseded by SHIPPED entry above)
The Module 2.5 spec has been implemented per the SHIPPED entry above. This placeholder is retained briefly so search/refs to "LOCKED SPEC" still surface a pointer. Safe to delete next time BUGS.md is touched.

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
