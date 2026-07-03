# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single Flutter codebase that builds **three apps**, selected at launch by build flavor:

- **Customer app** ("Play Diaries") — the shipping product; kids play-area app (wallet, sessions, birthdays, club orders, gamification, safari).
- **Staff app** — tablet KDS / venue ops.
- **Admin web** — desktop-first Flutter web console (catalog, CRM, live ops, content).

The branch happens in `lib/app.dart`: `F.isAdmin` → `AdminApp`, `F.isStaff` → `StaffApp`, else the customer `DiariesClubApp`. All three share `bootstrap()` (Supabase + Firebase init) and one Supabase backend.

Backend is **Supabase** (Postgres + RLS + RPCs + Deno edge functions), project ref `stpxtenyatjwcazuxhtu`. The Flutter side talks to it almost entirely through **Postgres RPCs** and **realtime streams** — there is very little REST/table-write logic in Dart.

## Running

The user runs long-lived `flutter run` commands themselves — give copy-paste commands, don't background them. Helper scripts live at the repo root and in `scripts/`.

```bash
# Customer app on a physical iPhone (dev). Uses env/dev.json.
./run_dev_iphone.sh            # PROFILE mode — see note below

# Customer app in Chrome (dev)
./run_dev_web.sh

# Staff app on Android (dev flavor staffDev)
./run_staff_dev_android.sh

# Admin web (no --flavor on web; flavor is set in Dart)
flutter run -d chrome --web-port=5060 \
  -t lib/main_admin_dev.dart \
  --dart-define-from-file=env/admin_dev.json
```

- **iOS runs use `--profile`, not debug.** Flutter 3.41.6 debug mode crashes on iOS 26.x (PAC/EXC_BAD_ACCESS). Profile mode is AOT and runs clean, at the cost of no hot reload. Android debug is fine.
- Each flavor has a Dart entry point (`lib/main_<flavor>.dart`) + an env file (`env/<flavor>.json`) passed via `--dart-define-from-file`. Committed `env/*.json` hold the real keys used for founder testing; `env/*.example.json` are the templates. See `FLAVORS.md`.
- Android installs dev/staging/prod/staff side-by-side (distinct `applicationId`). iOS uses a single bundle id `com.diariesclub.app` for all flavors — no side-by-side install.

### Flavor config & modes (`lib/flavors.dart`)

The global `late FlavorConfig F` is set in each `main_*.dart` before `bootstrap()`. It carries `OtpMode` (`mock`/`real`) and `RazorpayMode` (`mock`/`test`/`live`), resolved from dart-defines.

- Both **default to the safe production value** (`real` / `live`) when the env value is missing — a misconfigured build never silently accepts the mock OTP `123456` or fakes a wallet top-up.
- Dev currently runs against **live Razorpay and real OTP** (per `env/dev.json`), not mock — the founder tests with ₹1 real recharges. Don't assume dev == mock.

## Analyze / lint / test

```bash
flutter pub get
flutter analyze                       # custom_lint + riverpod_lint enabled
dart format lib/
flutter test                          # widget/unit tests (test/ is minimal)
flutter test test/path_to_test.dart   # single test file
```

`analysis_options.yaml` enforces `strict-casts`/`strict-inference`/`strict-raw-types`, single quotes, const-preference, and `avoid_print`. Excludes `*.g.dart` / `*.freezed.dart`.

**Codegen note:** `freezed`, `json_serializable`, and `riverpod_generator` are in dev deps, but there are currently **no generated `*.g.dart` / `*.freezed.dart` files** committed and providers are hand-written (plain `StreamProvider`/`Provider` globals, not `@riverpod`). Follow the existing hand-written style rather than introducing codegen unless asked. If a file ever does need generation: `dart run build_runner build --delete-conflicting-outputs`.

## Architecture

### Layout under `lib/`

- `core/` — cross-app foundation: `providers/` (Riverpod state, the data layer), `router/` (`app_router.dart` + `app_shell.dart`), `theme/`, `notifications/` (FCM), `services/`, `models/`, `widgets/`.
- `features/` — customer app, one dir per domain (`home`, `club`, `sessions`, `birthday`, `adventure`, `safari`, `gamification`, `auth`, `onboarding`, `profile`, `reflection`, `reactivation`, `force_update`). Feature dirs commonly hold `*_screen.dart`, `providers/`, and `widgets/`.
- `staff/` — staff app screens + `staff_router.dart`.
- `admin/` — admin web, one dir per console section + `admin_router.dart`.
- `shared/` — small shared widgets.

### State & data flow

State is **Riverpod**. The dominant pattern (see `core/providers/current_wallet_provider.dart`) is a global `StreamProvider` that subscribes to a Supabase **realtime stream** (`.from(table).stream(...)`) or calls an **RPC**, keyed off `currentFamilyIdProvider` / auth. UIs render a shimmer while the stream yields `null` (first load) rather than a misleading zero. Writes go through RPCs (e.g. `play_pass_purchase`, `session_create_with_coupon`) — the transaction ledger (`wallet_transactions`) is often the source of truth over a cached `balance_paise` column.

### Routing

`go_router`, wired to Riverpod in `core/router/app_router.dart`. A root redirect enforces auth (public path prefixes in `_publicPathPrefixes`) and force-update. `core/router/app_shell.dart` is the customer bottom-nav shell: **Home · Club · Adventure · Safari · Profile**. Splash (`/`) does smart cold-start routing. Staff and admin have their own routers.

### Theme

`core/theme/` — `AppTheme.light/dark`, `AppColors` (navy + gold), Nunito via `google_fonts`. **The customer app is locked to light theme** (`darkTheme: AppTheme.light`, `themeMode: light`) — many customer widgets hard-code light surface colors, so enabling dark mode produces unreadable white-on-white. Staff and admin do honor a theme-mode provider. Text scale is clamped (customer 1.5×, admin 1.0×).

### Notifications

FCM is **customer-app only** (staff tablets and admin web use realtime instead — see the `!F.isStaff && !F.isAdmin` guard in `bootstrap.dart`). Deep links arrive via FCM `data.deep_link` payloads (`core/notifications/fcm_setup.dart`) — **not** Branch or Universal Links (the `flutter_branch_sdk` dep is dead code). FCM init is best-effort with a 4s timeout so a hung APNs registration can't block launch. No third-party crash SDK by policy — native crash logs only.

## Supabase backend (`supabase/`)

- `migrations/` — 200+ sequentially numbered SQL files (`NNNN_description.sql`). This is where schema, RLS policies, and **RPCs** live; most app behavior is server-side. Read the latest few to understand current schema before changing anything. Apply via the `supabase-diariesclub` MCP server (`apply_migration`) or `execute_sql` for reads.
- `functions/` — Deno/TypeScript edge functions: OTP (`auth-otp`, `send-sms` via MSG91), payments (`razorpay-topup`, `razorpay-webhook`, `razorpay-reconcile`), push (`send-push`), several `-cron` jobs, and image/PDF generation. Shared helpers in `functions/_shared/` (`admin.ts`, `auth.ts`, `audit.ts`, `response.ts`).

Before schema changes use `list_tables`; when debugging start with `get_logs` / `get_advisors`.

## Conventions & context

- **Money is in paise** (integer), never floats. Fields like `amount_paise`, `balance_paise`.
- **Brand:** customer-facing name is **"Play Diaries"** (not "Diaries Club", which only appears in internal/bundle ids). Legal entity "Planovative Diaries LLP".
- The app targets India (`en_IN` locale, INR).
- `docs/` holds policies (privacy/terms/refund HTML for store submission), `BUGS.md`, and handover notes. `FLAVORS.md` documents the flavor matrix. `spec/` holds product specs.
- Deploy scope for the current launch is the **customer app only**; the staff app and admin console are functional but parked for a post-launch redesign sprint.
