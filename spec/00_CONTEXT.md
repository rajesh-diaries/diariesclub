# Diaries Club — Permanent Context

> **PASTE THIS FILE AT THE START OF EVERY CLAUDE CODE SESSION.**
> Then paste the specific session file (01, 02, 03, …) for the work you want done.
> Each session is a fresh Claude Code conversation. Do not chain sessions in one conversation.

---

## 1. Project — One-Line

Diaries Club is a Flutter + Supabase app for **Play Diaries** in Hyderabad — a kids' play area + café with three brands (Play Diaries, Coffee Diaries, FIT Diaries). The app is a **birthday-bookings funnel built on a play-visit habit base.**

## 2. Business Priority (read this twice)

1. **Birthdays first.** A birthday booking is ₹15,000–50,000 = 15–50 play sessions in revenue. Every feature is judged against "does this drive more birthday bookings?"
2. **Play visits second.** They are the habit-builder that fills the birthday funnel. A family that visits 8+ times will book a birthday; a family that visits once will not.
3. **Cross-brand revenue density per visit** is a tertiary lever — combos, while-you-wait food orders, etc.

If a feature is delightful but doesn't move one of these levers, **build it last or skip for v1.**

## 3. Audience

- **Primary:** parents in Hyderabad (English-speaking, urban, smartphone-native)
- **Secondary:** café-only walk-in customers (no kids required to use the app)
- **Children themselves do not use the app directly** — the app speaks to parents about their kids

## 4. Tech Stack — Locked

| Layer | Choice | Notes |
|---|---|---|
| Mobile | Flutter (latest stable) | iOS 14+, Android 8.0+, portrait only |
| Admin | Flutter Web (same codebase) | Responsive |
| Backend | Supabase Cloud | Postgres 15+, Auth, Storage, Realtime, Edge Functions, RLS |
| State | Riverpod 2.x | Realtime as StreamProviders |
| Payments | Razorpay Flutter SDK | **Webhook-only credit** (never client-side) |
| OTP/SMS | MSG91 via Supabase Auth | Reactivation blast also via MSG91 |
| Push | Firebase Cloud Messaging | Best-effort only; in-app inbox is reliable layer |
| Crash | Sentry | PII stripped; separate projects for mobile vs admin |
| Animation | Rive (interactive) + Lottie (cinematic) | Stage transitions = Lottie at venue |
| Font | Nunito (google_fonts) | Weights 400, 600, 700, 800, 900 |
| Icons | phosphor_flutter | Regular default, Fill for active states |
| Currency | `intl` NumberFormat, `locale: 'en_IN'` | Indian comma format: ₹1,10,000 |
| Phone | E.164 canonical | Stored as `+919876543210` everywhere |
| Time zone | IST (`Asia/Kolkata`) for all date math | Especially streaks and birthday journey |
| Deep links | **Branch.io** (NOT Firebase Dynamic Links — deprecated Aug 2025) | |

## 5. Foundational Conventions

- **All money in paise** (1 rupee = 100 paise) — server-side. Display only converts at the edge.
- **All RPC functions:**
  - `SECURITY DEFINER`
  - Accept an `idempotency_key` parameter
  - Fully atomic — succeed completely or fail completely
  - Return `JSONB`
  - Raise exceptions on failure (never partial state)
- **All client-supplied prices are ignored.** Server looks up real prices from the database.
- **All write operations need an audit log entry** (`audit_log` table).
- **`families.id` = `auth.users.id`** — Supabase Auth user UUID is the family ID.
- **Wallet is auto-created** on family signup via trigger.
- **No `localStorage`/`sessionStorage` analogues client-side** for sensitive data — use `flutter_secure_storage`.

## 6. Locked Decisions Log (Reference)

The founder reviewed and locked ~90 decisions across 13 themes during planning. The most important ones:

### Money & Wallet
- Wallet auto-created on family signup
- `payment_method` CHECK includes `'system'` (for bonus rows)
- Razorpay credits via webhook only — never from client success callback
- Auto-reconciliation cron every 15 min checks Razorpay API for missed credits
- All order prices and GST calculated server-side from `menu_items` lookup
- Diaries Coins = bonus rupees in the same wallet (not a separate currency)

### Gamification — Trait System
- 4 heroes = 4 traits: **Rafi = Brave, Ellie = Kind, Gerry = Curious, Zena = Creative**
- **All four heroes available from day one** — no level-based unlocks
- Each hero has independent XP and 5 stages (Seedling → Explorer → Adventurer → Champion → Legend)
- **Overall level = sum of all four trait XPs** (mapped to 20-level threshold table)
- Each child picks one **favourite hero** at onboarding (cosmetic avatar only)
- Parent reflects on each session via the Hero Recap Card → **tap-the-moments grid** (8–12 cards mapped to traits)
- **Auto-equal-split if no reflection within 24h**
- **Stage transitions revealed at the venue, not at home** — push notification when 1 session away, cinematic plays during recap
- Hero card draws are **simple 10% rare random** (no provably-fair claim)
- Healthy Bite reward stays separate from FIT food orders (founder explicitly chose to keep them decoupled)

### Birthday Funnel (Primary Goal)
- **Day -90 journey start** + hero-progression-triggered prompts
- Persistent **Home tab birthday card** (always visible)
- **Hybrid booking flow:** browse + reserve in-app, admin closes via WhatsApp/call
- **3–4 fixed packages** with food included (cross-brand bundling)
- **Post-event amplification:** birthday-exclusive hero card + auto-album, both shareable
- Staff app has **"Birthday Party Mode"** for photo capture during parties

### Play Visits & Returns (Secondary Goal)
- **Session pre-booking:** "Same time next Saturday?" prompt after a great visit
- Wallet rewards: **visit-based + streak milestones** (no decay)
- **Wall of Legends** — anonymised daily highlights (light social proof)
- Visible referrals: **Home tab card**, not buried in Profile
- **First referral = "Brave Boost"** (bonus XP for Rafi, replaces old "unlock Rafi" reward)
- Streaks: **Monday–Sunday calendar week, IST**
- Brand-specific badges: Play Champion, Coffee Regular, FIT Family + cross-brand combo badges

### Cross-Brand
- **2–3 fixed combos** at point of order ("Play + Café", "Family Saturday")
- **While-you-wait food prompt** — only from 2nd visit onwards (smart timing)
- Home tab is **constant** (no time-of-day dynamic content for v1)
- Café/food-only customers are **full app users** — no kids required at signup

### Operations
- QR check-in: **parent shows, staff scans** (current spec confirmed)
- Staff: **single shared venue tablet login** + **per-staff 4-digit PIN** for sensitive actions
- Cash: **end-of-shift reconciliation report**
- Refunds: staff can issue ≤₹500, admin approves above
- Grace period: **30-min hard cap** (configurable as `grace_max_minutes`)
- Workshop registration: **atomic spot decrement** (race-condition fixed)
- Concurrent session extends: **row-locked** (race-condition fixed)
- Session timer uses **server-clock offset** (device clock not trusted)

### Reactivation Campaign
- ~2,000 contacts from paper book (names + phones + visit dates)
- One-time admin import → SMS blast via MSG91 (DLT-registered template)
- **Generic SMS, no names** (paper data quality is uncertain)
- Smart link with **Branch.io** campaign tracking → install → app verifies phone → matched contacts get **₹200 welcome credit** automatically
- **No cap** on welcome credits, but admin can pause campaign
- Organic (non-book) new users get **no welcome credit** — exclusive to book contacts
- 90-day expiry on welcome credit if unredeemed

### Compliance & Operations
- **Account deletion = anonymise on request, immediate** (with strong "Type DELETE" confirmation)
  - Replace name with "Deleted User", phone with placeholder, child names + photos removed
  - Keep wallet_transactions for tax audit trail
  - Mark `deleted_at`, log out all devices
- **Privacy Policy + Terms hosted at `diariesclub.com/privacy` and `/terms`** (drafts pending)
- **Marketing consent** opt-in checkbox at signup (default unchecked)
- **Age gate:** 18+ checkbox + explicit guardian declaration
- **GST PDF invoices** auto-generated for every order, stored in user history, emailable
- **Razorpay disclosures** (refund/cancellation policy links) at checkout — required by RBI

### Customer Support & Admin
- Customer search: by **phone, name, or child's name**
- **Read-only impersonation** for debug
- Wallet credits flow free; **debits require reason + 2-person approval** (with single-admin fallback mode)
- **Full bulk operations toolkit** in admin (mass refunds, mass notifications)
- Help screen: **phone + WhatsApp** number prominently displayed

### Errors, Monitoring & Resilience
- **Auto-reconciliation cron** every 15 min reconciles Razorpay payments against wallet_transactions
- **Push best-effort, no retry.** In-app inbox `notifications` row is the reliable layer
- **Sentry:** strip PII before send (no phones, names, child names in payloads); separate projects for mobile and admin
- **Backups:** Supabase daily + manual weekly download by admin
- **Friendly error screen** with copyable error code (e.g., "E-247") + tap-to-WhatsApp support
- **Two-tier app version control** with per-platform minimum versions; force-update screen below minimum
- **System Health dashboard** in admin (uptime, errors, reconciliation, push delivery)
- **Critical-only phone alerts** to owner (payment system down, DB unreachable, ₹1,000+ reconciliation mismatch)

### Photos & Files
- All uploaded photos resized client-side: **1080×1080 max, ~80% JPEG, 500 KB cap**
- Larger uploads rejected with clear UX
- Storage upload via Supabase Storage; access via signed URLs

### Accessibility (build into every screen, not retrofit later)
- **Full screen reader support** (VoiceOver iOS / TalkBack Android) — every interactive element labelled
- **Full Dynamic Type support** — all text scales with system font size setting
- **Manual dark mode toggle** in Settings (light default, dark fully styled)
- **Built for slow networks** — 10s aggressive timeouts, retry buttons, cached fallback states

### Testing
- **pgTAP test suite** for all 14 RPC functions (catches money bugs before deploy)
- Run on every migration via CI
- Flutter widget/integration tests skipped for v1; manual QA covers UI

### Conventions for Claude Code

**File naming and module organisation:**
- snake_case for filenames
- PascalCase for class names
- camelCase for variables and methods
- Models in `lib/core/models/`, generated via `freezed`
- Services as singletons via Riverpod providers
- One screen per file, components extracted to `lib/core/widgets/` only if reused 2+ times

**Migration strategy:**
- All schema changes via `supabase/migrations/*.sql` — sequentially numbered
- Every migration must be `IF NOT EXISTS` / `CREATE OR REPLACE` so it's idempotent
- Pair every migration with rollback notes in a top-of-file comment

**Auth and RLS:**
- All RPCs use `SECURITY DEFINER` and bypass RLS safely (server-side validation in the function body)
- All tables have RLS policies; deny by default
- Service role key used only in Edge Functions, never in Flutter

**Audit log requirements:**
- Every staff action that touches money or modifies data writes `audit_log` row
- Include actor_id (staff PIN holder, not just shared login), action, before/after values, venue_id

**Error responses (RPCs):**
- Use named exceptions: `RAISE EXCEPTION 'insufficient_balance';`
- Standard codes: `insufficient_balance`, `session_not_active`, `workshop_full`, `idempotent_replay`, `not_authorised`, `expired`
- Flutter maps these to user-friendly messages in `lib/core/utils/errors.dart`

**Idempotency:**
- Every money-touching RPC accepts `p_idempotency_key TEXT`
- On replay, return success with `idempotent: true` and the original result, never re-execute
- Flutter generates UUIDs for keys; persists in `flutter_secure_storage` until confirmed

## 7. What This v1.5 Spec Adds Over v1.4

If you have read the v1.4 master document, here is what changed:

| Area | v1.4 | v1.5 |
|---|---|---|
| Hero unlock model | Locked behind levels (3, 5, 10) | All four available from day one (trait-based) |
| XP allocation | Single XP pool per child | 4 trait XPs (one per hero) + sum = overall level |
| Reflection ritual | None | Tap-the-moments grid via Hero Recap Card |
| Hero unlock for Rafi | Level 3 | "Brave Boost" bonus XP on first referral |
| Birthday journey start | Day -30 | Day -90 + hero-progression triggers |
| Birthday booking | Lead form → admin only | Hybrid: in-app browse + reserve, admin closes |
| Birthday packages | Custom quotes | 3–4 fixed packages with food bundled |
| Post-birthday | Nothing systematic | Birthday hero card + auto-album, shareable |
| Session pre-booking | Walk-in only | Pre-book "same time next week" after great visits |
| Reactivation | Not in v1.4 | One-time MSG91 SMS blast to ~2,000 paper-book contacts |
| Welcome credit | Not in v1.4 | ₹200 for matched book contacts (90-day expiry) |
| Café-only customers | Excluded | Full app users (no kids required at signup) |
| Profile tab | Mentioned in nav, not built | Full Session 5b with wallet, history, settings, help, referral |
| Cash reconciliation | Not in v1.4 | End-of-shift report; staff PIN audit trail |
| Razorpay reconciliation | Webhook only | Webhook + 15-min cron API check |
| Accessibility | "v2 concern" | Built in from the start (VoiceOver, Dynamic Type, dark mode) |
| Currency display | `₹1100` | `₹1,10,000` (Indian comma format via `intl`) |
| Phone format | Inconsistent | E.164 `+919876543210` everywhere |
| Time zone | Mixed/UTC | IST for all date math |
| Brand badges | Not in v1.4 | Per-brand + cross-brand combo achievements |
| Anonymise on delete | Not in v1.4 | Full DPDP compliance; immediate with confirmation |
| GST invoices | Not in v1.4 | Auto-generated PDF for every order |
| Wall of Legends | Mentioned, undefined | Light social proof — anonymised daily highlights |
| App version control | Not in v1.4 | Two-tier with per-platform minimums |
| System health monitoring | Not in v1.4 | Admin dashboard + critical phone alerts |
| Testing | None | pgTAP for all RPCs |

## 8. Pre-Launch Blockers

These items are NOT inside this spec; the founder owns them. Claude Code does not need to wait, but launch does:

1. **Privacy Policy + Terms drafts** (legal service like Vakilsearch ~₹3,000–10,000)
2. **Public hosting at diariesclub.com** (domain + simple static hosting)
3. **MSG91 DLT sender ID + template registration** (3–7 days lead time)
4. **Razorpay live keys** (test keys used in dev/staging)
5. **Apple Developer account + Google Play Console — both fully set up**
6. **Firebase project + google-services.json + GoogleService-Info.plist**
7. **Branch.io account for deferred deep links** (not Firebase Dynamic Links)
8. **GSTIN registered + invoice template signed off by accountant**
9. **Hero character art — full bodies × 5 stages × 4 heroes = 20 illustrations**
10. **Rive animation files** (hero idle/playing, stage transition cinematics)
11. **Diaries World Map illustration** (4 territories, top-down, for Adventure tab)
12. **Hero Card artwork** (~30 common + 6 rare foil; birthday-exclusive set)
13. **Physical gift catalog + supplier** (for Gift Ladder feature)

## 9. How Each Session File Should Start

Every session file (`01_…`, `02_…`, etc.) begins with the same prompt template:

```
I am building Diaries Club — a Flutter + Supabase app for a kids play area
in Hyderabad. The app is a birthday-bookings funnel built on a play-visit habit base.

Context I have already pasted above (00_CONTEXT.md) covers the business priorities,
tech stack, locked decisions, conventions, and pre-launch blockers.

This session: [SESSION TITLE]
Estimated time: [X hours]
What to build: [SCOPE]
What NOT to build: [OUT OF SCOPE]
Output expected: [FILES / MIGRATIONS]
Acceptance: [HOW TO VERIFY]
```

Each session file then provides the detailed spec for that session.

---

**Now paste the relevant session file (01, 02, 03, …) below this context and Claude Code is ready to build.**
