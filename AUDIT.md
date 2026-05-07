# Diaries Club v1 — Build State Audit

Audited 2026-05-05 against `SCOPE_LOCKED.md`, `BUILD_LOG.md`, `lib/BUGS.md` (all 1000 lines), 18 spec files, 44 migrations, 15 Edge Functions, and a tree of `lib/`.

## Section 1 — Feature audit

### Customer app

| Feature | Spec'd? | Built? | Working? | v1 / v1.1 | Notes |
|---|---|---|---|---|---|
| Phone OTP signup | YES (04) | YES | UNTESTED | v1 | `lib/features/auth/{phone_entry,otp_verify}_screen.dart`; `auth-otp` Edge Fn (361 LOC); BUG-005/007 fixed; BUG-025 fixed (mock-mode rate-limit bypass). |
| Family + child profile creation | YES (04) | YES | UNTESTED | v1 | `lib/features/onboarding/{family_name,add_child,child_details}_screen.dart`; BUG-006 fixed (web XFile bytes). |
| Hero pick during onboarding | YES (04) | YES | UNTESTED | v1 | `lib/features/onboarding/hero_pick_screen.dart`; profile widgets/hero_picker.dart for later edits. |
| Wallet (top-up, hold, debit) | YES (12) | YES | UNTESTED | v1 | `lib/core/providers/current_wallet_provider.dart`; `wallet_history_provider.dart`; held_paise column added 0022; BUG-004 hold-then-charge architecture verified via SQL. |
| Razorpay integration (test + KYC) | YES (12) | YES | UNTESTED | v1 | `razorpay-topup` (319 LOC), `razorpay-webhook` (296), `razorpay-reconcile` (162); mock/test/live mode switch in code. **KYC submission is founder task, not coded**. |
| Session start / QR display | YES (05) | YES | UNTESTED | v1 | `lib/features/sessions/{session_start,session_qr}_screen.dart`; BUG-016 fixed (auto-dismiss on staff scan). QR is unsigned base64 — see BUG-002 (deferred v1.1). |
| Active session view | YES (05) | YES | UNTESTED | v1 | `lib/features/home/views/session_home_view.dart` + `core/widgets/session_timer.dart`. |
| Order food during session | YES (07) | YES | UNTESTED | v1 | `club_screen.dart`, `order_tracking_screen.dart`, unified cart (`cart_provider.dart`) with sealed CartLine; migration 0039 order_place v2. |
| Extend session | YES (05) | YES | UNTESTED | v1 | `extend_session_sheet.dart`; BUG-017 fixed via migration 0027/0028 (JSONB options, no integer-division bug). |
| Wrap up session | YES (05) | YES | UNTESTED | v1 | wired via `session_home_view`; uses `session_close` RPC. |
| Overrun handling | YES (05) | YES | UNTESTED | v1 | `force-close-grace-sessions` Edge Fn (51 LOC); grace status in sessions table. |
| Session complete → hero recap | YES (06) | YES | UNTESTED | v1 | `core/providers/hero_recap_provider.dart`; `generate-hero-recap-image` Edge Fn (290 LOC); recaps in `hero-recaps` public bucket. |
| Reflection screen (4-trait XP) | YES (06) | YES | UNTESTED | v1 | `lib/features/gamification/reflection_screen.dart`; `reflection-auto-split-cron` (45 LOC) for unfilled reflections; migration 0010. |
| Hero stage progression | YES (06) | YES | UNTESTED | v1 | `stage_thresholds_per_trait` JSONB in venue_config; trait/stage logic in 0003_rpc_functions; widget `core/widgets/trait_progress_bar.dart`. Per-trait detail in `per_trait_detail_screen.dart`. |
| Hero card collection | YES (06/08) | YES | UNTESTED | v1 | `card_unboxing_screen.dart`; admin CRUD in `/admin/content/hero-cards`; `hero-cards` public bucket; widgets `card_grid_item.dart`, `card_detail_sheet.dart`. **Real artwork deferred to v1.1**. |
| Adventure tab dashboard | YES (08) | YES | UNTESTED | v1 | `adventure_screen.dart`, `child_adventure_dashboard.dart`, `wall_of_legends_screen.dart`; migration 0013 realtime. |
| Birthday discovery + planning | YES (09) | YES | UNTESTED | v1 | `birthday_discovery_screen.dart` + `package_detail_screen.dart` + `reservation_status_screen.dart`; BUG-010/011/013/014/015/018/027 all fixed. |
| Birthday packages (3 tiers) | YES (09) | YES | UNTESTED | v1 | `birthday_packages_screen.dart`; admin CRUD in Module 2.7; PDF gen via `generate-package-menu-pdf` Edge Fn (258 LOC); migration 0040/0041. |
| Workshop XP | YES (06/11) | YES | UNTESTED | v1 | `workshops.xp_award` column (0001:385); `workshop_attend` RPC awards XP (0003:1127–1158); admin `WorkshopEditScreen` exposes xp_award field; `workshops_provider.dart` + customer `workshops_tab.dart`. |
| Parent manual XP edit | NO | NO | n/a | not in v1 | Not found in spec or code. No `manual_xp_grant`/`admin_xp_grant` RPC. Not in SCOPE_LOCKED. |
| Stage upgrade notifications | YES (06) | PARTIAL | UNTESTED | v1 | `notify_push_dispatch` trigger (0017) + reflection RPC writes notifications on stage transitions; cinematic reveal in reflection flow. No dedicated stage-upgrade-only push template — uses generic notifications path. |
| Healthy bite reminder (FEATURE-002 in spec, not BUGS) | YES | YES | UNTESTED | v1 | `healthy_bite_widget.dart`, `healthy_bite_reminder_banner.dart`; migration 0044; staff `healthy_bite_screen.dart` for mark-claimed. |
| Push notifications (FCM) | YES (12) | YES | UNTESTED | v1 | `core/notifications/{fcm_setup,fcm_lifecycle_provider,notification_channels}.dart`; `send-push` Edge Fn (379 LOC); `firebase_options.dart` present; iOS support flagged "partial" in fcm_setup.dart comment. |
| Account deletion | YES (Phase 3) | YES | UNTESTED | v1 | `delete_account_screen.dart` + `farewell_screen.dart`; calls `family_anonymise(p_family_id, 'DELETE')`. Mandatory for App Store / Play Store. |
| Marketing consent card | YES (Phase 1A) | YES | UNTESTED | v1 | `home/widgets/marketing_consent_card.dart` + `marketing_consent_visibility_provider.dart`. |
| Reactivation screen | YES (12) | PARTIAL | UNTESTED | v1.1 | `lib/features/reactivation/reactivation_screen.dart` exists; cron + MSG91 plumbing deferred per Module 2.8 notes. Admin `/admin/reactivation` is a `ComingSoonScreen` stub. |

### Staff app

| Feature | Spec'd? | Built? | Working? | v1 / v1.1 | Notes |
|---|---|---|---|---|---|
| Email/password sign-in | YES (10, modified by DECISION-001) | YES | UNTESTED | v1 | `tablet_login_screen.dart`; phone-pivot per DECISION-001; BUG-026 RLS partial fix landed (migration 0043). |
| PIN-gated actions | YES (10) | YES | UNTESTED | v1 | `widgets/staff_pin_sheet.dart`; used in active_sessions, healthy_bite, menu_availability, qr_scanner, etc.; `verify_staff_pin` RPC server-side. |
| Scan QR to start session | YES (10) | YES | UNTESTED | v1 | `qr_scanner_screen.dart` + `scan_success_screen.dart`; `qr_scan_validate` RPC v2 (BUG-004 hold→debit). |
| Manual session | YES (10) | YES | UNTESTED | v1 | `manual_session_screen.dart`. |
| Active sessions list | YES (10) | YES | UNTESTED | v1 | `active_sessions_screen.dart`; BUG-021 fixed (empty-state hero glyphs). |
| Kitchen (KDS) | YES (10) | YES | UNTESTED | v1 | `kds_screen.dart`. RLS coverage incomplete — see BUG-026 (open). |
| Healthy bite mark-claimed | YES (10) | YES | UNTESTED | v1 | `healthy_bite_screen.dart`. |
| Refund | YES (10) | YES | UNTESTED | v1 | `refund_screen.dart`. RLS gap per BUG-026. |
| Walk-in POS | YES (10) | YES | UNTESTED | v1 | `walkin_pos_screen.dart`; migration 0015. RLS gap per BUG-026. |
| Menu availability toggle | YES (10) | YES | UNTESTED | v1 | `menu_availability_screen.dart`. |
| Audit log (staff side) | YES (10) | PARTIAL | n/a | v1.1 | `staff_router.dart` `/staff/audit` is a stub `_AuditPlaceholder` pointing to admin web. Admin-side audit lives at `/admin/audit`. |
| End shift | YES (10) | YES | UNTESTED | v1 | `shift_close_screen.dart`. |
| Polished home (3×3 grid) | YES (10) | NO | DEFERRED | v1.1 | BUG-031 — 11 fix attempts failed; v1 ships URL-bar nav fallback per launch-scope decision. BUG-029 also defers to v1.1. |

### Admin web

| Feature | Spec'd? | Built? | Working? | v1 / v1.1 | Notes |
|---|---|---|---|---|---|
| Auth | YES (11) | YES | UNTESTED | v1 | `admin/login_screen.dart`; `admin_auth_provider.dart`; redirect via `_assert_active_admin()` server-side. |
| Family search / view | YES (11) | YES | UNTESTED | v1 | `customers/{customers_screen,customer_detail_screen}.dart`. |
| Session management | YES (11) | YES | UNTESTED | v1 | `live_ops/live_ops_screen.dart` (initial route `/admin/live-ops`). |
| KDS (admin) | YES (11) | YES | UNTESTED | v1 | Surfaced via Live Ops + `admin_streams.dart`. |
| Workshop create / XP grant | YES (11) | YES | UNTESTED | v1 | Module 2.2: `workshops_list_screen.dart` + `workshop_edit_screen.dart`; migrations 0030/0031; `xp_award` editable; push fan-out on publish. |
| Birthday booking management | YES (11) | YES | UNTESTED | v1 | `birthday_crm/birthday_crm_screen.dart`; full package CRUD via Module 2.7. |
| Reports / analytics | YES (11) | NO | DEFERRED | v1.1 | `/admin/reports` is `ComingSoonScreen` stub — rationale "needs few weeks of real data". |
| User management (staff) | YES (11) | YES | UNTESTED | v1 | `users/users_screen.dart`; `admin-create-auth-user` Edge Fn (129 LOC). |
| Configuration (rates, hours, menu, packages) | YES (11) | YES | UNTESTED | v1 | Module 2.8: `config/config_screen.dart` (11 sections) + content CRUD; migration 0042 expanded whitelist 3.5×; full menu CRUD across coffee/FIT/combos (Modules 2.4/2.5/2.6); package CRUD (2.7); announcements (2.3); content (reflection-moments + hero-cards). |
| Refunds queue | YES (11) | YES | UNTESTED | v1 | `refunds/refunds_queue_screen.dart`. |
| Audit log | YES (11) | YES | UNTESTED | v1 | `audit/audit_log_screen.dart`. |
| Live ops dashboard | YES (11) | YES | UNTESTED | v1 | `live_ops_screen.dart` is initial route. |
| System health | YES (11) | NO | DEFERRED | v1.1 | `/admin/health` is `ComingSoonScreen` — depends on Session 13 cron. |
| Read-only impersonation | YES (11/13) | NO | DEFERRED | v1.1 | BUG-003 deferred — needs both Edge Fn + customer-side guard. |

### Infrastructure

| Feature | Spec'd? | Built? | Working? | v1 / v1.1 | Notes |
|---|---|---|---|---|---|
| Supabase auth + RLS | YES (01/02) | YES | PARTIAL | v1 | 0001 schema + 0002 hardening; BUG-026 staff-side RLS only minimum-fixed (0043). Admin path uses `admin_*` SECURITY DEFINER RPCs. |
| Realtime subscriptions | YES (08/13) | YES | UNTESTED | v1 | Migration 0013 (adventure), publication on FIT tables (0036), wall_of_legends_daily, announcements (0032), packages CRUD. |
| FCM push notifications | YES (12) | YES | UNTESTED | v1 | `notify_push_dispatch` trigger (0017); `send-push` Edge Fn; iOS support partial per fcm_setup.dart. |
| Razorpay hold/debit | YES (12) | YES | UNTESTED | v1 | 3 Edge Fns (topup/webhook/reconcile); BUG-004 architecture migrated 0022/0023; cron `session-autocancel-pending-cron` (118 LOC). |
| MSG91 OTP | YES (12) | YES | UNTESTED | v1 | `auth-otp` Edge Fn supports mock + live; BUG-025 fixed mock-mode rate-limit. SMS reactivation channel deferred (no DLT template). |
| MSG91 SMS (other) | YES (12) | PARTIAL | UNTESTED | v1.1 | `send-sms` Edge Fn (149 LOC) exists; SMS birthday-wish channel deferred per SCOPE_LOCKED ("needs MSG91 DLT template"). Push-only at launch. |
| Database migrations | YES (01) | YES | OK | v1 | 0001 → 0044 all present; cleanly numbered; latest 0044_healthy_bite_reminder.sql. |
| Storage buckets | YES (01) | YES | UNTESTED | v1 | ARCHITECTURE-001: marketing public (workshop-photos, menu-photos, package-photos, hero-recaps, hero-cards), user-content private (birthday-photos, child-photos, invoices). Migration 0035 split. |
| Cron jobs | YES (13) | YES | UNTESTED | v1 | birthday-72h-autocancel, birthday-journey-cron, child-birthday-wishes-cron, force-close-grace-sessions, reflection-auto-split-cron, session-autocancel-pending-cron; migration 0024 schedules. |

---

## Section 2 — Synthesis

### 1. Top 3 things that ARE built and working
1. **Birthday funnel + packages end-to-end** — discovery, opt-out (FEATURE-002), reservation lifecycle, package CRUD, PDF gen, journey cron, universal birthday wishes (FEATURE-001) all shipped and bug-flushed (BUG-009 through BUG-018, BUG-027 all FIXED).
2. **Customer wallet hold-then-charge architecture (BUG-004)** — verified via SQL: ₹300 held → released hold → debited cleanly; pending → active flow correct; UI auto-dismisses (BUG-016). Rare to have monetary flows this clean pre-launch.
3. **Admin web Phase 2 (Modules 2.1–2.8)** — every CRUD surface (workshops, coffee, FIT, combos, packages, announcements, content, config) shipped with audit-logged SECURITY DEFINER RPCs. `flutter analyze` clean.

### 2. Top 3 things that should be v1 but are broken / risky
1. **BUG-026 (staff RLS) — only PARTIALLY fixed.** Migration 0043 unblocks login + sessions/orders reads; KDS, menu_availability, walk-in POS, refund, shift-close all still rely on direct table reads with no staff-side policies. Will surface as empty screens or operational misses on Day 1 venue ops.
2. **Staff home navigation is URL-bar only (BUG-031).** Per launch-scope decision this is acceptable for v1 — but it's a real ergonomic regression versus spec; staff need bookmarks or memorised paths. BUG-029 (overflow) is moot only because the grid is gone.
3. **Nothing on this codebase has been end-to-end tested by a real customer/staff/admin since Phase 2 closed.** Phase 1A was customer-only on web; phone testing surfaced BUG-022/023/026/030/031 in one session. Most rows above read "UNTESTED" — that's the honest state.

### 3. Top 3 things that are v1.1 candidates (defer)
1. **Reports/analytics + System health admin screens** — both `ComingSoonScreen` stubs in `admin_router.dart`; no aggregation pipelines, no `system_health_snapshots` cron. Defer until 4-6 weeks of real data lands.
2. **Real artwork** (24 hero cards + 4 birthday cards + World Map + package photos) — already in SCOPE_LOCKED v1.1 list; CONVENTION-001 hero-glyph placeholders carrying the load.
3. **SMS channel for birthday wishes** + **per-child birthday wish toggle** + **notification copy templates UI** + **reactivation campaign defaults** — all deferred from Module 2.8 / FEATURE-001 work; push-only at launch is correct call.

### 4. Anything in SCOPE_LOCKED.md that was missed entirely
- **None of the SCOPE_LOCKED v1 items are coded-zero.** Every Phase 1 / 1A / 2 item shipped. Every v1.1 deferral is intentional and tracked.
- **Pre-launch blockers (Phase 3)**: account deletion shipped (`delete_account_screen.dart` + `farewell_screen.dart`). Pending testing pass, app store metadata, production builds, store submission — all founder-side work, not code.
- **Founder-side parallel tasks** (Razorpay Live KYC, domain, Apple/Google dev accounts, privacy policy finalisation, app icon, beta tester recruitment): outside repo scope, all 🔴/🟡 in SCOPE_LOCKED.
- **Open BUGs that should be triaged before launch**: BUG-024 (profile FilledButton width — cosmetic, OPEN), BUG-026 (staff RLS — PARTIAL, BLOCKER for non-fixed surfaces), BUG-030 (stat tiles contrast — OPEN, awaiting on-device confirmation).
