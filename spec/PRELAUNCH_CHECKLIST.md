# Diaries Club — Pre-Launch Checklist

> **Single source of truth for everything outside the codebase.** Tracks every external account, document, asset, and service Diaries Club needs before launch. Most items have lead times. Start the long ones today.

**Status legend:**
- 🔴 NOT STARTED
- 🟡 IN PROGRESS
- 🟢 DONE
- ⚪ NOT NEEDED YET

**Last updated:** 2026-05-03

---

## How to use this document

1. Items are grouped by **urgency tier** — start Tier 1 today.
2. Each item has a **lead time** (how long external parties take) and a **dependencies** list (what must happen first).
3. Update the status emoji as you complete items. Add notes inline.
4. The "What done looks like" line is your acceptance test — only mark green when that's true.
5. Total estimated cost (rough INR) at the bottom of each tier.

---

# Tier 1 — Start Today (long lead time, blocks launch)

These items take 3–14 days because external parties are involved. If you don't start them now, they become the bottleneck later.

---

## 1.1 🔴 MSG91 DLT Registration

**What it is:** Indian regulatory requirement to send transactional/promotional SMS through any provider. Without it, your SMS messages will not deliver to Indian phones.

**Why it blocks launch:** OTP login + reactivation SMS campaign + birthday journey SMS reminders all depend on this.

**Lead time:** 3–7 working days for approval after submission.

**Cost:** ₹0 platform fee + per-SMS pricing (~₹0.18 per transactional SMS).

**Dependencies:**
- GSTIN registered (see 1.6)
- Business name registered (proprietorship or Pvt Ltd certificate)
- PAN of business

**Steps:**
1. Sign up at https://msg91.com → choose India region
2. Complete KYC (upload PAN, GST certificate, business proof)
3. Register **Sender ID** (6-character alphanumeric, e.g., "DIARYC")
4. Register **DLT Principal Entity** at https://www.dltconnect.in (or any of the four telecom DLT portals — Jio, Airtel, Vi, BSNL)
5. Register **SMS templates** for each message type:
   - OTP login: "Your Diaries Club code is {{1}}. Valid for 10 minutes."
   - Reactivation: "Welcome back to Play Diaries! ₹200 has been added to your account..."
   - Birthday D-30: "{{1}}'s birthday is just 30 days away..."
   - (Full list in Tier 2 spec)
6. Wait for telecom approval per template (24–72h each)
7. Get API credentials (Auth Key) → save in `1Password` or similar

**What done looks like:**
- Test SMS delivers to your own phone
- All ~10 templates approved
- API credentials in hand for Edge Functions to use

**Notes:**
- ⚠️ DLT process is bureaucratic but mandatory — do NOT use Twilio or similar for India SMS, they don't comply with TRAI regs
- Templates are case-sensitive and any change = re-approval (so design templates carefully upfront)

---

## 1.2 🔴 Razorpay Account + Live Keys

**What it is:** Payment gateway for wallet top-ups, birthday deposits, and order payments.

**Why it blocks launch:** Without live keys, no real money flows. Test keys work for development only.

**Lead time:** 2–5 working days for activation review.

**Cost:** Setup free. Per-transaction fees: ~2% domestic cards, ~3% international, ~0.4% UPI.

**Dependencies:**
- Business PAN
- GSTIN
- Bank account (current account in business name preferred)
- Cancelled cheque or bank statement
- Business address proof

**Steps:**
1. Sign up at https://razorpay.com → "Accept payments"
2. Complete KYC: upload all documents above
3. Add bank account for settlements
4. Wait for activation (you can use **test keys** during this time for dev)
5. Once activated, get **live API keys** (KeyID + Secret)
6. Configure webhook URL: `https://<your-supabase-project>.functions.supabase.co/razorpay-webhook` (needs Tier 2 build first to deploy)
7. Set webhook secret → save in `1Password`
8. Configure refund settings: enable instant refunds for UPI/cards
9. Add **Refund/Cancellation Policy URL**: `diariesclub.com/refund-policy` (see 1.5 — required by RBI)
10. Add **Privacy Policy URL** + **Terms URL** (see 1.5)

**What done looks like:**
- Test transaction in test mode succeeds
- Live keys activated and saved securely
- Webhook URL registered (can't be tested until Edge Functions deployed)

**Notes:**
- Test keys: `rzp_test_*` — already configured in spec
- Live keys: `rzp_live_*` — only used in prod flavor build
- The compile-time guard in `flavors.dart` prevents accidentally shipping test keys to prod

---

## 1.3 🔴 Privacy Policy + Terms of Service + Refund Policy

**What it is:** Legal documents required by Apple App Store, Google Play Store, RBI (for Razorpay), and DPDP Act 2023 (Indian data protection law).

**Why it blocks launch:** App Store and Play Store reject submissions without a public Privacy Policy URL. Razorpay requires a Refund Policy URL.

**Lead time:** 5–7 days (legal drafting + your review).

**Cost:** ₹3,000–10,000 via legal services like Vakilsearch, LegalDocs, or local Hyderabad lawyer.

**Dependencies:** None.

**Steps:**
1. Engage a legal service or lawyer. Brief them on:
   - **Audience:** parents in India (DPDP Act applies)
   - **Data collected:** phone, name, email, child name + DOB, photos, payment details (via Razorpay), location (venue check-in only), device info, FCM tokens
   - **Special category:** children's data — DPDP Act requires explicit guardian consent + special handling
   - **Storage:** Supabase (servers in India region preferred — confirm with Supabase support)
   - **Third parties:** Razorpay (payments), MSG91 (SMS), Branch.io (deep links), Sentry (error tracking), Firebase (push notifications)
   - **Retention:** wallet_transactions kept indefinitely for tax audit; other data anonymised on account deletion
   - **Marketing:** opt-in only, default unchecked
2. Get drafts of:
   - Privacy Policy
   - Terms of Service
   - Refund & Cancellation Policy
3. Review and request changes (read every line — you're liable for what's in there)
4. Get final signed-off versions

**Hosting (immediate, ₹0):**
1. Buy domain `diariesclub.com` if not already (~₹800/year on GoDaddy/Namecheap)
2. Use simple static hosting:
   - **Easiest:** GitHub Pages (free) + Cloudflare DNS
   - **Alternative:** Vercel (free) or Netlify (free)
3. Create three pages:
   - `diariesclub.com/privacy`
   - `diariesclub.com/terms`
   - `diariesclub.com/refund-policy`
4. Use simple HTML — no need for a fancy site, just readable legal text

**What done looks like:**
- All three URLs publicly accessible without login
- URLs added to Razorpay account (1.2)
- URLs ready to add to App Store + Play Store submissions
- PDF copies stored locally for reference

**Notes:**
- ⚠️ DPDP Act 2023 is in force. Standard "boilerplate" privacy policies won't pass — make sure your lawyer is current on DPDP, not just GDPR
- The 18+ guardian declaration in your onboarding flow needs to align with what's in the Privacy Policy

---

## 1.4 🔴 Apple Developer Account

**What it is:** Required to publish iOS app to the App Store.

**Why it blocks launch:** Without this, no iOS app.

**Lead time:** 1–2 days for signup approval. **Initial 24-48h verification call from Apple.**

**Cost:** US$99/year (~₹8,300/year).

**Dependencies:**
- Apple ID (personal or business)
- Credit card for annual fee
- D-U-N-S number if registering as a company (free, takes 5 days from Dun & Bradstreet — for individual/proprietorship, not needed)

**Steps:**
1. Go to https://developer.apple.com → Enroll
2. Choose **Individual** (proprietorship-friendly, fastest) OR **Organization** (Pvt Ltd with D-U-N-S)
3. Pay annual fee
4. Wait for Apple verification (they may call to confirm identity)
5. Once active:
   - Create App ID for `com.diariesclub.app`
   - Configure Push Notification capability
   - Create distribution certificates
   - Set up App Store Connect listing (placeholder for now — final assets in Tier 3)

**What done looks like:**
- Account active in Apple Developer dashboard
- App ID created
- App Store Connect record exists (empty)

**Notes:**
- ⚠️ Individual accounts show your personal name as the developer in App Store — fine for v1, can be migrated to organization later
- App Store review for first submission can take 2–7 days; subsequent updates are faster

---

## 1.5 🔴 Google Play Console Account

**What it is:** Required to publish Android app to Google Play.

**Why it blocks launch:** Without this, no Android app (the bigger market in India).

**Lead time:** 2–3 days for signup verification.

**Cost:** US$25 one-time (~₹2,100), no annual renewal.

**Dependencies:** Google account + credit card.

**Steps:**
1. Go to https://play.google.com/console → Sign up
2. Pay one-time fee
3. Complete identity verification (may require ID upload)
4. Create app: package name `com.diariesclub.app` (must match Apple)
5. Set up listing details (placeholder for now)

**What done looks like:**
- Account active
- App created in Play Console
- Internal testing track ready (where you'll first deploy)

**Notes:**
- Google requires **20 testers** for closed testing if you want production release. Plan to recruit early — friends, family, your team
- Privacy Policy URL is required for any app collecting user data

---

## 1.6 🔴 GSTIN + Business Setup

**What it is:** Goods and Services Tax registration. Required for B2C transactions, invoicing, and many other registrations above (Razorpay, MSG91).

**Why it blocks launch:** Without GSTIN, you can't legally charge GST on orders, can't get fully activated on Razorpay/MSG91, can't issue compliant invoices.

**Lead time:** 7–15 working days.

**Cost:** ₹0 government fee. ₹500–2,000 if using a CA/agent.

**Dependencies:**
- PAN (yours or business's)
- Aadhaar
- Bank account
- Business address proof (rent agreement or NOC from owner)
- Photo

**Steps:**
1. Apply at https://www.gst.gov.in/ → New Registration
2. Choose:
   - **Proprietorship** (fastest, simplest, individual liability)
   - OR **Pvt Ltd** if planning to raise funds — but this requires MCA registration first (15+ days)
3. Submit documents
4. Wait for ARN (acknowledgement) within 24h
5. Verification by GST officer (~7–15 days)
6. GSTIN issued
7. Set up:
   - HSN/SAC codes for your services (entertainment services SAC: 998555)
   - GST rate: 18% on entertainment / 5% on food (FIT Diaries)

**What done looks like:**
- GSTIN certificate downloaded
- HSN codes configured
- Ready to print on invoices

**Recommendation:** Use a local CA or service like ClearTax/Vakilsearch — saves time vs DIY.

**Notes:**
- ⚠️ For your venue's gross revenue, GST registration is mandatory above ₹20 lakh annual turnover. Even below that, Razorpay and your wholesale food suppliers will likely require GSTIN
- GST returns must be filed monthly/quarterly once registered — engage a CA for this

---

## 1.7 🔴 Firebase Project + Configuration Files

**What it is:** Backend for push notifications (FCM) and Crashlytics if used.

**Why it blocks launch:** Push notifications are the primary engagement layer for the app. Without FCM setup, no notifications.

**Lead time:** 1 hour (technical setup).

**Cost:** Free for FCM at our scale.

**Dependencies:** Google account.

**Steps:**
1. Go to https://console.firebase.google.com → Create project
2. Project name: `Diaries Club`
3. Disable Google Analytics for Firebase (you don't need it; Sentry handles errors)
4. Add iOS app:
   - Bundle ID: `com.diariesclub.app`
   - Download `GoogleService-Info.plist`
   - Save to repo: `ios/Runner/GoogleService-Info.plist`
5. Add Android app:
   - Package name: `com.diariesclub.app`
   - SHA-1 fingerprint (from your debug + release keystores)
   - Download `google-services.json`
   - Save to repo: `android/app/google-services.json`
6. Generate FCM **Server Key** (Cloud Messaging tab) → save in Supabase Edge Function environment variables
7. Configure APNs:
   - Generate APNs Auth Key in Apple Developer Portal
   - Upload to Firebase Cloud Messaging settings
   - Required for iOS push to work

**What done looks like:**
- Both config files in repo (gitignored if they contain secrets)
- FCM server key added to Supabase Edge Function env vars
- Test push from Firebase console reaches a test device

**Notes:**
- ⚠️ FCM Server Key is sensitive — never commit to repo, never log it
- The two config files (Plist + json) themselves are NOT secret per Firebase docs, but conventionally gitignored

---

## 1.8 🔴 Branch.io Account (Deferred Deep Links)

**What it is:** Deep linking service. Specifically: when someone taps "Welcome back!" SMS link → if app installed, opens directly to `/welcome-back` route → if not installed, opens App Store/Play Store, and after install, opens directly to `/welcome-back` route.

**Why it blocks launch:** The reactivation SMS campaign for your ~2,000 paper-book contacts depends entirely on this — without deferred deep links, post-install routing breaks and the ₹200 welcome credit can't auto-apply.

**Lead time:** 1 day for signup + setup.

**Cost:** Free tier covers up to 10,000 monthly active users — plenty for v1.

**Dependencies:** Apple Developer + Play Console accounts (for app association).

**Steps:**
1. Sign up at https://branch.io
2. Create app → name: "Diaries Club"
3. Configure:
   - iOS Bundle ID + App Store URL (placeholder until app live)
   - Android package name + Play Store URL (placeholder)
   - URI scheme: `diariesclub://`
   - Universal Links domain (Branch provides one, e.g., `diariesclub.app.link`)
4. Get **Branch Key** → add to flavor configs (`F.branchKey` in Flutter)
5. Configure link patterns:
   - Reactivation: `https://diariesclub.app.link/welcome-back?contact_id={id}`
   - Referral: `https://diariesclub.app.link/refer?code={referral_code}`
   - Birthday album share: `https://diariesclub.app.link/album/{reservation_id}`

**What done looks like:**
- Branch Key in your flavor config
- Test link generated and confirmed it deep-links correctly

**Notes:**
- ⚠️ DO NOT use Firebase Dynamic Links — Google deprecated it August 2025. Branch is the Indian-market-friendly successor
- Universal Links require a server-side `apple-app-site-association` file at your domain — Branch hosts this for you on their domain

---

## 1.9 🔴 Domain + Static Hosting

**What it is:** `diariesclub.com` for hosting Privacy/Terms/Refund + small marketing site.

**Lead time:** Same day (domain) + 1 hour (deploy).

**Cost:** ₹800/year domain + ₹0 hosting.

**Steps:**
1. Buy `diariesclub.com` from Namecheap, GoDaddy, or BigRock
2. Set up Cloudflare for DNS (free, faster, more reliable)
3. Deploy via:
   - GitHub Pages (free, easy)
   - OR Vercel/Netlify (free, slightly better DX)
4. Initial pages: `/privacy`, `/terms`, `/refund-policy`, `/` (simple landing)

**What done looks like:** All four URLs return HTML in a browser.

---

## 1.10 🔴 Bank Account for Settlements

**What it is:** Where Razorpay deposits your settlements (payouts from customer transactions).

**Why it blocks launch:** Without this, Razorpay can't pay you.

**Lead time:** 1–7 days depending on bank.

**Cost:** Account opening fees vary (₹0–5,000 for current account).

**Dependencies:** GSTIN (1.6) recommended, PAN required.

**Steps:**
1. Open a **current account** in business name (proprietorship or Pvt Ltd)
2. ICICI, HDFC, Axis, Kotak all support Razorpay settlements well
3. Add account to Razorpay (1.2)
4. Complete cancelled cheque verification

**What done looks like:** Razorpay shows account verified, settlement schedule active.

---

### Tier 1 Summary

| Item | Status | Lead time | Est. cost (INR) |
|---|---|---|---|
| MSG91 + DLT | 🔴 | 3–7d | Per-SMS only |
| Razorpay activation | 🔴 | 2–5d | Per-txn only |
| Privacy/Terms/Refund (legal) | 🔴 | 5–7d | 3,000–10,000 |
| Apple Developer | 🔴 | 1–2d | 8,300/year |
| Play Console | 🔴 | 2–3d | 2,100 one-time |
| GSTIN + business setup | 🔴 | 7–15d | 500–2,000 (CA) |
| Firebase + config | 🔴 | 1h | Free |
| Branch.io | 🔴 | 1d | Free tier |
| Domain + hosting | 🔴 | Same day | 800/year |
| Bank account | 🔴 | 1–7d | 0–5,000 |

**Total Tier 1 cost: ~₹15,000–28,000 + ongoing per-transaction fees**

**Recommended start order:** GSTIN first (blocks others) → in parallel: legal drafts, Apple, Google → once GSTIN done: Razorpay, MSG91 → finally: Branch + Firebase (when build is closer).

---

# Tier 2 — Within 2 Weeks (creative + content)

These items take time because they involve illustrators, content creation, or vendor sourcing. Some can run in parallel with the build.

---

## 2.1 🔴 Hero Character Art

**What:** 4 heroes × 5 stages × full-body illustrations + facial expressions = ~24 illustrations minimum.

**Heroes & traits:**
- Rafi (Brave) — coral red color
- Ellie (Kind) — sky blue
- Gerry (Curious) — amber/orange
- Zena (Creative) — green

**Stages each hero progresses through:**
1. Seedling (newest, smallest, beginner energy)
2. Explorer (curious, gaining confidence)
3. Adventurer (mid-progression, geared up)
4. Champion (advanced, accomplished)
5. Legend (final form, iconic, slightly mythical)

**Why it blocks launch:** The Adventure tab and Hero Recap Card are visually empty without these. Critical for the "magic moment" experience.

**Lead time:** 3–6 weeks depending on illustrator.

**Cost:** ₹40,000–1,50,000 depending on illustrator tier:
- Local Hyderabad illustrator: ₹40K–80K
- Mid-tier Indian studio: ₹80K–1.2L
- Premium freelancer (Behance/Dribbble): ₹1.2L+

**Dependencies:** Mood board (you provide), brand guidelines (your design system).

**Steps:**
1. Brief illustrator with:
   - Brand guidelines (colors, tone)
   - Reference: think Pixar warmth + indie game charm (e.g., A Hat in Time, Untitled Goose Game)
   - **Strict spec:** 4 heroes, 5 stages each, transparent PNG, 2048×2048 master
   - Each hero needs at minimum: idle pose, celebration pose, "thinking" pose
2. Get sample illustrations of one hero (Ellie or Rafi) before committing to full set
3. Iterate on style for that hero until it's right
4. Approve and commission remaining 3 heroes
5. Get all delivered as:
   - Master PNG files (transparent)
   - Layered PSD/AI source files (for future edits)
   - Optimized smaller PNGs for app (512×512 versions)

**What done looks like:**
- 24+ illustrations delivered, named by convention: `rafi_seedling_idle.png`, etc.
- Files in `assets/hero/` in repo
- All four heroes feel like they belong together (consistent style)

**Notes:**
- Where to find: Behance, Dribbble, Toptal, local Hyderabad design schools (NIFT, NID alumni network)
- ⚠️ Get full IP rights in writing — illustrator should sign over commercial usage rights
- Budget for 1–2 rounds of revisions per hero

---

## 2.2 🔴 Rive Animation Files

**What:** Animated versions of hero illustrations for:
- Idle animations (gentle breathing/swaying loop)
- Stage transition cinematics (when child levels up — celebratory ~3-5s sequence)
- Hero card flip animations
- Birthday celebration sequence

**Why it blocks launch:** Static images work but the app feels significantly less alive without them. Your "premium, celebratory" tone is hard to hit without motion.

**Lead time:** 2–4 weeks AFTER hero illustrations are done.

**Cost:** ₹30,000–80,000.

**Dependencies:** Hero illustrations (2.1) — illustrator's source files needed.

**Steps:**
1. Find Rive specialist (Rive.app community, Behance "rive" tag)
2. Brief: 4 heroes × idle + 4 stage-transition cinematics = 8 core animations
3. Deliver source `.riv` files
4. Files placed in `assets/rive/` in repo

**What done looks like:**
- 8+ `.riv` files in repo
- Test in Flutter — animations play smoothly at 60fps on a mid-range Android device

**Notes:**
- Rive is preferred over Lottie for character animation — smaller files, more interactive
- Same illustrator can sometimes do Rive too — ask

---

## 2.3 🔴 Diaries World Map Illustration

**What:** Top-down illustrated map of "Diaries World" — a single image showing 4 territories (one per hero) on the Adventure tab.

**Why it blocks launch:** The Adventure tab's hero element. Without it, the tab is essentially empty.

**Lead time:** 1–2 weeks.

**Cost:** ₹15,000–40,000.

**Dependencies:** Hero illustrations (2.1) — for visual consistency.

**Brief:**
- Top-down/isometric perspective
- 4 distinct territories: Rafi's Mountain (brave/adventure), Ellie's Meadow (kind/community), Gerry's Library (curious/discovery), Zena's Studio (creative/expression)
- Each territory has landmarks the child unlocks as they level up
- Style matches hero illustrations
- 4096×4096 master, layered source

**What done looks like:**
- Single PNG asset in `assets/images/diaries_world_map.png`
- Optional: Rive version with subtle ambient animation

---

## 2.4 🔴 Hero Card Artwork

**What:** ~30 common cards + 6 rare "foil" cards + 4 birthday-exclusive cards = ~40 cards total.

**Why it blocks launch:** Healthy Bite distribution and birthday album rely on this.

**Lead time:** 3–4 weeks.

**Cost:** ₹50,000–1,50,000 for 40 cards.

**Dependencies:** Hero illustrations (2.1).

**Brief:**
- Each card: hero in different scenarios/poses showing personality
- Common cards: simple background, action pose
- Rare cards: gold foil treatment, detailed background, dramatic lighting
- Birthday-exclusive: cake, confetti, "BIRTHDAY EDITION" foil
- Card aspect ratio: 5:7 (standard trading card)
- 1500×2100 master each

**What done looks like:**
- 40 PNGs in `assets/cards/`
- Database `hero_card_definitions` rows populated with image URLs
- Mix evenly distributed across heroes (10 per hero)

---

## 2.5 🔴 Physical Gift Catalog + Supplier

**What:** The Gift Ladder feature gives kids real physical gifts at level milestones. Need actual gifts to give them.

**Why it blocks launch:** Feature is broken without inventory.

**Lead time:** 2 weeks (sourcing).

**Cost:** ₹15,000–50,000 initial inventory (covers ~50–100 redemptions).

**Brief — gift tiers (placeholder, refine with founder):**
- Level 5 (Seedling → Explorer): branded sticker pack (~₹50/each)
- Level 10 (mid-Explorer): branded notebook + pen (~₹150)
- Level 15 (Adventurer): branded T-shirt or cap (~₹400)
- Level 20 (Champion): branded backpack or custom storybook (~₹800)
- Level 25 (Legend): premium item — model figurine, tablet stand, etc. (~₹1500)

**Steps:**
1. Sourcing options:
   - **Local print shops** (Hyderabad has many): stickers, notebooks, T-shirts
   - **Vendors on IndiaMART** for branded merch
   - **Custom storybook printers** for advanced tier
2. Get samples of top tier items first to verify quality
3. Order initial inventory
4. Set up `gift_ladder` table rows with images of actual items

**What done looks like:**
- Initial inventory at venue
- Photos of each gift in app's `gift_ladder` table
- Staff trained on which gift maps to which level

---

## 2.6 🔴 GST Invoice Template

**What:** Tax-compliant invoice format for orders.

**Why it blocks launch:** Every order generates a GST invoice (per spec). It must comply with GST rules.

**Lead time:** 2–3 days with a CA.

**Cost:** ₹2,000–5,000 with CA.

**Required fields per Indian GST law:**
- Business name + GSTIN + address
- Customer name + address (if B2B; B2C below ₹50K can use phone only)
- Invoice number (sequential, never repeated)
- Date + time of issue
- HSN/SAC codes
- Item description + quantity + rate
- Subtotal, CGST + SGST split (or IGST for inter-state), total
- Place of supply
- Signature placeholder

**Steps:**
1. Engage CA to design template
2. Get HTML/PDF template approved
3. Implement in Edge Function `generate-invoice` (Tier 3)

**What done looks like:**
- PDF template that generates correctly with sample data
- CA's written signoff that template is GST-compliant

---

## 2.7 🔴 Reactivation Contact List Cleanup

**What:** Your ~2,000 paper-book contacts need to be cleaned + uploaded.

**Why it matters:** This is a one-shot ₹200-credit SMS blast. Bad data = wasted SMS budget + bad first impressions for matched users.

**Lead time:** 3–5 days (manual cleanup).

**Cost:** Your time (or ~₹3,000 if you delegate to a VA).

**Steps:**
1. Type out paper-book entries into a single CSV with columns: `phone, name, last_visit_date, visit_count, notes`
2. Validate phone numbers (must be 10-digit Indian mobile starting with 6/7/8/9)
3. Remove duplicates (same phone)
4. Remove obvious garbage (incomplete/illegible entries)
5. Estimate quality: how many phones do you trust are correct?
6. Save final CSV — this gets imported via admin Reactivation tool

**What done looks like:**
- Clean CSV with ~2,000 rows (or however many survive cleanup)
- Realistic estimate of "good phone number" hit rate
- Ready to upload via admin panel

**Notes:**
- ⚠️ Even if 30% of numbers are wrong, sending the SMS is fine — those just bounce silently and don't cost anything beyond the per-SMS fee for valid ones
- ⚠️ Ensure the SMS message complies with TRAI: clear opt-out mechanism + sender ID

---

### Tier 2 Summary

| Item | Status | Lead time | Est. cost (INR) |
|---|---|---|---|
| Hero character art (24+ illustrations) | 🔴 | 3–6w | 40,000–1,50,000 |
| Rive animations | 🔴 | 2–4w (after 2.1) | 30,000–80,000 |
| Diaries World Map | 🔴 | 1–2w | 15,000–40,000 |
| Hero Card artwork (40 cards) | 🔴 | 3–4w | 50,000–1,50,000 |
| Gift catalog + initial inventory | 🔴 | 2w | 15,000–50,000 |
| GST invoice template | 🔴 | 2–3d | 2,000–5,000 |
| Reactivation contact cleanup | 🔴 | 3–5d | 0–3,000 |

**Total Tier 2 cost: ~₹1,52,000–4,78,000**

**Recommended approach:** Find a single illustrator/studio who can do 2.1 + 2.2 + 2.3 + 2.4 — saves you 4 separate sourcing efforts and ensures visual consistency.

---

# Tier 3 — Before Launch (final-week items)

These items happen in the last 1–2 weeks before launch. They depend on the build being mostly done.

---

## 3.1 ⚪ App Store Listing Assets

**Lead time:** 2–3 days (for content/screenshots).

**What you need:**
- App name: "Diaries Club"
- Subtitle (30 chars): "Your kid's play adventure"
- App icon (1024×1024)
- Screenshots: 6.7" iPhone (1290×2796) and 6.5" iPhone — minimum 3, max 10
  - Suggested: Home tab, Adventure tab, Hero Recap, Birthday flow, Wallet
- Promotional video (optional, 30s max)
- Description (4000 chars max) — write benefits, not features
- Keywords (100 chars total, comma-separated)
- Support URL: `diariesclub.com/help` (static page)
- Marketing URL: `diariesclub.com`
- Privacy Policy URL (1.3)
- Age rating: 4+ (no objectionable content, but confirm via questionnaire)
- Pricing: Free
- Categories: Lifestyle (primary), Entertainment (secondary)

**Steps:**
1. Build app to point where screenshots can be taken
2. Use real-feeling data (your own family + 2-3 dummy children with hero progression)
3. Take screenshots from iOS simulator at exact dimensions
4. Optionally use Figma to add device frames + headlines (e.g., "Earn XP for every visit")
5. Submit via App Store Connect

**Notes:**
- App Store Connect's screenshot requirements change occasionally — check Apple docs at submission time
- First submission review: 2-7 days. Plan for 1-2 rejections (common reasons: missing privacy details, age rating mismatch, bugs in submitted build)

---

## 3.2 ⚪ Play Store Listing Assets

Similar to App Store, but:
- Feature graphic: 1024×500
- Hi-res icon: 512×512
- Screenshots: 16:9 phone, minimum 2, max 8
- Short description (80 chars)
- Full description (4000 chars)
- Content rating questionnaire — fill carefully
- Data safety form — declare every piece of data collected and shared
- 20 testers needed for closed testing track BEFORE production release (Google policy as of 2024)

**Steps:** As above, plus recruit 20 testers via friends/family/internal team.

---

## 3.3 ⚪ FAQ + Help Content

**What:** A help page on the app + WhatsApp support coverage.

**Steps:**
1. Write FAQ (10–15 questions): "What is Diaries Coins?", "How do I top up?", "Why didn't I get my SMS?", etc.
2. Static page: `diariesclub.com/help` with FAQ
3. Train your support staff (or yourself) on responses
4. Set up WhatsApp Business number for support
5. Configure auto-reply: "Thanks for reaching out! Our team responds within 30 mins (10am–9pm)."

---

## 3.4 ⚪ Social Media + Soft Launch Plan

Per your decision (quiet launch, no marketing push):
- Don't run ads
- Don't post on social media until you've done the reactivation campaign and have ~50 active families using the app
- Set up @diariesclubhq Instagram handle now (just to reserve it)
- After 2 weeks of usage, soft-share: "We've been quietly building this. Here's what 50 families are seeing."

---

## 3.5 ⚪ Internal Staff Training

**What:** Your venue staff need to learn:
- How to scan customer QR code
- How to handle a manual session (customer phone dead, etc.)
- How to use the Kitchen Display System
- End-of-shift cash reconciliation
- How to issue a refund (and when to escalate to admin)
- "Birthday Party Mode" for photo capture

**Steps:**
1. After Staff app is built (Session 10), do hands-on training session
2. Print laminated quick-reference cards for the till
3. Define escalation paths: "Anything > ₹500 refund → call founder"

---

## 3.6 ⚪ Owner/Admin Phone Alerting

**What:** Per your decision: critical-only alerts for payment system down, DB unreachable, ₹1,000+ reconciliation mismatch.

**Setup options:**
- **Sentry's Slack/email/SMS alerts** for backend errors
- **PagerDuty free tier** (5 users) for critical-only paging
- **Custom: Supabase Edge Function** that calls Twilio/MSG91 to your phone for highest-severity events

**Recommendation:** Start with Sentry → Slack/email. Add SMS alerts only after 1 month of operation (so you know what "noise" looks like first).

---

## 3.7 ⚪ Backup + Disaster Recovery Verification

**What:** Test that backups actually work BEFORE you need them.

**Steps:**
1. Verify Supabase daily backups are enabled (Pro plan or higher)
2. Manually download a backup
3. Restore it to a fresh Supabase project (point-in-time recovery)
4. Confirm data is intact
5. Document the restore process in a runbook
6. Schedule monthly backup verification

---

### Tier 3 Summary

| Item | Status | Lead time | Est. cost (INR) |
|---|---|---|---|
| App Store listing assets | ⚪ | 2–3d | Your time |
| Play Store listing assets | ⚪ | 2–3d | Your time |
| FAQ + help content | ⚪ | 1–2d | Your time |
| Soft-launch plan | ⚪ | 1d | 0 |
| Staff training | ⚪ | 1d | Your time |
| Alerting setup | ⚪ | 0.5d | Free–₹1,000/mo |
| Backup verification | ⚪ | 0.5d | 0 |

---

# Critical Path Summary

**To launch as fast as possible, the order is:**

**Week 1 (start TODAY):**
- 1.6 GSTIN application (longest blocker)
- 1.3 Engage lawyer for legal docs
- 1.4 Apple Developer signup
- 1.5 Play Console signup
- 1.9 Buy domain
- 2.1 Brief illustrator + start sample for one hero

**Week 2:**
- 1.1 MSG91 + DLT (once GSTIN done)
- 1.2 Razorpay activation (once GSTIN done)
- 1.10 Bank account
- 1.7 Firebase setup
- 1.8 Branch.io setup
- 2.6 GST invoice template
- 2.7 Start reactivation contact cleanup

**Weeks 3–6 (parallel with build):**
- 2.1 Hero illustrations complete
- 2.2 Rive animations
- 2.3 World Map
- 2.4 Hero Cards
- 2.5 Gift catalog inventory

**Final week (Tier 3):**
- 3.1 + 3.2 App listings + screenshots
- 3.3 FAQ
- 3.5 Staff training
- 3.6 Alerting
- 3.7 Backup verification

---

# Total Estimated Pre-Launch Cost

| Tier | Range (INR) |
|---|---|
| Tier 1 (accounts + legal + setup) | 15,000–28,000 |
| Tier 2 (creative + content) | 1,52,000–4,78,000 |
| Tier 3 (final-week items) | 0–3,000 |
| **Total upfront** | **₹1,67,000–5,09,000** |
| **Ongoing monthly** | Razorpay fees + MSG91 SMS fees + Supabase ~₹2,000/mo + domain ~₹70/mo |

**Reality check:** You can launch on the lower end (~₹1.7L) with a single mid-tier illustrator and minimal initial gift inventory. You can also defer Rive animations to v1.1 if budget is tight — the app works with static illustrations.

---

# What I Need From You Next

To produce the Tier 2 spec files (the 9 feature build session files), I have a few decisions still pending. Most are minor refinements; some are dependent on what you've decided since our planning session:

1. **Help screen WhatsApp number:** What's the actual number? Currently a placeholder (`+919XXXXXXXXX`).
2. **Birthday package final pricing:** Confirm ₹15,000 / ₹25,000 / ₹45,000 — or update.
3. **Reservation deposit amounts:** ₹5,000 / ₹8,000 / ₹15,000 (33%) — confirm or update.
4. **Reactivation SMS final copy** — drafted but needs your review before MSG91 template registration.
5. **Reflection moment cards** — 8 drafted (2 per trait). Want to expand to 10 or 12?

I'll ask these as we go through Tier 2 — no need to answer now. They're flagged as "Open Items for Founder" sections in each session file.

---

# Status Tracking Table (update as you go)

Copy this into your project tracker (Notion/Linear/spreadsheet). Update weekly.

```
| Item                      | Owner    | Status  | Started   | Done      | Notes |
|---------------------------|----------|---------|-----------|-----------|-------|
| 1.1 MSG91 DLT             | [You]    | 🔴      |           |           |       |
| 1.2 Razorpay              | [You]    | 🔴      |           |           |       |
| 1.3 Legal docs            | [Lawyer] | 🔴      |           |           |       |
| 1.4 Apple Developer       | [You]    | 🔴      |           |           |       |
| 1.5 Play Console          | [You]    | 🔴      |           |           |       |
| 1.6 GSTIN                 | [CA]     | 🔴      |           |           |       |
| 1.7 Firebase              | [You]    | 🔴      |           |           |       |
| 1.8 Branch.io             | [You]    | 🔴      |           |           |       |
| 1.9 Domain + hosting      | [You]    | 🔴      |           |           |       |
| 1.10 Bank account         | [You]    | 🔴      |           |           |       |
| 2.1 Hero art              | [Illust.]| 🔴      |           |           |       |
| 2.2 Rive animations       | [Illust.]| 🔴      |           |           |       |
| 2.3 World Map             | [Illust.]| 🔴      |           |           |       |
| 2.4 Hero Cards            | [Illust.]| 🔴      |           |           |       |
| 2.5 Gift catalog          | [You]    | 🔴      |           |           |       |
| 2.6 GST invoice template  | [CA]     | 🔴      |           |           |       |
| 2.7 Reactivation cleanup  | [You/VA] | 🔴      |           |           |       |
| 3.1 App Store listing     | [You]    | ⚪      |           |           |       |
| 3.2 Play Store listing    | [You]    | ⚪      |           |           |       |
| 3.3 FAQ + help            | [You]    | ⚪      |           |           |       |
| 3.4 Soft launch plan      | [You]    | ⚪      |           |           |       |
| 3.5 Staff training        | [You]    | ⚪      |           |           |       |
| 3.6 Alerting              | [You]    | ⚪      |           |           |       |
| 3.7 Backup verification   | [You]    | ⚪      |           |           |       |
```
