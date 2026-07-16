# Events / Party Pipeline — Build Plan

**Status:** Plan only. No feature code written yet.
**Author:** audit + design pass, 2026-07-12.
**Branch:** `diaries-os-events`.

The venue's biggest revenue stream (~53%) — birthday parties and private events — runs today on
phone calls, WhatsApp, and a paper register with no system. This plan adds **one** capability: a
lead → follow-up → booking → payment → day-of → completion → repeat pipeline, plus an owner report.

Birthday-package CRUD already exists (`lib/admin/packages/`, `birthday_packages`). This is the
**pipeline around the packages**, not a replacement for them.

---

## 1. Scope & guardrails

- **Money is paise** (integer), everywhere. Reuse `Money.fromPaise` (admin) / `rupees()` (staff_web).
- **GST:** parties follow the birthday-package pricing model already in `birthday_packages`
  (`price_per_pax_veg_paise` / `_non_veg_paise`, 18% treatment). Don't invent a new tax path.
- **Prod writes go through the one-lane workflow** (file → git → migration tool → ledger → prod).
  No autonomous/agent-driven prod money writes. Schema lands as new sequential migrations
  (`0236_*` onward). MCP stays read-only for this planning stage.
- **Target staff surface is the React PWA `staff_web/`** — NOT the parked Flutter staff app
  (`lib/staff/`). This is the post-launch staff sprint; the customer app (v1.0.4) is already
  submitted and stays essentially untouched.
- **Founder drives content.** Ship the source taxonomy and checklist as *structure*; keep the
  editable lists minimal and let the founder own the copy. Don't preseed example lead names.

---

## 2. What already exists (reuse inventory)

The pipeline is **~40% already built** — as a customer-initiated *birthday reservation* flow.
Here is exactly what to reuse.

### Backend (Supabase)
| Thing | Where | Reuse as |
|---|---|---|
| `birthday_reservations` (booking record) | `0001`, funnel `0014`, cancel `0025` | **The booking record.** Cols: `venue_id, family_id, child_id, package_id, slot_date, slot_start_time, slot_end_time, slot(morning\|evening), num_kids, num_adults, package_price_paise, deposit_paid_paise, balance_paise, total_paid_paise, status, assigned_admin, admin_contacted_at, admin_confirmed_at, admin_notes, triggered_by, cancelled_reason, special_requests, idempotency_key`. Status machine: `interested → admin_contacted → confirmed → completed \| cancelled \| no_show`. **Every booking field is NOT NULL** — it cannot hold a bare lead. |
| `birthday_packages` | `lib/admin/packages/`, `0040/0078+` | Catalog the booking references. `price_per_pax_veg/non_veg_paise`, `deposit_paise`, `hall_name`, `min/max_guests`, `duration_hours`. |
| `birthday_availability` | `0001` (**dormant — no RPC reads it**) | **Activate for slot-conflict + venue-block.** `venue_id, slot_date, slot_start_time, slot_end_time, is_blocked, block_reason, UNIQUE(venue_id, slot_date, slot_start_time)`. |
| `wallet_transactions` + `wallet_topup` | `0003`, hardened `0228` | **The ledger PATTERN to copy** (SECURITY DEFINER, double idempotency on `idempotency_key`+`razorpay_payment_id`, `FOR UPDATE`, ledger row + `audit_log`). Types `birthday_deposit_debit/_balance_debit` are already reserved. |
| `birthday_deposit_record` | `0003` §15 | **Precedent to SUPERSEDE, not reuse** — it routes party money through the *kids' wallet* with a fake `balance_after` and assumes a family wallet. Phone leads have no wallet. |
| Invoice numbering | `_next_invoice_number()`, `invoice_year_counters` (`0100/0101`) | `INV-YYYY-NNNNN` for party receipts. |
| Three auth lanes | customer `assert_caller_authority`; admin `is_admin()`/`admin_users`; staff `tablet_devices → verify_staff_pin`/`staff` | Party RPCs pick the lane by caller. Staff RPCs use the `tablet_devices` + `p_staff_pin_id` pattern (see `0232/0234`). |
| `admin_birthday_dashboard`, `admin_birthday_reservation_contact/confirm/edit/cancel/complete`, `birthday_inquiry_submit`, `birthday_reservation_cancel` | `0016/0079/0091` | Existing pipeline RPCs — extend, don't duplicate. |

### Admin console (`lib/admin/`) — Flutter
- **`birthday_crm/birthday_crm_screen.dart` is already a working lead pipeline**: 4-column kanban
  (`interested → admin_contacted → confirmed → completed`), `_KpiRow`, a "birthdays this month"
  outreach table, a 440px `_DetailDrawer`. Backed by `birthday_reservations` +
  `admin_birthday_dashboard(p_month)`.
- `reports/` — `/admin/reports` is a **`ComingSoonScreen` stub**; the one real report
  (`hall_of_heroes_screen.dart`) is the pattern to copy: file-local `FutureProvider.autoDispose` →
  aggregate read → KPI tiles + filter chips + `ListView.separated` table. **No chart library** in
  the app; owner report stays tiles/tables.
- Reuse: `AdminListScaffold`, `admin_buttons.dart` (web-safe buttons), `AdminAppBar`, the
  `_KpiTile`/`_KpiRow` pattern (promote out of `birthday_crm` into `widgets/`), `Money.fromPaise`.
  Add a section = a `GoRoute` in `admin_router.dart` + a `_NavItemSpec` in `admin_sidebar.dart`.

### staff_web (`staff_web/src/`) — React PWA — **no events UI exists today**
- House pattern: RPC-first via `rpc<T>(fn, params)` in `lib/supabase.ts`; server state in
  **@tanstack/react-query** (`hooks/useVenueData.ts`) with `refetchInterval` polling, true Realtime
  only where needed (`useOrders`, `components/Alerts.tsx`).
- **`components/Sheet.tsx`** — the workhorse bottom-sheet for every action flow.
- **`screens/CheckInScreen.tsx`** — the gold standard for **≤10s entry**: `+91` numeric phone
  field, Enter-to-submit, chip selects, one big button, `useMemo` stable `crypto.randomUUID()`
  idempotency key. **Model the lead-capture form on this.**
- **`screens/WalkInScreen.tsx`** — manual create of a family+child on the fly (reusable `Field`
  wrapper). **This is how a phone booking materializes a family+child.**
- **`screens/PendingPaymentsScreen.tsx`** — collect cash at counter (`mark_counter_payment`), and
  `RefundRow` in `CustomerSheet.tsx` — the amount-input idiom for **advance/balance collection**.
- Identity: single **actor** via `requireActor()` (auto-picks `staff_roster` row 0, no PIN prompt);
  every mutating RPC carries `p_staff_pin_id: staff.staffId`. `rupees()`/`toE164()` in `lib/format.ts`.
- Primitives: `Button/Card/Pill/Empty/useToast` in `components/ui.tsx`; `CakeIcon` in `icons.tsx`.
- Routes live in `App.tsx` (`Gate`); nav in `components/Shell.tsx` (5-slot bottom nav + More grid).

### Customer app (`lib/features/birthday/`) — the existing secondary funnel
- `widgets/inquiry_bottom_sheet.dart` → `birthday_inquiry_submit` (this **is** the "in-app enquiry
  form" — the minor secondary source). `reservation_status_screen.dart` already renders the
  customer's pipeline timeline. Keep both; just tag the enquiry as one **source** among many.
- `0164_birthday_lead_track.sql` is a **marketing push track** (D-30/D-15 nudges +
  `birthday_marketing_state` dedup) — NOT a sales pipeline. Reuse its cron/dedup shape for the
  auto-repeat lead.

---

## 3. Gap analysis (what's genuinely net-new)

1. **A lead that isn't a booking.** A ≤10s phone lead has no family, child, package, or date.
   `birthday_reservations` can't hold it (all NOT NULL). → **new `party_leads` table.**
2. **Mandatory structured `source`.** Today only free-text `triggered_by`. → source enum, required.
3. **Follow-up states + due dates.** Today the machine jumps straight to `admin_contacted`. → lead
   status (`new/contacted/follow_up/quoted/won/lost`) + `next_follow_up_at` + snooze.
4. **Structured lost reasons.** Today only free-text `cancelled_reason`. → `lost_reason` enum.
5. **Slot conflict + venue-block warnings.** `birthday_availability` is dormant; bookings do **no**
   conflict/capacity check. → activate it, check per-hall.
6. **Real advance/balance payments.** Columns exist but are hand-typed; no online/counter recording.
   → **new `party_payments` ledger** + record RPC (parties don't route through kids' wallets).
7. **Day-of checklist.** No checklist/task table anywhere. → **new `party_checklist_items`** (11 items).
8. **Auto-repeat lead ~10.5 months post-party.** → new cron.
9. **Owner pipeline report.** `/admin/reports` is a stub. → new aggregate RPC + report screen.

---

## 4. Where this should live — recommendation

Three surfaces, three roles. **staff_web is the primary build; the backend is the shared spine.**

### 4.1 staff_web (React PWA) — PRIMARY: the front-desk operational cockpit
This is where the leads actually arrive (phone at the front desk, on the tablet). It has the
≤10s fast-entry DNA and zero events UI today, so it's the big net-new build. Owns:
- **Lead capture** (≤10s, phone-first, `Sheet` on `CheckInScreen` pattern; **source mandatory**).
- **Follow-up queue** (my/all leads, "due today", snooze, mark-contacted, quote sent, lost+reason).
- **Booking** (resolve/create family+child via `staff_lookup_family`/walk-in create → pick
  package/date/slot → **conflict + venue-block warning** → confirm).
- **Advance/balance collection** (counter cash/UPI now; Razorpay link later — `PendingPayments` idiom).
- **Day-of checklist** ("today's parties" → 11-item checklist, per-item done-by/at).
- **Mark completion.**

### 4.2 Admin console (`lib/admin/`) — OWNER: oversight, report, config (desktop)
The owner works on desktop. Owns:
- **Owner pipeline report** at `/admin/reports` (replace the stub): leads by source, conversion
  rate, average ticket, bookings-ahead-by-week, lost reasons. Tiles + tables, no chart dep.
- **Venue-block calendar** (owner sets holidays/maintenance blocks → `birthday_availability`).
- **Keep the existing `birthday_crm` kanban** as the bird's-eye pipeline view (re-point its lead
  columns at `party_leads`; booked/completed columns stay on `birthday_reservations`).
- Package CRUD already lives here — unchanged.

### 4.3 Customer app (`lib/features/birthday/`) — SECONDARY, minimal touch
- Keep `inquiry_bottom_sheet.dart`; route it through the lead pipeline as `source = 'app_enquiry'`.
- `reservation_status_screen.dart` already shows the pipeline. *Optional later:* surface
  advance/balance due + a "pay advance" button (Razorpay). Not day-1.
- No customer UI for the auto-repeat lead — it's a server cron (+ optional push if they're a family).

**Rule of thumb:** operational verbs (create lead, follow up, book, collect, check off, complete)
live in **staff_web**. Analytical/config nouns (report, blackout calendar, kanban oversight,
packages) live in **admin**. The customer app only *originates* one source and *watches* status.

---

## 5. Recommended data model

Recommendation: **a new `party_leads` funnel head + keep `birthday_reservations` as the strict
booking record**, rather than relaxing five NOT NULL columns that the shipped customer app,
journey states, and notifications all assume. One lead → (on win) one booking.

```
party_leads                         -- NEW: the single funnel head, all sources
  id                uuid pk
  venue_id          uuid not null
  source            text not null    -- 'phone'|'walkin'|'app_enquiry'|'referral'|'instagram'
                                      --  |'whatsapp'|'auto_repeat'|'other'  (CHECK, editable list)
  status            text not null default 'new'
                                      -- 'new'|'contacted'|'follow_up'|'quoted'|'won'|'lost'
  lead_name         text not null    -- parent/host name (phone lead has no family yet)
  lead_phone        text not null    -- E.164 (toE164)
  lead_child_name   text
  lead_child_dob    date             -- drives the auto-repeat 10.5-month timer
  guest_estimate    int
  tentative_date    date
  tentative_slot    text             -- 'morning'|'evening'
  package_id        uuid             -- interested package (nullable)
  family_id         uuid             -- linked if resolved to an app family (nullable)
  child_id          uuid             -- linked once booked (nullable)
  reservation_id    uuid             -- set when status='won' → birthday_reservations.id
  assigned_staff_id uuid             -- staff.id
  next_follow_up_at timestamptz      -- powers the "due today" queue
  last_contacted_at timestamptz
  follow_up_count   int not null default 0
  lost_reason       text             -- 'price'|'date_unavailable'|'went_elsewhere'|'no_response'
                                      --  |'not_serious'|'other'  (nullable, required when lost)
  lost_reason_note  text
  notes             text
  created_by_staff_id uuid
  created_at        timestamptz not null default now()
  updated_at        timestamptz not null default now()

party_payments                      -- NEW: append-only party money ledger (NOT the kids' wallet)
  id                uuid pk
  reservation_id    uuid not null    -- → birthday_reservations
  kind              text not null    -- 'advance'|'balance'|'refund'
  amount_paise      int not null     -- signed; refund negative
  method            text not null    -- 'cash'|'card'|'upi'|'razorpay'|'bank_transfer'
  razorpay_payment_id text
  invoice_number    text             -- _next_invoice_number() (optional per row)
  collected_by_staff_id uuid
  idempotency_key   text unique not null
  note              text
  received_at       timestamptz not null default now()
  -- reservation.deposit_paid_paise/balance_paise/total_paid_paise = denormalized rollups;
  -- this ledger is the source of truth (matches CLAUDE.md "ledger over cached balance").

party_checklist_items               -- NEW: 11 day-of items per booking, per-item audit
  id                uuid pk
  reservation_id    uuid not null
  item_key          text not null    -- 'decor'|'menu_confirmed'|'staff_assigned'|'guest_count'
                                      --  |'kids_count'|'housekeeping'|'food_labels'|'tissues'
                                      --  |'host_briefed'|'activities_ready'|'washroom_cleaned'
  label             text not null    -- seeded from template; founder-editable later
  is_done           bool not null default false
  done_by_staff_id  uuid
  done_at           timestamptz
  sort_order        int not null
  unique(reservation_id, item_key)

birthday_availability               -- EXISTING, activate: owner-managed blackout rows
  -- add read in the booking RPC: is_blocked → venue-block warning;
  --   existing confirmed reservation same (venue, hall, slot_date, slot) → conflict warning.
```

Notes:
- **Booking materializes a family+child** (reuse `staff_lookup_family` / walk-in create) so
  `birthday_reservations` invariants hold and the host becomes a durable CRM contact.
- The existing `birthday_inquiry_submit` (customer) either also inserts a `party_leads`
  (`source='app_enquiry'`) row, or the admin kanban reads a `UNION` view. Prefer the former —
  one funnel head.
- Conflict is **per hall** (`birthday_packages.hall_name`), and is a **warning, not a hard block**
  (the venue may run parallel halls; staff override with a reason).

---

## 6. RPC surface (all SECURITY DEFINER, audit_log on every mutation)

Staff lane (`tablet_devices` + `p_staff_pin_id`, `crypto.randomUUID()` idempotency):
- `party_lead_create(p_source, p_lead_name, p_lead_phone, p_child_name?, p_child_dob?, p_guest_estimate?, p_tentative_date?, p_slot?, p_package_id?, p_notes?, p_staff_pin_id, p_idempotency_key)` — the ≤10s call.
- `party_lead_update_status(p_lead_id, p_status, p_next_follow_up_at?, p_lost_reason?, p_note?, p_staff_pin_id)` — contacted / follow-up / quoted / lost.
- `party_booking_create(p_lead_id, p_family_id, p_child_id, p_package_id, p_slot_date, p_slot_start, p_slot_end, p_num_kids, p_num_adults, p_price_paise, p_override_conflict?, p_staff_pin_id, p_idempotency_key)` — checks `birthday_availability` + existing reservations, returns `{warnings:[...]}`, creates `birthday_reservations`, sets `lead.status='won'` + `reservation_id`.
- `party_payment_record(p_reservation_id, p_kind, p_amount_paise, p_method, p_razorpay_payment_id?, p_staff_pin_id, p_idempotency_key)` — ledger row + reservation rollups + optional invoice number. **Supersedes `birthday_deposit_record`.**
- `party_checklist_toggle(p_reservation_id, p_item_key, p_is_done, p_staff_pin_id)`.
- `party_booking_complete(p_reservation_id, p_staff_pin_id)` — → `completed`; triggers the repeat-lead schedule.
- Reads (react-query): `staff_party_leads(p_venue_id, p_filter)`, `staff_party_bookings_upcoming(p_venue_id)`, `staff_party_checklist(p_reservation_id)`.

Admin lane (`is_admin()`):
- `admin_events_pipeline_report(p_from, p_to, p_venue_id)` → `{leads_by_source[], funnel{leads,contacted,confirmed,completed,rates}, avg_ticket_paise, bookings_ahead_by_week[], lost_reasons[]}`.
- `admin_venue_block_set(p_venue_id, p_slot_date, p_slot, p_is_blocked, p_reason)` — blackout calendar.

Cron (service_role):
- `party_repeat_leads_cron` — daily; for each `completed` booking whose child's next birthday is
  ~10.5 months out (≈319 days after party date), insert a `party_leads` row `source='auto_repeat'`
  with dedup guard (unique on child + birthday_year, à la `birthday_marketing_state`). Optional push
  to the family if linked. Model on the existing `-cron` edge functions + reservation-expiry cron.

---

## 7. Build phasing

| Phase | Deliverable | Surfaces | Notes |
|---|---|---|---|
| **0** | Schema + core RPCs | supabase | `party_leads`, `party_payments`, `party_checklist_items`, activate `birthday_availability`; migrations `0236+`. |
| **1** | Lead capture + follow-up queue | staff_web | Highest value — retires the paper register. `Sheet` + CheckIn-style entry; "due today" list. |
| **2** | Booking (conflict/block warnings) + advance/balance collection | staff_web | Reuse walk-in create + PendingPayments idiom. |
| **3** | Day-of checklist + completion | staff_web | "Today's parties" → 11-item checklist. |
| **4** | Auto-repeat lead cron | supabase | Dedup guard; optional push. |
| **5** | Owner pipeline report + venue-block calendar | admin | Stub → real; re-point kanban lead columns at `party_leads`. |
| **6** (opt) | Customer: tag app enquiry as source; surface advance/balance due | customer | Minimal; not day-1. |

Ship Phase 1 first and let the venue run leads on it before Phase 2 — it's independently useful.

---

## 8. Decisions needed from you before I write code

1. **Two tables vs one.** Recommended: new `party_leads` (funnel head) + strict
   `birthday_reservations` (booking). Alternative: relax the reservation NOT NULLs and use one
   table (simpler queries, higher risk to the shipped customer flow). → **confirm the split.**
2. **Party money ledger.** Recommended: dedicated `party_payments` table (parties don't belong in
   the kids' wallet). Alternative: route through `wallet_transactions` with `reference_type='birthday'`
   like the legacy `birthday_deposit_record`. → **confirm dedicated ledger.**
3. **Conflict = warning or hard block?** Recommended: warning + staff override (parallel halls).
4. **Source & lost-reason lists** — the enums in §5 are a starting point; give me your real list
   (you own the content).
5. **Auto-repeat timing** — "~10.5 months after the party" = ~319 days; or do you want "45 days
   before next birthday"? Both are one line; pick the anchor.
6. **Booking without an app family** — OK to auto-materialize a lightweight family+child at booking
   (reusing walk-in create)? Recommended yes.

---

## 9. Non-goals / out of scope for this pass
- No new tax/GST path — reuse the package pricing model.
- No redesign of birthday-package CRUD or the customer reservation status screen.
- No touching the parked Flutter staff app (`lib/staff/`).
- No third-party CRM, calendar sync, or e-signature.
- No online Razorpay party-payment flow in Phase 2 (counter cash/UPI first; link is a fast-follow).

---

## 10. Reuse cheat-sheet (open these when building)
- Fast entry: `staff_web/src/screens/CheckInScreen.tsx`
- Create family+child on the fly: `staff_web/src/screens/WalkInScreen.tsx`
- Collect payment: `staff_web/src/screens/PendingPaymentsScreen.tsx`, `RefundRow` in `components/CustomerSheet.tsx`
- Bottom sheet / primitives: `staff_web/src/components/Sheet.tsx`, `components/ui.tsx`
- RPC helper / money / phone: `staff_web/src/lib/supabase.ts`, `lib/format.ts` (`rupees`, `toE164`)
- Ledger + idempotency pattern: `wallet_topup` in `supabase/migrations/0003_rpc_functions.sql` (+ `0228`)
- Legacy to supersede: `birthday_deposit_record` (`0003` §15)
- Slot/block primitive: `birthday_availability` in `0001_initial_schema.sql`
- Admin report pattern: `lib/admin/reports/hall_of_heroes_screen.dart`; KPI tiles in `lib/admin/birthday_crm/birthday_crm_screen.dart`
- Add admin section: `lib/admin/admin_router.dart` + `lib/admin/widgets/admin_sidebar.dart`
- Customer enquiry (existing secondary source): `lib/features/birthday/widgets/inquiry_bottom_sheet.dart`
</content>
