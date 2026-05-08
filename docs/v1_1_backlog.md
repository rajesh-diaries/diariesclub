# v1.1 backlog

Items deferred from v1 launch. Each entry has a short rationale + the
v1.1 path forward. Sized for **one focused sprint after soft-launch
stabilises**, not a free-for-all.

---

## Rebuild admin web

**Why deferred:** Flutter web hit-test issues are systemic — chevrons
don't expand, FilledButtons absorb taps, IconButtons go non-responsive
when many ConsumerWidgets re-register MouseRegions. We've root-caused
the family three times across customer/staff/admin (BUG-031, BUG-039a,
BUG-024) and each fix only covers a specific surface; the underlying
MouseTracker invariant violation isn't something we can fix surface-by-
surface without a multi-day refactor.

**v1 mitigation:** admin operations are documented in
`docs/admin_via_supabase_v1.md` so the founder can run common flows
(create workshop, edit pricing, push announcement, swap card art,
add staff, edit reflection moments, build FIT templates) directly via
the Supabase dashboard SQL editor during the soft-launch window.

**v1.1 options:**
1. **Upgrade Flutter to latest stable + retest.** Cheapest path. The
   hit-test issue may be patched or attenuated in a newer engine
   release. Budget: 1 day to upgrade + regression-test all three apps;
   if admin web behaves on Chrome + Android browser after that, we
   stop.
2. **Migrate admin to Next.js + Supabase.** If (1) doesn't fix it,
   admin moves to a thin Next.js app on top of the existing admin RPCs
   (which are already wired and unit-tested at the DB layer). Customer
   + staff stay on Flutter — they're mobile-first anyway. Budget:
   ~5–7 days for parity with the current 13 admin tabs.

**Decision point:** evaluate option 1 first (low cost, possible win).
If the Flutter web upgrade doesn't resolve the hit-test issues across
admin's 47 FilledButtons / 23 IconButtons / 3 ExpansionTiles, commit
to option 2 and migrate. Don't sink more time into per-widget
Material+InkWell rewrites — that path was tried during BUG-031 and was
ultimately deferred after 11 attempts.

**Acceptance for v1.1:** founder can complete every flow currently
documented in `docs/admin_via_supabase_v1.md` from the admin UI
without touching SQL.

---

## Added 2026-05-08

### BUG-031 — staff cards interactive home

**Why deferred:** Flutter web hit-test family of bugs. 11 attempts
on 2026-05-06 across 3×3 grid + ListTile fallback both failed with
`mouse_tracker` assertions. Underlying issue is the same one we hit
in the admin Material+InkWell sweep, but staff home has additional
nesting (BottomNav + ConsumerWidget tree) that the surface-level
fix didn't reach.

**v1 mitigation:** URL-bar / route-list home shipped — staff lands
on a page that lists all 9 staff routes + their paths
(`/staff/sessions`, `/staff/kds`, etc.). Day-1 ops works via
bookmarks. All individual screens and their RPCs are wired and
functional.

**v1.1 path:** revisit after the admin web rebuild decision (see
"Rebuild admin web" above). If the Flutter upgrade fixes admin's
hit-test issues, retry staff home with the same fix. If the team
moves admin to Next.js, staff stays Flutter and we do a one-shot
Material+InkWell+stretch rewrite of the staff home grid using the
admin sweep's helpers as a template.

**Acceptance:** staff signs in, lands on a 3×3 card grid (or
ListTile rows, founder choice), each card taps to its route on
web AND mobile.

---

### UI/UX polish phase

**Why deferred:** Shipping v1 functionality first; polish second.
Anthropic Claude design tool generated a full set of mockups on
2026-05-08 covering customer home, profile, workshops tab, and
admin dashboard layouts.

**v1.1 path:** 5-day budget. Mockups serve as the design spec;
implementation is straightforward Flutter widget work using the
existing theme tokens (`AppColors`, `AppTextStyles`,
`AdminPrimaryButton`, etc.). Trigger condition: v1 functionality
verified end-to-end + first-week soft-launch metrics stabilised.

**Acceptance:** every screen referenced in the mockup set matches
the spec on Chrome and Android, sign-off from founder.

---

### 30-stage hero image upgrades

**Why deferred:** Real artwork sourcing is in flight (Fiverr) and
not on the v1 critical path. v1 ships 5 hero card stages built per
spec with branded-circle glyph placeholders (CONVENTION-001).

**v1.1 path:** receive 28 final card images (24 hero + 4 birthday)
+ workshop/menu/package photos. Admin already has photo-upload
flows wired for each (BUG-050 storage RLS landed today). Founder
swaps art via admin; no code changes needed beyond verifying that
the new image dimensions render cleanly on all viewports.

**Acceptance:** all 24 hero cards and 4 birthday cards display
final art across customer home + reflection moments + birthday
flows.

---

### Admin web rebuild option (Flutter upgrade vs Next.js migration)

**Why deferred (and re-evaluated after today's Option C sweep):**
Today's sweep DID resolve the immediate hit-test issues across all
admin tabs by replacing every raw `FilledButton`/`IconButton`/
`TextButton` with the `Material > InkWell > Padding` helpers in
`lib/admin/widgets/admin_buttons.dart`. The "Rebuild admin web"
section above (originally written 2026-05-06) is therefore softer
than it was — admin web may not need a rebuild for v1.

**v1.1 decision tree:**
1. After 2 weeks of soft-launch, audit how many *new* hit-test or
   layout bugs surface in admin web. If under 2, hold the line on
   Flutter and skip the rebuild entirely.
2. If 3+ new bugs surface, evaluate the Flutter upgrade path
   (option 1 in the original section).
3. If the Flutter upgrade doesn't hold, then commit to the Next.js
   migration.

**Acceptance:** decision recorded in this doc with date + rationale
+ which option was picked.

---

## Other items already tracked

These are tracked elsewhere, not duplicated here. See `lib/BUGS.md` for the
authoritative list and current status:

- **BUG-002** — Unsigned QR / forgery risk (deferred, requires server-side QR mint)
- **BUG-003** — Admin read-only impersonation (deferred, audit-log impact pending design)
- **BUG-026** — Staff RLS for KDS / walk-in POS / refund / menu availability / shift-close screens
- **Announcement → FCM push fanout** — admin-created announcements currently land in the in-app feed only; mobile push is not wired (noted inline in `docs/admin_via_supabase_v1.md` §3)
- **Notification copy templates** — `venue_config` flagged this as v1.1 (needs a `sendNotification` refactor before strings are admin-editable)
- **Reactivation campaign defaults** — paired with Session 13 cron + MSG91 (per `lib/admin/config/config_screen.dart` "out-of-scope" footer)
- **Two-person debit worker pairing UI** — toggle exists in feature flags, worker pairing flow doesn't
- **Reports dashboard / System health** — `admin_router.dart` routes to `ComingSoonScreen` for both; aggregations are heavy and depend on the cron stack stabilising
- **FAQ admin CRUD** — `Content` tab has a stub; founder confirmed v1.1 deferral

---

## Out of scope (do not pull into v1.1 without explicit founder ask)

- Multi-venue support — schema has `venue_id` everywhere but the Kondapur
  venue is hardcoded in client code in many places; expanding requires a
  venue-picker shell + RLS audit on every admin RPC.
- Customer-side admin features (e.g. customer-initiated wallet refund
  request flow) — currently a phone-call flow, sufficient for v1+.
- Loyalty / referral analytics dashboards — separate product question
  from "does the admin work".
