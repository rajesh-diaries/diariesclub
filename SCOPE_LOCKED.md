# Diaries Club v1 — Scope Status

## Lock date and target
- Initial scope locked: 2026-05-05 (Day 3)
- Target launch: ~Day 18-22 from initial lock (~May 22-26, 2026)

## Status

### Phase 1 — Build (COMPLETE)
Customer app, staff app, admin web foundations + business logic. See lib/BUGS.md and original spec/ folder for details.

### Phase 1A — Fix-batch (COMPLETE, 2026-05-05)
12 bugs fixed (BUG-004 through BUG-018) + 2 features:
- FEATURE-001: Universal birthday wishes (push-only for v1)
- FEATURE-002: Birthday interest opt-out (per child)
Architectural changes:
- BUG-004: Hold-then-charge sessions (wallet held → debit on staff scan)
- BUG-018: Smart birthday card on home (rich/discovery/no-card variants)

### Phase 2 — Admin CRUD + Configurability (COMPLETE, 2026-05-06)
All 8 modules + 2 follow-ups shipped:
- Module 2.1: View-only stubs
- Module 2.2: Workshops CRUD with photo upload + push fan-out
- Module 2.3: Announcements with workshop auto-create + customer home feed
- Module 2.4: Coffee Diaries menu CRUD
- Module 2.5: FIT meal builder (Pattern 1 normalized, ~12-14h shipped on estimate)
- Module 2.6: Combos CRUD with multi-item picker + savings indicator
- Module 2.7: Birthday packages rich CRUD + PDF generation Edge Function
- Module 2.8: Config admin UI (11 sections + content CRUD)
Plus follow-ups:
- ARCHITECTURE-001: Storage bucket public/private split (marketing public, sensitive private with signed URLs)
- Cart unification: heterogeneous client cart with menu_item/combo/fit_meal types

### Phase 3 — Pre-launch (PENDING)
- Account deletion feature (~2-3h, MANDATORY for App Store + Play Store)
- Staff app phone-only refactor (DECISION-001, +1-2 days)
- Pre-launch testing pass
- App store metadata (descriptions, screenshots, keywords)
- Production builds (iOS + Android)
- Submit to stores
- Store review (3-7 days each)

### Deferred to v1.1
- Notification copy templates UI
- Reactivation campaign defaults
- Per-child birthday wish toggle
- SMS channel for birthday wishes (needs MSG91 DLT template)
- Cart persistence across app restarts
- Bulk operations on admin lists
- CSV export from admin
- Daily admin digest email
- Real-time alerts dashboard
- Skeleton loaders, custom animations, onboarding coachmarks
- Dark mode, multi-language
- A/B testing infrastructure
- Real artwork (24 hero cards, 4 birthday cards, World Map, package photos)

## Real-world parallel tasks (founder responsibility)
- 🔴 Razorpay Live KYC submission (3-7 day approval)
- 🔴 Domain registration (diariesclub.com or .in)
- 🔴 Apple Developer account ($99, 24-48h)
- 🔴 Google Play Developer ($25, instant)
- 🟡 Privacy Policy + Terms (drafts exist, need finalization)
- 🟡 App icon design (Fiverr, 3-7 days)
- 🟡 Beta tester recruitment

## Discipline rules
- No scope additions during build without explicit decision and timeline impact
- New ideas → v1.1_BACKLOG.md, NOT into v1
- Daily entry in BUILD_LOG.md
- Cut from bottom (deferred items first) if behind, don't extend timeline

## Key architectural decisions (locked)
See lib/BUGS.md for full rationale on each.
- GST: 18% INCLUSIVE everywhere in app, 5% exclusive walk-in food only
- Hold-then-charge sessions (BUG-004)
- Universal birthday wishes regardless of opt-out (FEATURE-001 + FEATURE-002)
- FIT meal builder: normalized schema (Pattern 1)
- Storage buckets: marketing public, user content private with signed URLs
- Cart: heterogeneous client-side with type discriminator
- DECISION-001 (2026-05-06): Staff app phone-only, not shared tablet — landscape lock removed, app renamed, +1-2d Phase 3
