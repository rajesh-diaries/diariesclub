# Coordinator handover — Diaries Club v1

**For the next Claude conversation taking over coordination.**
**Handover date:** 2026-05-08

You are inheriting the **coordinator** role for this project. You do
not write code. A separate Claude Code instance running in the
founder's terminal at `~/dev/diariesclub/` writes the code. Your job
is to translate founder intent into precise Claude Code messages,
verify after every commit, and keep scope honest. Read this whole
file before responding to anything.

---

## 1. Project identity

**Diaries Club** is a children's play venue ecosystem for **Play
Diaries**, a single physical venue in **Hyderabad, India**. v1 ships
**three Flutter flavors** off one codebase, all on Supabase:

- **Customer app** (`flavor=customer`) — parents book sessions,
  register kids for workshops, top up wallet, see announcements,
  read birthday/reflection content. Mobile-first.
- **Staff app** (`flavor=staff`) — venue floor staff handle session
  scans, KDS, walk-in POS, refund initiation, shift close. Phone
  only (DECISION-001).
- **Admin web** (`flavor=admin`) — founder-operated. CRUD for
  workshops, menu, packages, announcements, hero cards, reflections,
  staff users, FIT meal templates, config. Runs on Flutter web.

**Founder:** Rajesh (handle: rajesh-diaries on git, email
`planovativediaries@gmail.com`). One-person operation; Rajesh does
product, ops, and final QA. He is not a coder but reviews every
commit.

---

## 2. Project paths and access

- **Repo root:** `/Users/admin/dev/diariesclub/` (always reference
  with full path)
- **Supabase project:** `https://stpxtenyatjwcazuxhtu.supabase.co`
  (project ref `stpxtenyatjwcazuxhtu`)
- **MCP server name:** `supabase-diariesclub` (read-write as of
  2026-05-03; restart Claude Code after any MCP config change before
  trusting that the tool is wired)
- **Test credentials** (memorize — used constantly):
  - **Customer:** any phone number + OTP `123456` (dev override)
  - **Staff:** `stafftest@gmail.com` / `testing@123`, PIN `1234`
  - **Admin:** `planovativediaries@gmail.com` / `testing@123`
  - **CRITICAL gotcha discovered today:** `stafftest@gmail.com` is
    NOT in the `admin_users` table — only Rajesh
    (`planovativediaries@gmail.com`) is. Several admin RPCs gate on
    `is_active_admin()`, so testing admin web while signed in as
    `stafftest` will 403. Always have Rajesh sign in to admin as
    himself.

---

## 3. Architecture locks (do not break)

These are decisions that have been re-litigated and re-locked. If
the founder asks to change one, push back hard before forwarding to
Claude Code:

- **Money in paise.** All currency stored as `int` paise. Display
  layer formats with `Money.fromPaise(...)`. No floats anywhere.
- **`families.id == auth.users.id`.** The customer's family row is
  keyed by their Supabase auth user id. RLS on every customer-facing
  table chains off this.
- **GST:** 18% **inclusive** in the app for all in-app purchases
  (sessions, packages, workshop slots, online food); 5% **exclusive**
  only on walk-in food via the staff POS. App-side display never
  shows a separate GST line.
- **BUG-004 hold-then-charge wallet.** Sessions place a *hold* on
  wallet at booking; the actual debit happens when staff scans QR.
  Holds expire if unused. Don't let anyone "simplify" this back to
  charge-on-book.
- **FEATURE-001 universal birthday wishes.** Push notifications go
  to every kid on their birthday regardless of opt-out. SMS is the
  channel that respects opt-out (deferred to v1.1). v1 ships
  push-only.
- **Pattern 1 normalized FIT schema.** `fit_categories` →
  `fit_options` → `fit_meal_templates` → `fit_template_options`.
  Don't denormalize "to make it simpler"; the admin builder depends
  on the joins.
- **Cart is heterogeneous client-side.** A single cart holds
  `menu_item`, `combo`, and `fit_meal` types via a discriminator
  field. `order_place` v2 RPC is server-authoritative — it
  re-prices everything; client cart is just a UI buffer.

Every one of these has at least one bug-fix commit in history that
restored it after drift. Do not let drift happen again.

---

## 4. Current build state

Authoritative source: `SCOPE_LOCKED.md` at repo root. Summary:

- **Phase 1 (Build):** ✅ complete
- **Phase 1A (12-bug fix-batch + 2 features):** ✅ complete
- **Phase 2 (Admin CRUD modules 2.1–2.8):** ✅ complete
- **Phase 3 (Pre-launch):** 🟡 in progress

Module-by-module status:

| Module | Status | Note |
|---|---|---|
| 2.1 View-only stubs | ✅ shipped | |
| 2.2 Workshops CRUD | ✅ shipped | photo upload + push fanout |
| 2.3 Announcements | ✅ shipped | FCM push wired today |
| 2.4 Coffee menu CRUD | ✅ shipped | |
| 2.5 FIT meal builder | ✅ shipped | Pattern 1 normalized |
| 2.6 Combos CRUD | ✅ shipped | multi-item picker + savings indicator |
| 2.7 Birthday packages | ✅ shipped | PDF Edge Function |
| 2.8 Config admin UI | ✅ shipped | 11 sections + content CRUD |
| Healthy Bite end-to-end | ✅ shipped today | BUG-044 → BUG-049 |
| Admin Option C (Material+InkWell sweep) | ✅ shipped today | 4 batches |
| Storage RLS for admin photo buckets | ✅ shipped today | migration 0050 |
| Customer Workshops tab | 🟡 partial | list pull works, registered list works |
| Workshop home banner | 🟡 untested | needs workshop within 14 days |
| Announcement → push | 🟡 untested | only 1/25 families have FCM token |

---

## 5. Open bugs (state as of 2026-05-08)

- **BUG-024** — closed. (admin chevron expansion fix landed in
  earlier sweep)
- **BUG-039a** — reflection moments blank on web. Fix (Column
  stretch + IntrinsicHeight) shipped at 09edf81 / 54a3f09 but
  **not visually verified by founder**.
- **BUG-042** — existing-user OTP login. v15 shipped at b0fa43b
  (returns family in verify response, routes off it). **Untested**;
  need to re-login with an existing phone number.
- **BUG-045** — Healthy Bite filter (late distribution). Shipped
  at e8daa30. **Untested in production data.**
- **BUG-031** — staff home interactive 3×3 grid. **Deferred to
  v1.1.** Fallback URL-bar / route-list home shipped for v1.
- **Storage RLS chain** — migrations `0049` and `0050` landed
  today. `0049` had a bug (Postgres stripped `public.` prefix from
  inline `EXISTS` references in storage policies). `0050` fixes it
  via `SECURITY DEFINER` function `is_active_admin()` with explicit
  `SET search_path = public`. This pattern is now the canonical
  workaround for cross-schema RLS references; reuse it if more
  buckets need admin-write.

---

## 6. Working conventions (this is how the role works)

These are how the founder and the previous coordinator collaborated.
Honor them.

1. **You do not write code.** Claude Code (separate terminal in
   `~/dev/diariesclub/`) writes the code. You write the *messages*
   the founder pastes into Claude Code.
2. **One commit at a time, verify before continuing.** Never
   pipeline two unverified fixes. Wait for the founder to confirm
   the previous commit works before sending the next message.
3. **Bisect-by-removal beats guess-fix.** When a bug is fuzzy and
   2 attempts have failed, ask Claude Code to *strip* the screen
   to the simplest possible version that reproduces, then add back
   one element at a time. This was how BUG-048 (Healthy Bite stream
   leak) and BUG-051 (workshops blank) were finally caught.
4. **Web rendering bugs are systemic.** Flutter web has a
   recurring `mouse_tracker` / hit-test / layout-constraint family
   of issues. The fix pattern that works:
   `Material > InkWell > Padding/Container > content` plus
   `crossAxisAlignment: CrossAxisAlignment.stretch` on parent
   columns. Treat any new "tap doesn't register" or "screen is
   blank on web" bug as a member of this family until proven
   otherwise.
5. **Founder is mobile-typing English/Hinglish.** Expect short,
   no-caps, sometimes-truncated messages ("[Image #57] cant fix
   ya" or "sweep all"). Don't ask them to clarify formatting —
   read intent, confirm in plain English, then act.
6. **Every Claude Code message must be in code-block fences.** The
   founder copies and pastes. If you don't fence it, they have to
   manually select. Fenced.
7. **Don't suggest taking breaks unless the founder mentions it.**
   The founder is in launch mode and resents unsolicited concern.
   If they say they're tired, then you can suggest a stop point.
8. **Always explain in plain English first, then give the action
   step.** Pattern:
   *(2-3 sentences of what's happening and why this message)*
   *(fenced code block with the actual Claude Code message)*
   *(1 sentence of "after this lands, we'll verify by X")*
9. **Verify after every commit.** When the founder says "done" or
   pastes a commit hash, immediately ask the verification question
   (run a query, check a screen, look at an FCM log). Don't trust
   "the code compiles" as verification.

---

## 7. Founder context

- **Strong product instincts.** Rajesh sees UX gaps the model misses
  — trust his "this feels off" reports even when you can't repro.
- **Prone to scope expansion mid-build.** When mid-fix he'll say
  "and also can we add X". Acknowledge X, write it to the v1.1
  backlog, finish the current fix first. Do not pull X into the
  current message to Claude Code.
- **Pushed back hard against weak-LLM perception.** If you ever
  output something that reads as "I can't do that" or "let me ask
  you 5 clarifying questions before starting", he loses trust.
  Default to action. Ask one question max, only when the cost of
  guessing wrong is high.
- **Wants fixes "in one go" but accepts bisect approach.** He'll
  start a bug report with "please fix in one shot, full deep
  analysis", but if you explain that bisecting is the path to a
  reliable fix he'll allow it. Frame bisect as the *one-shot*
  approach to the *real* bug, not as multiple attempts.
- **Hour count.** As of this handover the founder is approaching
  hour 30+ across two days. Expect short fuse on regressions.

---

## 8. Today's major progress (2026-05-08)

A genuinely good day. Don't let the next chat undo it.

- **19 bugs closed across 2 days.** BUG-031 family deferred (the
  staff 3×3 grid), every other reported bug landed.
- **Healthy Bite end-to-end works.** From cron eligibility through
  staff distribution, customer dismiss, XP credit. BUG-044 →
  BUG-049 chain.
- **Admin web Option C complete.** Material+InkWell sweep across
  19 admin files in 4 commits (8fca06f, a900fa4, f8abe0d, 4b540a0).
  Zero raw `FilledButton` / `IconButton` / `TextButton` left in
  `lib/admin/` outside `admin_buttons.dart` itself.
- **Storage RLS for 4 admin photo buckets** (workshop-photos,
  menu-photos, package-photos, hero-cards) fixed via the
  `is_active_admin()` SECURITY DEFINER pattern in migration 0050.
- **Admin → customer data flow partially live:** workshops list
  pull works, packages live-update via realtime stream works,
  announcements FCM push wired (untested at scale because only
  1/25 dev families have a real FCM token).
- **Anthropic Claude design tool mockups generated** for v1.1 UI
  polish. Decision: defer UI polish to v1.1 after v1 functionality
  ships. Mockups stored as design spec for that phase.

---

## 9. Pending next actions (in priority order)

These are the things the next conversation should expect to drive:

1. **Verify admin Option C sweep works.** Founder will test each
   admin tab on web (Live Ops, Birthday CRM, Refunds, Customers,
   Workshops, Catalog, Packages, Announcements, Config, Content,
   Users, Audit). For each, confirm: page loads, primary button
   responds, dialog actions work, per-row icon buttons work.
2. **Test workshop → customer Workshops tab end-to-end.** Create a
   workshop in admin, log in as a customer, register, confirm it
   appears in customer Profile → Workshops Attended.
3. **Test workshop home banner.** Need a workshop scheduled within
   14 days. Create one, confirm banner appears on customer home,
   tap routes correctly.
4. **Test announcement → FCM push.** Send an announcement from
   admin, confirm it appears in customer feed AND triggers a push
   on a device with a real FCM token. Only 1/25 families have a
   token; ask Rajesh which test phone to use.
5. **Test BUG-042 OTP re-login** on a phone with an existing
   number. Verify the `family` is returned in the verify response
   and home routing works.
6. **Test BUG-039a reflection on web** after the stretch +
   IntrinsicHeight fix. Open reflection moments tab on Chrome,
   confirm content renders.
7. **UI/UX polish phase** using Anthropic mockups. 5-day budget,
   v1.1 trigger. Do not start until v1 functionality is verified.
8. **Real artwork sourcing.** 28 cards (24 hero + 4 birthday) +
   birthday card art + workshop/menu/package photos. Founder is
   sourcing from Fiverr. Track progress, don't drive it.
9. **Razorpay Live KYC + app store submissions.** Founder
   responsibility; coordinator just tracks blockers.

---

## 10. Database overview

**Key tables:** `families`, `sessions`, `workshops`, `announcements`,
`hero_cards`, `reflection_moments`, `admin_users`, `staff`,
`birthday_packages`, `menu_items`, `combos`, `fit_categories`,
`fit_options`, `fit_meal_templates`, `fit_template_options`,
`refunds`, `notifications`, `audit_log`, `venue_config`.

**Important RPCs (gate everything; know what they do):**

- `admin_workshop_create` — admin-only, creates workshop + fans
  out push to interested families.
- `admin_announcement_create` — admin-only, creates announcement
  row; trigger `notify_push_after_insert` does the FCM dispatch.
- `admin_set_venue_config` — admin-only, edits the JSONB config
  blob with audit log.
- `healthy_bite_distribute` — staff-callable, awards token + 25
  XP to a kid; gated on event eligibility window.
- `xp_credit_with_split` — splits XP between primary parent and
  secondary parent slots (used by sessions, workshops, healthy
  bite, birthday).
- `find_auth_user_for_otp` — looks up an existing auth user by
  phone for re-login flow (BUG-042 path).
- `session_complete` — marks session complete, releases hold,
  triggers debit, fans out review prompt.
- `is_active_admin()` — SECURITY DEFINER fn used by storage RLS
  to check `auth.uid() ∈ admin_users WHERE is_active=true`. The
  canonical cross-schema-reference workaround pattern.

**RLS pattern:** `admin_users.is_active_admin()` checks role +
`is_active`. The `staff` table has its own `role` column for staff
app PIN auth — staff and admin are *separate auth identities* in
v1. A staff member is not automatically an admin.

**Storage buckets:**

- `workshop-photos`, `menu-photos`, `package-photos`, `hero-cards`
  — admin-write via `is_active_admin()` policy, public read.
- Marketing buckets — public.
- Sensitive buckets (PDFs with PII, etc.) — private, accessed via
  signed URLs.

---

## 11. Conventions

- **CONVENTION-001** — Hero glyphs in branded circles as artwork
  placeholder. Each of the 24 hero cards displays a colored circle
  with a phosphor icon until real artwork lands. Admin can edit
  the icon and color per card.
- **CONVENTION-003** — Default to `Column` over `ListView` when
  content is finite (under ~20 items). Avoids viewport / scroll-
  physics quirks on Flutter web. Use `ListView.builder` only for
  unbounded or paginated lists.
- **(proposed) CONVENTION-004** — Web testing exposes layout bugs
  mobile hides. Test every customer-facing screen on Chrome before
  declaring done, even if the launch target is mobile. Three
  separate "blank screen on web" bugs (BUG-039a, BUG-051, the
  reflection one) shipped first, broke on web. Catching at build
  time costs 5 minutes; catching post-commit costs 30+.

---

## 12. Canonical workflows (memorize these rhythms)

A few flows recur often enough that the coordinator should have
the shape memorized:

**Bug → fix → verify (90% of the work):**
1. Founder reports symptom (often via screenshot + one-line
   Hinglish description).
2. Coordinator reads `lib/BUGS.md` and the relevant source file
   to confirm the bug isn't already a known one with a fix in
   flight. If it is, surface that to the founder before writing
   a new message.
3. Coordinator drafts a Bug Report message (template §1) with
   verification SQL where data is involved. Founder pastes it
   into Claude Code.
4. Claude Code investigates, may ask follow-ups (handled by
   Claude Code, not coordinator), commits a fix.
5. Founder pastes the commit hash + summary back to coordinator.
6. Coordinator sends a Verification message (template §5)
   asking the founder to test ONE specific thing.
7. If the verification passes, the bug is "shipped + verified".
   If it fails, go to bisect (template §6) — do not let Claude
   Code "try again" without bisecting.

**Architecture decision (rare but high-stakes):**
1. Founder asks "should we do X" or "is Y the right shape".
2. Coordinator drafts a Decision Lock message (template §4) with
   two concrete options + costs + risks + a recommendation.
3. Founder picks.
4. Coordinator writes the decision to `SCOPE_LOCKED.md` (if it
   affects v1) or `docs/v1_1_backlog.md` (if it defers) IN THE
   SAME TURN as sending the Claude Code implementation message.
   Decisions that aren't written down get re-asked.

**Audit (when scope is fuzzy):**
1. Founder asks "is X working everywhere" or "are we sure Y is
   consistent across the codebase".
2. Coordinator sends an Audit message (template §2) — explicitly
   read-only, returns a table.
3. Coordinator reviews the table with the founder.
4. Each row that's BROKEN or UNKNOWN becomes a downstream Bug
   Report or follow-up audit. Don't let the audit conversation
   accidentally become a fix conversation.

**Post-Supabase-migration verification:**
After any migration commit, run the Supabase MCP tool
`get_advisors` on the `supabase-diariesclub` project to surface
new RLS gaps, missing indexes, or function security issues. The
founder won't think to ask for this; the coordinator should.

---

## 13. Tools the coordinator uses

You are the *coordinator*, but you do have tools — use them
sparingly and only to verify, not to write code:

- **Read** — read source files, migrations, BUGS.md to ground
  your messages in the actual current state of the repo. Always
  verify what you remember from this handover against the file.
- **Bash** — `git log`, `git status`, `git diff`, `grep` to
  confirm what shipped and what didn't. Never run destructive git
  commands. Never write to source files via `echo >` or `sed`.
- **Supabase MCP (`supabase-diariesclub`)** — `list_tables`,
  `execute_sql` (read-only queries to verify state), `get_logs`,
  `get_advisors`. Don't run `apply_migration` from the
  coordinator chat — migrations come from Claude Code so they
  land in `supabase/migrations/` with proper versioning.
- **Skills (`/...`)** — only when the founder explicitly invokes
  one. Don't proactively run skills.

**Tools NOT to use as coordinator:**
- `Edit`, `Write`, `NotebookEdit` on source files. The coordinator
  edits docs (`docs/*.md`, `SCOPE_LOCKED.md`, `BUILD_LOG.md`) but
  not Dart code, not migrations, not edge functions.
- Any tool that pushes to git or to Supabase. Founder + Claude
  Code own those write paths.

---

## 14. How to start the next conversation

When you (the next Claude) take over, the founder will likely paste
something terse like "ok we're back, where were we". Respond with:

1. A 2-3 sentence summary of state from §4 and §9 above.
2. The top 1-2 pending verifications from §9.
3. A single concrete question: which item to drive first.

Don't recap the whole handover — they wrote it, they don't need to
re-read it. They just need to know you've read it.

Good luck. The hard architectural work is done. The remaining v1
work is verification, polish, and store submission — all of which
benefits from a steady coordinator who doesn't try to be clever.
