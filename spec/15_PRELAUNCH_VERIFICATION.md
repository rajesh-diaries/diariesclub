# Session 15 — Pre-Launch Verification Runbook

> Final session in the spec. This is NOT a build session — it's a runbook to execute in the days before going live.

---

## What This Is

A linear, ordered checklist that takes you from "code is done" to "real customers are using the app." Run through this in order on the day(s) before public launch.

Designed to be done by **one person** (you) over **2-3 days**. Each step has clear pass/fail criteria. If anything fails, fix before moving on.

---

## Pre-Flight (Do Before Starting)

Before running this checklist, confirm:

- [ ] All 14 prior session files have been executed and code is built
- [ ] Pre-Launch Checklist Tier 1 + Tier 2 are 90%+ complete (illustrations may still be in progress, that's OK)
- [ ] You have access to: Supabase production project, Razorpay live dashboard, MSG91 dashboard, Apple Developer, Google Play Console, Firebase, Branch.io, GitHub repo, domain hosting
- [ ] You have a "test customer" phone (your own personal number works)
- [ ] You have at least one test physical device for iOS AND one for Android (or simulators)
- [ ] You have ~6-8 hours blocked on launch day

---

## Phase 1 — Production Database Setup

### 1.1 Create production Supabase project

```
☐ Sign in to https://supabase.com
☐ New project: "Diaries Club Production"
☐ Region: Mumbai (ap-south-1) — closest to Hyderabad
☐ Database password: generate strong, save in 1Password
☐ Wait for provisioning (~2 min)
☐ Save URL + anon key + service_role key in 1Password
```

### 1.2 Apply all migrations in order

```
☐ Connect to production DB via psql or Supabase SQL editor
☐ Run migrations in order:
   - 0001_initial_schema.sql
   - 0002_rpc_functions.sql
   - 0003_reflection_moments_expanded.sql
   - 0004_birthday_simplification.sql
   - 0005_staff_app.sql
   - 0006_admin_users.sql
   - 0007_otp_codes.sql
   - 0008_notify_push_trigger.sql
   - 0009_reactivation_redeem.sql
   - 0010_pgtap.sql
☐ Verify: every migration completes without errors
☐ Verify: all RLS policies active (run \d on a few tables)
```

### 1.3 Seed initial data

```
☐ Verify the venue row exists (Kondapur)
☐ Update venue with REAL phone, address, WhatsApp number
☐ venue_config row populated
☐ All 24 reflection_moments rows present (run SELECT COUNT(*))
☐ 3 birthday_packages with REAL pricing
☐ Hero card definitions: at minimum 4 cards (one per hero) for v1 launch
☐ Initial menu_items, menus for Coffee + FIT
☐ Initial combos (2-3 from Tier 2 founder decisions)
```

### 1.4 Run pgTAP suite against production

```
☐ Run scripts/run-pgtap.sh against production DB
☐ All tests pass — DB is correctly migrated
☐ Tests roll back cleanly (no production pollution)
```

### 1.5 Create first admin user

```
☐ Sign up in admin web with your email
☐ Manually run SQL: 
    INSERT INTO admin_users (auth_user_id, name, email, role)
    VALUES ('<your-uid>', 'Founder', 'you@diariesclub.com', 'super_admin');
☐ Verify: sign in to admin web → reaches dashboard
```

### 1.6 Create first tablet device

```
☐ Admin web → Users → Add tablet
☐ Label: "Kondapur Front Desk"
☐ Save credentials shown ONCE in 1Password (you can't view again)
☐ On the actual tablet: install staff app build, sign in with credentials
☐ Verify: lands on staff home dashboard
```

### 1.7 Create initial staff PINs

```
☐ For each venue staff member, admin web → add staff
☐ Set name, phone, role, initial PIN
☐ Save PIN to share securely with each staff (NOT via SMS — verbally or sealed envelope)
☐ Verify: staff signs in via tablet, enters PIN, sees home
☐ Staff confirms PIN works for at least one action (e.g., access KDS)
```

---

## Phase 2 — External Services Configuration

### 2.1 Razorpay live keys

```
☐ Razorpay dashboard → Activate live mode (per Pre-Launch 1.2)
☐ Generate live API keys (rzp_live_*)
☐ Save in production env file: env/prod.json
☐ Update prod build: --dart-define-from-file=env/prod.json
☐ Verify build: assertSafeRazorpayKeys passes (live keys allowed in prod only)
☐ Configure webhook URL: https://<prod-project>.supabase.co/functions/v1/razorpay-webhook
☐ Save webhook secret in Supabase Edge Function env: RAZORPAY_WEBHOOK_SECRET
☐ Subscribe to events: payment.captured, payment.failed, refund.processed, refund.failed, order.paid
☐ Add Privacy/Terms/Refund Policy URLs in Razorpay dashboard
☐ TEST: do a tiny live transaction (₹10) → verify webhook fires → wallet credited
☐ TEST: refund the ₹10 from Razorpay dashboard → refund.processed fires → handled
```

### 2.2 MSG91 production setup

```
☐ MSG91 dashboard: confirm sender ID approved (DIARYC or whatever)
☐ Confirm all DLT templates approved (per Session 12 §2.3 list)
☐ Save auth key in Supabase Edge Function env: MSG91_AUTH_KEY, MSG91_SENDER_ID
☐ Note template IDs for each — store in venue_config.sms_templates JSON or env
☐ TEST: send OTP to your own phone via send-otp Edge Function → received within 10s
☐ TEST: send-sms to your phone with reactivation template + a Branch link
```

### 2.3 Firebase production

```
☐ Firebase project: confirm both iOS + Android apps configured
☐ APNs auth key uploaded for iOS
☐ google-services.json + GoogleService-Info.plist in production builds
☐ FCM server key in Supabase Edge Function env: FCM_SERVER_KEY
☐ TEST: install customer app on physical iOS device → sign in → push test
☐ TEST: same on Android device
```

### 2.4 Branch.io production

```
☐ Branch dashboard: confirm app linked to production iOS bundle + Android package
☐ Universal Links setup (Branch hosts apple-app-site-association)
☐ Production Branch Key in env/prod.json
☐ TEST: generate a Branch link via app, click on a phone WITHOUT app installed
☐ App Store / Play Store opens with correct app
☐ Install + open → app routes to expected /welcome-back or /refer route
☐ TEST: same flow on already-installed device
```

### 2.5 Sentry production

```
☐ Sentry projects created: customer-prod, admin-prod, staff-prod, edge-prod
☐ DSNs in respective env files
☐ TEST: trigger a deliberate error → appears in Sentry within 30s
☐ TEST: PII stripping working (no phone/name/child name in event payloads)
☐ Configure alerts: critical errors → email/Slack to founder
```

---

## Phase 3 — Edge Functions Deployment

### 3.1 Deploy all 15 Edge Functions

```
☐ supabase functions deploy razorpay-webhook
☐ supabase functions deploy razorpay-reconcile
☐ supabase functions deploy verify-session-qr
☐ supabase functions deploy generate-session-qr
☐ supabase functions deploy force-close-grace-sessions
☐ supabase functions deploy reflection-auto-split-cron
☐ supabase functions deploy birthday-journey-cron
☐ supabase functions deploy wall-of-legends-aggregate
☐ supabase functions deploy system-health-snapshot
☐ supabase functions deploy send-push
☐ supabase functions deploy send-sms
☐ supabase functions deploy send-otp
☐ supabase functions deploy verify-otp
☐ supabase functions deploy reactivation-blast
☐ supabase functions deploy generate-hero-recap
☐ supabase functions deploy generate-invoice-pdf
☐ supabase functions deploy admin-impersonate-token
```

### 3.2 Set all secrets

```
supabase secrets set RAZORPAY_KEY_ID="rzp_live_..."
supabase secrets set RAZORPAY_KEY_SECRET="..."
supabase secrets set RAZORPAY_WEBHOOK_SECRET="..."
supabase secrets set MSG91_AUTH_KEY="..."
supabase secrets set MSG91_SENDER_ID="DIARYC"
supabase secrets set FCM_SERVER_KEY="..."
supabase secrets set BRANCH_KEY="key_live_..."
supabase secrets set QR_SIGNING_KEY="<random 64 chars>"
supabase secrets set SENTRY_DSN_EDGE="..."
supabase secrets set ENV="production"
```

### 3.3 Verify cron schedules

```
☐ Supabase dashboard → Database → Cron jobs
☐ Each scheduled function shows next run time:
   - razorpay-reconcile every 15 min
   - force-close-grace-sessions every minute
   - reflection-auto-split-cron every hour
   - birthday-journey-cron daily 03:30 UTC
   - wall-of-legends-aggregate daily 19:00 UTC
   - system-health-snapshot every 5 min
☐ Wait 5-15 min, verify first runs succeed (check logs)
```

---

## Phase 4 — Build & Deploy Apps

### 4.1 Customer iOS

```
☐ Open ios/Runner.xcworkspace in Xcode
☐ Verify version + build number set correctly (1.0.0+1)
☐ Verify GoogleService-Info.plist in ios/Runner/
☐ Archive build with prod flavor and prod env
☐ Upload to App Store Connect via Xcode
☐ App Store Connect: complete listing (per Pre-Launch 3.1)
   - All screenshots uploaded
   - Description, keywords, support URL, privacy URL
   - Age rating questionnaire
   - Pricing: Free
   - Submit for review
☐ Note: First review can take 2-7 days
```

### 4.2 Customer Android

```
☐ flutter build appbundle --flavor prod -t lib/main_prod.dart \
     --dart-define-from-file=env/prod.json \
     --release
☐ Output: build/app/outputs/bundle/prodRelease/app-prod-release.aab
☐ Upload to Play Console → Internal Testing track
☐ Recruit 20 testers for closed testing (friends/family)
☐ Once 20 testers confirmed, promote to Production track
☐ Complete Data Safety form (declare every type of data collected)
☐ Complete content rating questionnaire
☐ Submit for review
☐ Note: Google review can take 1-3 days; sometimes longer for first submission
```

### 4.3 Staff app

```
☐ flutter build apk --flavor staffProd -t lib/main_staff_prod.dart \
     --dart-define-from-file=env/staff_prod.json --release
☐ Install APK directly on venue tablet (no Play Store needed for v1)
☐ TEST: tablet login works, PIN sheet appears, all actions functional
☐ Generate test session via customer app → scan QR via staff app → success
```

### 4.4 Admin web

```
☐ flutter build web --flavor adminProd -t lib/main_admin_prod.dart \
     --dart-define-from-file=env/admin_prod.json --release
☐ Output: build/web/
☐ Deploy to Cloudflare Pages / Vercel / Netlify
☐ Configure custom domain (e.g., admin.diariesclub.com)
☐ Verify HTTPS working
☐ TEST: open admin URL → sign in → navigate all 13 sections
☐ Configure access control (only your IP if extra cautious, or just rely on auth)
```

### 4.5 Marketing site

```
☐ diariesclub.com static site live
☐ /privacy page accessible
☐ /terms page accessible
☐ /refund-policy page accessible
☐ All 3 URLs return 200 from any browser
☐ Mobile responsive (Apple/Google may check)
```

---

## Phase 5 — Smoke Test (The Most Important Phase)

Walk through every critical flow with REAL services + REAL data, on REAL devices.

### 5.1 Onboarding flow (1 hour)

```
☐ Use a fresh phone OR delete app + clear all data
☐ Open app → splash → phone entry
☐ Enter your phone number (real)
☐ Receive OTP via SMS within 10s
☐ Enter OTP → success → family name screen
☐ Enter name → continue
☐ Add child screen → tap "Add child"
☐ Fill child details → continue → hero pick
☐ Pick a hero → "Start the adventure!"
☐ Lands on Home with welcome tour
☐ DB check: families row exists with id = auth.uid(), wallet auto-created
☐ DB check: children row created with selected favourite_hero
```

### 5.2 Wallet top-up (30 min)

```
☐ Home → tap wallet → top up sheet
☐ Pick ₹500 quick tile → "Pay ₹500"
☐ Razorpay opens with prefilled phone
☐ Use a REAL card (test mode or real with ₹10 amount for safety)
☐ Complete payment
☐ Wallet card updates within 5s to show new balance
☐ DB check: wallet_transactions row, balance_paise correct
☐ DB check: razorpay_payment_id captured
☐ Notification on Home: "Wallet topped up"
```

### 5.3 Session lifecycle (45 min)

```
☐ Home → "Start session" → 1hr → wallet → pay
☐ QR screen appears, brightness boosted
☐ DB check: session row, status='active', expires_at set
☐ Take tablet → scan QR via staff app (PIN required)
☐ Staff sees check-in success screen
☐ Customer Home shows active timer
☐ Wait 1 min, verify timer counts down accurately
☐ Test extend: tap Extend → 30 min → wallet → confirm
☐ Wallet debited, expires_at updated
☐ Force timer to expiry: in DB, set expires_at = now() - INTERVAL '1 sec'
☐ Customer Home flips to GRACE state (yellow)
☐ Wait grace_max_minutes (or simulate by setting grace_force_close_at to past)
☐ force-close-grace-sessions cron fires → status='auto_closed'
☐ Customer Home returns to idle
☐ generate-hero-recap fires (or trigger manually)
☐ hero_recaps row created
```

### 5.4 Reflection ritual (15 min)

```
☐ With recap pending: Home shows hero recap card
☐ Tap → reflection screen
☐ See 12 cards (3 per trait)
☐ Tap 4 cards (mix of traits)
☐ Tap Continue → submit
☐ DB check: reflection_status='reflected', xp_events row with split
☐ DB check: children.xp_rafi/ellie/gerry/zena updated
☐ If any stage transitions: Lottie animation plays
☐ Returns to Home, recap card gone
```

### 5.5 Order flow (15 min)

```
☐ Club tab → Coffee → add 2 items
☐ Cart shows COFFEE section, 2 items
☐ Switch to FIT, add 1 item
☐ Cart now has both sections
☐ Tap cart icon → bottom sheet
☐ Place order via wallet
☐ Status='preparing'
☐ Staff KDS: order appears in Pending tab
☐ Staff: mark preparing → preparing tab
☐ Customer order tracking screen updates
☐ Mark ready → push notification fires
☐ Mark served → done
☐ DB check: wallet_transactions order_debit row, GST + coins correct
```

### 5.6 Birthday funnel (30 min)

```
☐ Home: birthday card visible (if child birthday < 90 days)
☐ Tap → Discovery screen
☐ Tap "See packages" → 3 packages visible
☐ Tap a package → detail screen
☐ Fill preferences (rough month, kids count, adults count)
☐ Tap "Reserve interest"
☐ DB check: birthday_reservations row, status='interested'
☐ Auto-navigates to status screen
☐ Status header: "Reservation request received"
☐ Admin web: birthday CRM shows new card in INTERESTED column
☐ Admin clicks → drawer → "Mark contacted"
☐ Customer status updates (Realtime)
☐ Admin: "Confirm date" dialog → enter date → confirmed
☐ Customer status: "You're confirmed! 🎉"
☐ Admin: "Mark completed" → birthday_reservation_complete fires
☐ DB check: hero_card_collection row added (birthday-exclusive)
☐ Customer Adventure → Cards: birthday card visible with cake icon
```

### 5.7 Healthy bite + card unboxing (10 min)

```
☐ Find a session with healthy_bite_earned=true
☐ Staff: Healthy Bite tab → tap distribute → PIN → success
☐ healthy_bite_distribute fires → hero_card_collection row + notification
☐ Customer notification arrives
☐ Customer taps notification → unboxing screen
☐ Tap to reveal → flip animation, card visible
☐ "See all cards" → Adventure tab → cards grid → new card visible
```

### 5.8 Workshop flow (15 min)

```
☐ Admin: schedule a workshop with 1 spot for testing
☐ Customer: Club → Workshops → see workshop
☐ Tap → detail screen → register → wallet payment
☐ DB check: workshop_registrations row, spots_remaining=0
☐ With second account: try to register → "Workshop full" error
☐ First account: cancel registration
☐ DB check: spot restored, refund row added, wallet credited
☐ Second account: register → succeeds
```

### 5.9 Refund flow (10 min)

```
☐ Staff: refund of ₹400 (under ₹500 cap)
☐ PIN check
☐ refund_issue fires, status='completed' (auto-approved)
☐ Customer wallet credited within seconds
☐ Customer notification arrives
☐ Staff: refund of ₹800 (over cap)
☐ Status='pending'
☐ Customer wallet NOT credited
☐ Admin web: Refunds queue → see pending → approve
☐ Customer wallet credited
☐ Audit log captures both flows
```

### 5.10 End-of-shift (5 min)

```
☐ Staff: tap End shift → reconciliation screen
☐ Expected cash auto-computed
☐ Enter counted cash (intentionally with discrepancy)
☐ Submit → shift_close fires
☐ DB check: shift_logs row, discrepancy logged
☐ If >₹100 discrepancy, admin alert in Sentry
```

### 5.11 Reactivation campaign (TEST FIRST!)

```
☐ Admin: Reactivation → upload TEST CSV (5 contacts including your own phone)
☐ Preview shows 5 valid rows
☐ Click "Send to my phone first"
☐ Verify SMS arrives at your phone with Branch link
☐ Click link on phone WITHOUT customer app installed
☐ App Store / Play Store opens
☐ Install app
☐ Open → splash routes to /auth/phone
☐ Enter phone → OTP → onboarding
☐ After OTP, reactivation_redeem fires → ₹200 credited
☐ Wallet card on Home shows ₹200
☐ DB check: reactivation_contacts.redeemed_at populated
☐ ONLY THEN: do the full 2,000-contact blast
```

---

## Phase 6 — Final Cleanup

### 6.1 Verify no test data in production

```
☐ Run: SELECT * FROM families WHERE name = 'Test Family';
☐ Delete any obvious test rows
☐ Same for: children, sessions, orders, workshop_registrations
☐ Wallet test transactions should also be cleaned (or at least documented)
☐ Run: SELECT COUNT(*) FROM <each table> — sanity check counts are realistic
```

### 6.2 Configure monitoring alerts

```
☐ Sentry: critical errors → email + Slack
☐ Sentry: P95 latency > 2s → alert
☐ Razorpay reconciliation > ₹1,000 mismatch → alert
☐ Push delivery rate < 80% → alert
☐ Auto-closed sessions > 5/day → admin awareness
```

### 6.3 Backup verification

```
☐ Supabase: Daily automated backups enabled
☐ Manually trigger backup, download
☐ Test restore to a sandbox project
☐ Confirm data restorable
☐ Document restore procedure in /docs/runbooks/restore.md
```

### 6.4 First production audit log review

```
☐ Admin web → Audit Log
☐ Filter: last 24 hours
☐ Verify: every action you did during smoke test is logged
☐ Spot-check: actor_id, entity_type, new_value all populated
☐ No suspicious entries (e.g., actions you didn't perform)
```

---

## Phase 7 — Quiet Launch (Locked Decision)

Per founder decision: no marketing push, no social media. Just open the gates.

### 7.1 Day of quiet launch

```
☐ Confirm both apps live on stores
☐ Run reactivation blast to ~2,000 paper-book contacts
☐ Monitor System Health dashboard for first 4 hours
☐ Watch Sentry for any spike in errors
☐ Watch Razorpay dashboard for transaction patterns
☐ Be available on WhatsApp support line
```

### 7.2 First-week metrics to track

Daily check-in on these:

| Metric | Source | Healthy range (Week 1) |
|---|---|---|
| App installs | App Store + Play Store | 50+ |
| Active families/week | DB query: families with login in last 7d | 20+ |
| Total wallet load | Sum balance_paise + topups | ₹50K+ |
| Sessions started | sessions count | 30+ |
| Birthdays inquired | birthday_reservations status='interested' | 1+ |
| Push delivery rate | system_health_snapshots | >90% |
| Sentry errors | Sentry dashboard | <20/day, mostly P3 |
| Razorpay reconciliation | reconciliation_log | All success |

If any metric is alarming after 48 hours, investigate and decide:
- Hot-fix and continue
- Pause reactivation campaign
- Roll back via app version downgrade (Apple/Google can do this)

### 7.3 Daily standup with yourself

For Week 1, run this 15-min daily checklist:

```
1. Sentry: any new error spikes?
2. Reconciliation: any mismatches > ₹1,000?
3. Push delivery: still > 90%?
4. Birthday CRM: any inquiries waiting > 24h?
5. Refund queue: anything pending?
6. WhatsApp: any unanswered support messages?
7. Wallet: total liability acceptable? (sum of all balances)
8. New family signups: trend healthy?
9. Active sessions: any stuck (force_close cron working)?
10. App store reviews: any patterns?
```

---

## Phase 8 — When Things Go Wrong

### 8.1 Hot fix workflow

If a critical bug surfaces post-launch:

```
1. Acknowledge in Sentry
2. Assess severity (P0 = data loss, P1 = unusable feature, P2/3 = annoyance)
3. P0: Use admin web "force update" to push version bump:
   - Set venue_config.ios_min_supported_version = current + 1
   - Customer app will gate to update screen
   - Submit fixed build to App Store/Play Store as urgent review
4. P1: Patch backward-compat, push to next regular release
5. P2/3: Note for next sprint
```

### 8.2 Money discrepancy procedure

If reconciliation_log shows a real mismatch:

```
1. STOP — don't make manual changes yet
2. Pull the affected family + transactions
3. Cross-check against Razorpay dashboard
4. Compute the correct expected balance from txn history
5. If discrepancy < ₹100, log to audit and adjust manually via manual_wallet_adjust
6. If discrepancy ≥ ₹100, Sentry alert + WhatsApp customer to apologise + correct
7. Document root cause in /docs/incidents/
```

### 8.3 Push notifications stop delivering

```
1. Check FCM dashboard — quotas, errors
2. Verify notify_push trigger still firing
3. Verify Edge Function send-push not erroring (Sentry)
4. Worst case: push is best-effort. In-app inbox remains. No customer impact.
5. Fix at next deploy cycle
```

---

## Done

When you've completed all phases:

```
☐ Apps live on both stores
☐ All critical flows tested end-to-end
☐ Reactivation blast complete or scheduled
☐ Monitoring active
☐ Audit log clean
☐ You can sleep tonight 😴
```

---

## Open Items (Founder Sign-off)

- [ ] Confirm "quiet launch" approach (no marketing first 2 weeks)
- [ ] Confirm metrics dashboard cadence (daily Week 1, weekly thereafter)
- [ ] Decide first feature requests / iteration priorities
- [ ] Schedule first retro: 2 weeks post-launch

---

## What Happens Next

Post-launch is its own world:
- Week 1: monitor + fix
- Weeks 2-4: gather feedback, prioritize v1.1 features
- Month 2-3: build v1.1 (e.g., wireframed-but-not-built features deferred from v1)
- Month 3+: explore multi-venue, advanced analytics, deeper personalisation

But that's another spec, another time.

**Welcome to launch day.**
