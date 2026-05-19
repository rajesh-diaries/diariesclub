# Diaries Club — Policy Inventory

> **Purpose of this document.** A single source of truth for everything
> Diaries Club collects, processes, shares, and the rules governing
> sessions / wallet / refunds. Hand this whole file to Claude (or a
> lawyer) and ask for: Privacy Policy, Terms of Service, Refund Policy.
>
> **Last updated:** 2026-05-15
>
> **All operator fields complete as of 2026-05-15.** Ready to hand to
> Claude / a lawyer for drafting Privacy Policy, Terms of Service, and
> Refund Policy.

---

## 1. Operator block (top of every policy doc)

> **Policy version:** 1.0
> **Effective from:** 1 June 2026 *(target — adjust to the actual app-store launch date before publishing)*
> **Last updated:** 2026-05-15
>
> Version history is maintained on request to the grievance officer named below.

**Diaries Club** is operated by **Planovative Diaries LLP**, a Limited
Liability Partnership registered under the Indian Limited Liability
Partnership Act, 2008.

| Field | Value |
|---|---|
| Legal Name | PLANOVATIVE DIARIES LLP |
| Trade Name | PLANOVATIVE DIARIES LLP |
| Constitution | Limited Liability Partnership |
| GSTIN | 36ABGFP4029B1ZJ |
| LLPIN | ACK-4047 |
| LLP Status | Active |
| Designated Partner (primary signatory) | Venkata Rajesh Kumar Gaddam |
| Co-Designated Partner | Namrata Kamalakar Rao |
| Registered Office | 4th Floor, PRR Pawan Plaza, SY No. 187 (P), Botanical Garden Road, Serilingampally, Kondapur, Hyderabad — 500084, Telangana, India |
| Grievance Officer | Venkata Rajesh Kumar Gaddam (Designated Partner) |
| Grievance Officer Email | rajesh@playcafediaries.in |
| Support Email | rajesh@playcafediaries.in |
| Support Phone / WhatsApp | +91 89780 75757 |
| Website (policy host) | https://playcafediaries.in |

### Brand relationship (mention explicitly in the Privacy Policy)

> Diaries Club is the loyalty and booking platform for **Play Diaries**
> play cafes, operated by Planovative Diaries LLP. References to
> "Diaries Club," "we," or "us" in this policy refer to Planovative
> Diaries LLP.

This sentence avoids App Store reviewer confusion when the reviewer
clicks the policy link from "Diaries Club" listing and lands on a
`playcafediaries.in` URL.

### Geographic scope

Diaries Club is intended for residents of India. Sign-up is gated to E.164 `+91` (Indian) phone numbers only; we do not knowingly collect data from users outside India. If you are based outside India and have somehow created an account, please contact the grievance officer (above) so we can delete it.

---

## 2. Personal data collected — by category

### 2.1 From parents / guardians (account holders, must be ≥ 18 per consent gate)

**Required at signup:**
- **Phone number** (E.164 format, +91 only) — auth identity, OTP delivery, customer-support lookup
- **Family name** (display name, user-supplied during onboarding) — personalised greetings + admin search

**Automatically collected as the parent uses the app:**
- **Wallet balance & transaction history** — top-ups, debits, refunds, coupon redemptions, idempotency keys, payment method, Razorpay payment IDs (no card data); admin-visible only — customer sees amount + timestamp in their wallet history
- **FCM device token + platform** (iOS / Android) — push delivery routing; persisted on the family row; cleared on sign-out
- **Notification preferences** — 8 toggleable categories (see §7)
- **Marketing consent** — explicit opt-in, default OFF
- **Technical request data** — IP address, device model, OS version, app version, app crash reports (Sentry). Standard server-log + crash-monitoring telemetry. PII scrubbed in crash reports via the regex set in `bootstrap.dart`. auth.uid attached so we can attribute the crash to a user for support purposes.

### 2.2 From children (created and managed by the parent)

**Required to use the app:**
- **Child first name** — parent-supplied; used for personalised greetings, session display, and progress dashboards
- **Date of birth** — full date (DD-MMM-YYYY). Reason for collecting full date: to send personalised birthday greetings on the child's actual birthday, to power the birthday-booking funnel (countdown reminders + special hero cards on the child's birthday), and to deliver age-appropriate content. Accepted range: 0–14 years old (DOB must fall within the last 14 years; enforced both client-side in the picker and server-side in `child_create` / `child_update`).
- **Favourite hero character** — 1 of 4 (Rafi, Ellie, Gerry, Zena); drives the gamification visuals on the Adventure tab

**Optional — explicitly marked optional in the app, can be skipped without losing core functionality:**
- **Delivery address** *(optional)* — parent may provide a postal address so we can mail physical gifts, hero card decks, or birthday-package related prizes to the child. Field is clearly labelled "Delivery address (optional) — We'll mail special prizes here" in the onboarding UI. Skipping means the child can still play, earn XP, unlock hero cards, etc.; only physical-mail prize fulfilment is affected.

**No child photos collected, ever.** The app has no photo upload surface anywhere — not in onboarding, not in profile, not on the avatar. All child avatars display the first letter of the name on a tinted circle. See §2.5 for the full no-photo stance.

**Derived gameplay state (not user-supplied, automatically computed):**
- **XP per trait, current level, current stage** — derived from session activity
- **Hero card collection, hero recap images** — gameplay artefacts
- **Session history** — venue check-ins, durations, money spent
- **Reflection entries** — parents' qualitative notes about each play session, used to track the child's overall developmental growth across visits to Play Diaries (mood, behaviour highlights, things the parent observed). Optional; if skipped, XP auto-splits across all four heroes after 24h. Stored privately, visible only to the family account holder, and anonymised on account deletion.
- **Streak / visit milestones**
- **Birthday booking interest signal** (`children.birthday_interest_state`) — auto-derived from in-app behaviour (defaults to `interested`; flips to `not_interested` or `ready_to_book` based on whether the parent engages with or dismisses birthday-party cards). Used only to decide whether to surface birthday-party suggestions on the home screen.

### 2.3 Transactional / behavioural

- **Sessions** — venue play records (start, end, status, amount, child, payment method)
- **Orders** — café + FIT menu items + combos ordered at venue
- **Wallet transactions** — types: `topup`, `session_debit`, `session_refund`, `order_debit`, `refund`, `bonus`, `reactivation_credit`, `extension_debit`. Wallet pays for **play sessions, café/FIT food orders, and workshop fees only**. Birthday parties are not paid for through the app — see next bullet.
- **Birthday inquiries** *(enquiry-only — no payment, no booking through the app)* — when a parent expresses interest in a birthday party, we capture the preferred date, package interest, guest-count estimate, and any special requests they want the venue to know about. A staff member then follows up via WhatsApp to confirm details, dates, and pricing **outside the app**. No wallet debit, no deposit, no in-app reservation flow. The special-request free-text field **may include allergy or dietary information** which the parent enters voluntarily so the venue team can prepare; stored only to brief venue staff for that specific enquiry, not used for marketing, not shared outside the venue team. Anonymised on account deletion.
- **Workshop registrations** — workshop id, child id, registration timestamp, payment status
- **Push notification dispatch history** (`notifications` table) — the title and body of each push we sent (which may reference your child's first name, e.g. *"Welcome back to Diaries Club, Aarav!"*), the timestamp, delivery status, and optional failure reason. **Auto-purged after 7 days** via a nightly cron (`notifications_purge_old`) — the in-app inbox shows only the past week of activity.
- **Audit log** — every privileged server-side action (RPC call, row update, money-moving operation) is recorded with actor, timestamp, old/new values. This exists so we can investigate fraud, abuse, and regulatory enquiries, and to demonstrate accountability under DPDP Act 2023 §8. The audit log is **not customer-visible** but you can request a copy of your own audit entries via the grievance officer. Anonymised on account deletion (your auth.uid is replaced with the deleted-user placeholder).
- **Anonymised venue analytics.** We aggregate gameplay activity (visit counts, average session duration, XP progression rates, popular hero choices) across all customers at each Play Diaries venue to inform our own product and operational decisions — e.g., *"kids aged 5–7 average 12 visits per year at our Kondapur location."* These aggregate insights **do not include any personal identifiers** and are never sold, shared, or exposed to third parties. Once your account is deleted, your individual contributions are anonymised, but the aggregate counts they fed into remain (they are no longer your data — they are venue-level statistics).

### 2.4 Device + platform metadata

- **Operating system + app version** — iOS / Android version + Diaries Club app version, auto-collected by Sentry and Firebase Cloud Messaging.
- **Crash reports + breadcrumbs** — sent to **Sentry** (sentry.io, **hosted in the United States**) under their standard Data Processing Agreement, retained for 30 days (Sentry default). Before any crash event leaves the device, our `bootstrap.dart` scrub pipeline strips: phone numbers (E.164 +91 patterns and bare 10-digit Indian mobiles), email patterns (defence-in-depth — we don't collect email anyway), Razorpay payment IDs, auth user IDs, **and the current family's child first names** (registered at runtime by `family_children_provider.dart`). Possessive patterns such as *"Aarav's reflection failed"* are scrubbed via a regex fallback even before a child name registers, so newly created children are covered too.
- **Cross-border data transfer disclosure (DPDP §16):** Sentry crash data is the only cross-border transfer we make. We disclose this transfer to the user in the Privacy Policy.
- **IP addresses** — your IP address is processed **transiently** by our hosting providers (Supabase ap-south-1 Mumbai, Razorpay India, Firebase Cloud Messaging global) for fraud prevention, request routing, and standard server logs. **Diaries Club itself does not store IP addresses in any of its own application tables.** The IP is never associated with a child or with a family in our databases.

### 2.5 What we explicitly do NOT collect

- **Email addresses** (we deliberately do not collect or store email — all communication is via in-app push, SMS for OTP, and phone/WhatsApp for support)
- **Photographs of any kind.** Diaries Club never collects, stores, or processes photographs — not of the child's profile, not of birthday parties, not as staff-curated keepsakes. All child avatars in the app are initial-on-a-tinted-circle. **Play Diaries venue staff also do not photograph children at the venue for marketing or promotional use** (founder decision 2026-05-15: replaced the prior opt-out clause on the physical consent form with a clean "no photography" stance to keep the app + venue stories consistent). Parents and guests are free to take their own photos at the venue on their own devices; nothing about those photos touches our systems. Deliberate DPDP §9 stance — we will not process children's images at all, eliminating the risk of inadvertently storing images of guest children (siblings, friends, party guests) whose parents have not given verifiable consent.
- **Advertising identifiers (IDFA on iOS, GAID on Android).** Diaries Club does not access, read, or transmit any device-level advertising identifier. We do not show ads in the app and we do not participate in any cross-app tracking, attribution, or audience-building network. The App Tracking Transparency (ATT) prompt is therefore not shown on iOS, and our Apple App Privacy declaration is "Data Not Collected" for the Identifiers → Advertising Data subcategory.
- Government IDs (no Aadhaar, no PAN)
- Precise geolocation (no GPS access requested)
- Browsing history outside the app
- Contacts, calendars, camera-roll-wide access
- Voice recordings
- Biometrics

**We do not sell or rent any of your data to third parties for advertising or marketing purposes.** Data is shared only with the processors named in §3 (Supabase, Razorpay, MSG91, Firebase Cloud Messaging, Apple Push Notification service, Sentry) and only to the strict extent necessary to operate the app. We have no affiliate-marketing, ad-network, or data-broker relationships. If this ever changes, we will update this policy and obtain fresh consent from existing users before any new data flow begins.

### 2.6 Legal basis for processing each data category (DPDP §6)

For every piece of data we collect, the law requires us to state *why* — i.e. which lawful ground under DPDP §6 applies. Here is the mapping:

| Data | Legal basis | Plain explanation |
|---|---|---|
| Phone number | **Contractual necessity + statutory** | We can't run a user account without a way to sign you in; OTP delivery via a DLT-registered template is also mandated by Indian telecom regulation. |
| Family name | **Contractual necessity** | Personalised greetings and admin support are core features of the product you signed up for. |
| Child first name, DOB, favourite hero | **Consent (parental, on behalf of the child)** | Captured at onboarding behind the 18+ guardian checkbox and OTP. You can edit or remove these at any time. |
| Delivery address | **Consent** | Strictly optional. Only collected if you want us to mail physical prizes. |
| Wallet balance + transactions | **Contractual necessity + legal obligation** | Required to operate the wallet feature, and Indian Income Tax + GST law requires us to retain financial records for 7 years. |
| FCM device token | **Consent** | We only register this after you grant the OS push permission. |
| Notification preferences + marketing consent | **Consent** | Explicit toggles; marketing defaults OFF. |
| Crash reports (Sentry) | **Legitimate use** | Necessary to operate the app safely. PII is stripped before transmission per §2.4. |
| Audit log | **Legal obligation + legitimate use** | DPDP §8 itself requires us to demonstrate accountability; needed for fraud and chargeback investigation. |
| Birthday enquiry text + special requests | **Consent** | You type it voluntarily; we use it solely to brief venue staff for that specific enquiry. |
| IP address (transient) | **Legitimate use** | Used by our hosting providers only for fraud prevention and request routing; never stored by Diaries Club. |

---

## 3. Third-party processors and data flow

| Processor | What they receive | Purpose | Data residency | Contractual basis |
|---|---|---|---|---|
| **Supabase** (project `stpxtenyatjwcazuxhtu`, region ap-south-1 Mumbai) | All app data — families, children, sessions, wallets, etc. | Backend database + auth + realtime + edge functions + storage | India (Mumbai) | Supabase standard DPA |
| **Razorpay** | Customer phone, family name, payment amount, idempotency key | Payment processing — wallet top-ups only | India | Merchant agreement |
| **MSG91** | Customer phone number | OTP SMS delivery — DLT-approved template `1007579191778139072`, sender `PLNVTD` | India | DLT registration + MSG91 ToS |
| **Firebase Cloud Messaging (Google)** | FCM device token + push payloads (title, body, deep link, notification ID) | Push notification routing to iOS / Android | Google global (US-centric storage) | Google's FCM ToS |
| **Apple Push Notification service** | APNs device token + push payloads | iOS push delivery | Apple global | Apple Developer Program ToS |
| **Sentry** | Error reports, breadcrumbs (PII scrubbed per §2.4) | Crash and error monitoring | sentry.io (US) | Sentry's DPA |
| **Cloudflare / Supabase Edge Functions** | Per-request bodies (OTP, Razorpay webhook, FCM dispatch) | Edge function runtime | ap-south-1 routed | Same as Supabase |

**This is the complete list.** Diaries Club does not use any analytics SDK (no Google Analytics for Firebase, no Mixpanel, no Amplitude, no AppsFlyer, no Adjust, no Hotjar), no advertising SDK, no audience-building or profiling tool, and no third-party deep-link attribution service. The app makes no network calls outside the processors listed above.

**No data is shared with any third party for advertising, profiling, or audience-building.** Sharing is limited to operational necessity — payment processing (Razorpay), OTP delivery (MSG91), push delivery (FCM + APNs), and crash monitoring (Sentry) — with the named processors above. If we ever add a new processor or change the scope of an existing one, we will update this policy and obtain fresh consent from existing users before any new data flow begins.

**Cross-border data summary (DPDP §16).** Data that ever leaves India:

- **Crash reports** → Sentry (sentry.io, United States). PII scrubbed before transmission per §2.4. Retention 30 days.
- **Push notification tokens + payloads** → Firebase Cloud Messaging (Google global infrastructure, US-centric storage) and Apple Push Notification service (Apple global infrastructure).

**All other data — families, children, sessions, wallets, orders, workshops, audit log, OTPs — stays in Supabase ap-south-1 Mumbai.** No data is transferred to any country that the Government of India has restricted under DPDP §16. If the Central Government notifies new transfer restrictions in future, we will re-evaluate Sentry and FCM/APNs and substitute India-resident alternatives if any provider is blacklisted.

---

## 4. Children's data — special handling (DPDP Act 2023 §9)

- **Consent model:** the parent or guardian is the consenting adult on behalf of the child. Children themselves do not hold accounts and cannot directly interact with Diaries Club; everything in the app — sessions, reflections, hero cards — is managed by the parent's account.
- **Enforcement at signup:** explicit checkbox on the phone-entry screen — *"I am 18+ and a parent or guardian. I agree to Privacy Policy and Terms"* — gated before OTP can be sent. The OTP itself, sent to a phone number a parent owns, serves as verifiable parental consent within the meaning of DPDP §9.
- **No targeted advertising to children:** the app has no advertising of any kind. No ad SDKs, no third-party tracking. See §2.5 + §3.
- **No behavioural surveillance.** We track in-app gameplay activity — sessions played, XP earned per trait, levels reached, streaks, hero card collection — solely to power the Adventure tab and the child's progress dashboard. This information is never used for targeted advertising, never shared with third parties for marketing or profiling, and never linked to any cross-app identifier. It is gameplay state, not behavioural surveillance.
- **No marketing pushes to children:** marketing notifications are the only category that defaults OFF in the parent's notification settings; opt-in is explicit. The parent — not the child — receives every push notification.
- **Verifiable consent floor:** phone OTP + 18+ guardian checkbox is the consent floor we use today. We will strengthen this (e.g. to DigiLocker-backed parental e-KYC) if the DPDP Rules tighten the verifiable-consent definition in future.
- **Age range:** 0–14 years per child profile, enforced both client-side in the date-picker and server-side in `child_create` / `child_update`. Older siblings who occasionally accompany younger ones can still be played-as via a family-shared profile; we don't auto-archive a child when they age past 14. Parents may remove any child profile at any time via Profile → Edit Child → Remove (calls `child_deactivate`, soft-delete with anonymisation on full account deletion).
- **Right to erasure:** the `family_anonymise(p_family_id, 'DELETE')` SQL RPC is wired into the in-app Account Deletion flow at Profile → Delete Account (`/profile/delete-account`). Confirmation token is the literal string `DELETE`. Full mechanics are described in §6 below.
- **Grievance officer for children's data:** any concern about how we handle your child's data may be addressed to the Grievance Officer named in §1 (Venkata Rajesh Kumar Gaddam, rajesh@playcafediaries.in). We will respond within the timelines mandated by DPDP §8(8) once the Rules are finalised; in the interim, target response is within 7 working days.

---

## 5. Retention schedule

| Data type | Retention | Notes |
|---|---|---|
| Phone, family name, child first name, DOB, favourite hero, delivery address | Until user requests deletion via Profile → Delete Account | On deletion: phone is overwritten with an unguessable placeholder; names → "Deleted User" / "Deleted Child"; address → cleared. See §6.3. |
| Sessions, food orders, workshop registrations | Permanent **in anonymised form** (linked only to the now-anonymised account UUID, no name or phone) | Required for Indian Income Tax + GST audit (7-year statutory minimum), fraud and chargeback investigation, and venue gameplay analytics. Physically purged on the next compliance sweep after the 7-year window. |
| Wallet transactions (top-ups, debits, refunds) | Permanent **in anonymised form** | Same statutory tax / GST basis as above. Razorpay also retains the matching payment record server-side for 7 years under their PCI-DSS + RBI obligations, outside our control. |
| Birthday enquiries | Until user requests deletion | Enquiry-only — no payment, no booking. On deletion the row is anonymised along with the rest of the family record. |
| Hero recap images + hero card collection | Anonymised on account deletion; image URLs cleared at the same moment | The aggregate XP / level / stage history per trait is retained anonymised to feed venue analytics on "how kids progress at our cafes." |
| OTP codes | 10 minutes (TTL on the `otp_codes` table) | Phone OTP is hashed (SHA-256) at rest; never stored in plaintext. Codes auto-expire even before the row is purged. |
| Push notification dispatch records | **7 days** (nightly auto-purge at 02:15 UTC via `notifications_purge_old` cron) | Deleted **outright** on account deletion. In-app inbox shows only the past week. |
| Sentry crash reports | 30 days (Sentry default retention) | PII scrubbed before transmission per §2.4. Cannot be selectively deleted per-user — Sentry does not expose a customer-level erasure API, but the 30-day retention bounds the exposure window. |
| Audit log | Permanent **in anonymised form** | Records every privileged server-side action (RPC calls, money-moving operations). On deletion the actor reference is anonymised; entries themselves remain so we can investigate fraud / chargeback / regulatory enquiries post-deletion. |
| Razorpay payment records (their side, not ours) | 7 years | Outside our control — Razorpay retains payment records as required by RBI Master Directions on PA-PG and PCI-DSS. We never store card numbers ourselves; Razorpay does the tokenisation. |
| FCM device token | Until sign-out, until account deletion, or until the OS rotates the token | Cleared on sign-out and on `family_anonymise`. If the OS rotates the token, the old one becomes invalid and FCM drops further dispatches to it. |
| Marketing consent flag | Until the user toggles it off, or until account deletion (reset to `false`) | Explicit opt-in only — defaults OFF for every new account. |
| Inactive accounts | Auto-anonymised after 30 months of no activity | After 24 months of no sign-in, no session, no wallet activity, we send a heads-up SMS. After 30 months we run `family_anonymise` automatically — same anonymisation as a manual deletion. You can sign back in any time before the 30-month mark to reset the clock. *(Auto-purge cron not yet implemented — will be added before launch.)* |

---

## 6. User rights (DPDP Act 2023 + Apple / Play store requirements)

### 6.1 Right to access

The Profile tab exposes every piece of data we hold about you and your family — family name, phone, your children, wallet history, past play sessions, past orders, past workshop registrations, past birthday enquiries. Anything we store is something you can already see in the app.

### 6.2 Right to correction

You can edit your family name, each child's name, DOB, favourite hero, and delivery address at any time from the Profile tab. Optional fields (delivery address) can be cleared back to empty.

### 6.3 Right to erasure — account deletion

**Where to find it.** Profile tab → scroll to the bottom → **"Delete account"** button. Direct route: `/profile/delete-account`.

**How it works.**
1. The screen explains what will happen (the same explanation as below).
2. You type the literal word `DELETE` into a confirmation box. This protects against accidental taps and serves as your final consent.
3. Tapping **"Delete my account"** calls the `family_anonymise(p_family_id, 'DELETE')` server function as a single atomic operation.

**What gets deleted immediately.**
- Family name → replaced with `"Deleted User"`
- Each child's name → replaced with `"Deleted Child"`
- Each child's delivery address → cleared
- Your phone number → replaced with a unguessable placeholder (the format is `+910000` followed by the first 10 characters of your account UUID — chosen so the row no longer maps to a real Indian mobile)
- FCM device token + platform → cleared (no further push notifications can reach you)
- Marketing consent → reset to `false`
- All hero recap images → cleared
- **All push notification history** → deleted outright (every notification we ever sent you is gone)
- A `deleted_at` timestamp is set and `is_anonymised = true` is flagged so the row is excluded from every customer-facing query going forward.

**What is retained — and why.**
- **Wallet transactions, session records, food orders, workshop registrations, birthday enquiries, audit log entries** are retained in **anonymised form** (linked only to your now-anonymised account UUID, with no name / phone / personal identifier). We have to keep these for:
  - **Income tax + GST audit (statutory 7-year requirement under Indian tax law).** Wallet top-ups are taxable revenue events; we cannot lawfully erase them.
  - **Razorpay-side payment records** — separately retained by Razorpay for 7 years under their PCI-DSS and RBI merchant obligations, outside our control.
  - **Fraud and chargeback investigation** for the limited window during which a Razorpay dispute is possible (7 days for direct reversals; up to 120 days for card chargebacks).
  - **Hero progression aggregates** — XP and stage history feed the venue's anonymous analytics on "how kids of age X tend to progress at our cafes." Once anonymised, these are no longer your data — they are aggregate venue data.
- After the statutory retention windows expire, financial records are physically purged on our next compliance sweep.

**What we never claim.** We do not retain the *capability* to re-link an anonymised account to a real person. The phone number, name, and FCM token are physically overwritten, not just hidden — there is no "soft-delete that lets us undo it later" trapdoor.

**Timing.** Deletion is **instantaneous** (single SQL transaction). The Profile tab signs you out immediately afterwards and the next time anyone signs in with that same phone number, it is treated as a brand-new account with no history.

**Cross-platform parity.** The exact same deletion flow is available on iOS, Android, and the customer web (if shipped) — Apple App Store and Google Play Store both require an in-app deletion path, and ours is identical on every platform. No "contact us to delete" workaround. No email back-and-forth.

**Can a deleted account be restored?** No. Once `family_anonymise` runs, there is no path to restore the original identifiers — they have been overwritten in the database. If you sign back up with the same phone, you start fresh.

### 6.4 Right to nominate (DPDP §14)

DPDP §14 allows you to nominate another individual to exercise your rights on your behalf in the event of death or incapacity. We do not yet support in-app nomination; this is on the v1.x roadmap. In the interim, the Grievance Officer (§1) will accept written nomination requests on a case-by-case basis.

### 6.5 Right to grievance

Contact the Grievance Officer named in §1 — Venkata Rajesh Kumar Gaddam, rajesh@playcafediaries.in. Target response within 7 working days.

### 6.6 Right to withdraw consent (DPDP §6(4))

You can withdraw consent for any purpose you previously consented to, as easily as you gave it:

- **Marketing notifications** → Profile → Notifications → toggle off "Marketing"
- **Optional fields** (delivery address) → Profile → Edit Child → clear the field
- **Photo permission** (FCM) → revoke push permission in iOS / Android settings
- **All consent at once** → Profile → Delete Account

Withdrawal does not affect the lawfulness of processing that already happened before you withdrew, but it stops further processing for that purpose from the moment you withdraw.

---

## 7. Notification preferences (user-controllable)

8 categories. Defaults shown — only `marketing` defaults OFF (DPDP requires explicit opt-in for marketing comms):

| Preference key | Default | Gates these notification types |
|---|---|---|
| `session_reminders` | ON | session_* / hydration_nudge / healthy_bite_earned / recap_ready / reflection_prompt / reflection_auto_split |
| `hero_progression` | ON | level_up / stage_transition_* / hero_card_received |
| `birthday_reminders` | ON | birthday_d_* (12 types) / birthday_album_ready / birthday_hero_progression_trigger / birthday_wish |
| `order_status` | ON | order_confirmed / order_ready |
| `wallet_alerts` | ON | wallet_topup / wallet_low_balance / refund_processed |
| `streaks_milestones` | ON | visit_milestone / streak_milestone |
| `workshop_reminders` | ON | workshop_reminder / workshop_cancelled |
| `marketing` | **OFF** | announcement_published — explicit opt-in |

---

## 8. Payment terms (drive the Refund Policy)

### 8.1 Mechanics

- Customer tops up wallet via Razorpay (cards / UPI / wallets) → balance held in INR paise
- Wallet pays for: **play sessions, food orders, session extensions, workshop fees**. Birthday parties are arranged offline (WhatsApp / phone) — the app captures enquiries only.
- **Sessions debit wallet at session creation** — balance reflects reality the moment the customer commits
- **Orders use hold-then-charge** — held at order placement, debited when staff KDS marks order completed
- A reconciliation cron runs every 15 minutes to auto-recover from network drops between Razorpay and our wallet

### 8.2 Refund matrix

Refunds are only issued for one of the following valid reasons:

| Scenario | Outcome |
|---|---|
| Customer cancels session **before** staff QR scan (session not started) | **Full refund** to wallet, instant (`session_refund` transaction) |
| Customer cancels session **after** QR scan (during active or grace) | **No refund** (play already started) |
| Food/drink order cancelled while in `preparing` (before ready) | **Full refund** to wallet |
| Food/drink order delivered as ordered, no quality issue | **No refund** (final sale) |
| Food/drink order — quality issue, wrong item, allergen mishap, or other valid reason raised at the venue | **Manual staff refund** via admin panel; up to `staff_refund_cap_paise` auto-approved; above requires senior admin approval |
| Workshop cancelled by Diaries Club (low signups, instructor unavailable, venue issue, etc.) | **Full refund** to wallet, automatic |
| Workshop registration cancelled by customer **24h+** before workshop | **Full refund** to wallet |
| Workshop registration cancelled by customer **<24h** before workshop | **No refund** |
| Wallet top-up — wrong amount entered, accidental top-up, fraud claim | **Refund to original payment method** via Razorpay (within Razorpay's T+7-day window) on customer request to support |
| Hero cards, perks, XP, coins | **Non-refundable** (gameplay artefacts with no real-world value, not exchangeable) |

Birthday parties are not paid for through the app, so there is no birthday-refund matrix here — any deposit handling happens offline between the family and Diaries Club's birthday team.

### 8.3 Refund destination

- **Default:** wallet credit (instant)
- **Razorpay reversal to source card/UPI:** only on customer request to support, within Razorpay's 7-day window
- All refunds logged to `wallet_transactions` and surfaced in customer's wallet history

### 8.4 Wallet rules

- The Diaries Club wallet is **closed-system store credit** — usable **only at Play Diaries / Diaries Club venues** for play sessions, food orders, session extensions, and workshops. It is the digital equivalent of a café gift card.
- **Not transferable to a bank account.** Wallet balance cannot be withdrawn as cash, transferred to another bank account, sent to another user, or otherwise converted to currency. The only way money leaves the wallet is by spending it at Diaries Club, or — for a wrong/fraudulent top-up — by a refund to the original payment method via Razorpay (see §8.2).
- **Not transferable between families.** Each wallet is tied to a single Diaries Club account (one phone, one family).
- **Top-up bonuses** (e.g., ₹300 free on ₹3,000) are **non-withdrawable, non-transferable** and cannot be refunded to source — they convert to ordinary play credit only.
- **No balance expiry** currently *(may add a 12-month dormancy clause in a future version)*.
- **Negative balance is impossible** — the server raises `insufficient_balance` before any debit.

#### 8.4.1 Why we're allowed to do this (regulatory framing for the App Store)

The Diaries Club wallet is a **Closed-System Prepaid Payment Instrument (PPI)** under Reserve Bank of India guidelines on PPIs. Closed-System PPIs are explicitly **outside the scope of RBI's PPI licensing requirements** because:

1. They can only be used for the issuer's own goods and services (Play Diaries venues only).
2. They cannot be redeemed for cash.
3. They cannot be transferred to third parties.

This is the same regulatory treatment as café gift cards, in-app coin balances on most gaming apps, and merchant-specific store credit. App Store and Play Store both routinely approve this model for Indian merchants. Reference: RBI Master Directions on PPIs (DPSS.CO.PD.No.1/02.14.006/2021-22).

If an App Store reviewer asks *"Can users transfer this wallet to a bank account?"*, the answer is:
> **"No. The Diaries Club wallet is closed-system prepaid store credit usable only at Play Diaries venues for play sessions, food, and workshops. It is not transferable to bank accounts, not redeemable for cash, and not transferable to other users. Refunds to the original payment method are issued via Razorpay only on customer support request within Razorpay's 7-day window."**

---

## 9. Service terms (drive the ToS)

- **Eligibility:** India only (E.164 +91 phone regex enforced). Account holders 18+.
- **Children:** physical presence at venue subject to standard café / play-area rules. Parents responsible at all times.
- **Session duration:** 60 or 120 minutes. Plus a configurable grace period (default ~10 min) at `venue_config.session_grace_max_minutes`.
- **Extensions:** paid; count from original expiry (so grace overrun is deducted from extension purchased).
- **Hero progression / XP / hero cards:** gameplay mechanics with no monetary value. Account-bound, non-transferable.
- **Wallet credit:** prepaid store credit. See Refund Policy.
- **Acceptable use:** no automation / scraping / impersonation / fraud / chargeback abuse / threats to staff.
- **Termination:** company may suspend an account for fraud, chargeback abuse, abuse of staff, or repeated breach of acceptable-use policy.
- **Limitation of liability:** typical SaaS — total liability capped at amounts paid in the trailing 12 months. *(Lawyer to draft the exact clause.)*
- **Force majeure:** standard clause covering pandemics, natural disasters, government action, etc.
- **Governing law:** India, Telangana.
- **Dispute resolution:** arbitration in Hyderabad, English language; subject to courts at Hyderabad for non-arbitrable matters.

---

## 10. Cookies / SDKs / trackers

| Surface | Trackers |
|---|---|
| Mobile app (iOS + Android) | Firebase Cloud Messaging (push only — Analytics not enabled), Sentry (crash only) |
| Customer web (PWA, if shipped) | Same as mobile |
| Admin web | Sentry; Razorpay JS SDK loaded only on admin payment pages (not customer-facing) |
| Marketing site (`playcafediaries.in`) | *Declare separately on the website's own policy — typically Google Analytics + cookies* |

---

## 11. Data security claims you can make

- All data in transit: TLS 1.2+
- Database: Supabase managed Postgres with encryption at rest (AES-256)
- Row-level security (RLS) on every customer-touched table
- Service-role keys never exposed to client
- Razorpay tokenisation — card numbers never touch our servers
- OTP codes hashed (SHA-256) before storage; not stored in plaintext
- Razorpay webhooks signed (HMAC-SHA256) and signature-verified before any wallet credit
- Idempotency keys on every money-moving call
- Audit log captures every privileged server-side action
- Mandatory rebuild + RLS-policy re-verification before any schema change touches user data
- **Backups + disaster recovery.** Supabase maintains automatic encrypted backups of our production database with point-in-time recovery for the last 7 days, all retained in the same `ap-south-1 Mumbai` region as the primary. Backups inherit the same Row-Level Security (RLS) policies as production — there is no privileged "backup admin" who can read raw rows. In the event of database corruption or accidental data loss, we can restore to any point in the previous 7 days. We do not maintain off-region or off-provider backups (no out-of-India copy exists).

### 11.1 Breach notification (DPDP §8(6))

We do everything reasonable to prevent unauthorised access to your data (see the list above). If despite all our safeguards we ever discover a breach affecting your personal data, we will:

1. **Notify you** — via an in-app message + SMS to your registered phone number — describing (a) what data was affected, (b) when the breach occurred and when we discovered it, (c) what we have done to contain it, and (d) what steps you should take to protect yourself.
2. **Notify the Data Protection Board of India** within the timelines mandated by the DPDP Act 2023 (currently 72 hours under the draft DPDP Rules, subject to change once the Rules are notified).
3. **Investigate and remediate** — engage independent security review where the breach is material, fix the underlying vulnerability, and publish a post-incident summary in our app's Help section.

We will never attempt to silently absorb a breach. The grievance officer named in §1 is the single point of contact for breach-related queries from affected users.

### 11.2 Authorised staff and admin access

A small team within Planovative Diaries LLP is able to view your data through the **Diaries Club Admin Console** — a separate web application accessible only to designated staff. We want you to know exactly who and what:

**Who:** Designated Partners (Venkata Rajesh Kumar Gaddam and Namrata Kamalakar Rao), and a strictly limited number of trained venue staff and customer-support personnel whose Diaries Club accounts have been explicitly flagged `is_admin = true`. The admin flag is granted and revoked by the Designated Partners only.

**What they can see:**
- Your wallet balance and full transaction history
- Your past play sessions, food orders, workshop registrations, birthday enquiries
- The names, dates of birth, and favourite-hero choices for the children in your family
- Your contact phone number for support call-backs
- Notification dispatch history (for the same 7-day window your own inbox shows)

**What they cannot do:**
- They cannot read deleted accounts (the row is anonymised and excluded from every admin query).
- They cannot bulk-export customer data.
- They cannot create money out of thin air — wallet top-ups go only through Razorpay; refunds above a configurable per-transaction cap (`staff_refund_cap_paise`) require senior-admin approval.

**Why they have this access:**
- Customer support — looking up your wallet history to resolve a missed top-up or refund query
- Fraud and chargeback investigation
- Operational duties — confirming a birthday enquiry, marking an order as ready, issuing a refund for a quality issue
- Site-wide health monitoring — aggregate dashboards (which never expose individual children)

**Every staff action is recorded.** The audit log (§2.3, §11) captures the actor's UUID, the timestamp, the entity touched, and the before/after values of any change. We review the audit log periodically for unusual access patterns; deliberate misuse is grounds for immediate revocation of admin access and possible legal action under the IT Act.

You may, at any time, ask the grievance officer (§1) for a list of admin accesses that touched your specific account. We will return that list within 7 working days.

### 11.3 Significant Data Fiduciary self-assessment (DPDP §10)

DPDP Act 2023 §10 creates an additional category — **Significant Data Fiduciary** — for organisations processing personal data of a volume or sensitivity that warrants heightened obligations (mandatory Data Protection Officer, periodic Data Protection Impact Assessments, independent audits, etc.).

Based on our current customer base, the volume of personal data processed, the sensitivity of that data, and the limited risk profile of our processing activities, **Diaries Club / Planovative Diaries LLP is not currently classified as a Significant Data Fiduciary** under DPDP Act 2023. We re-evaluate this self-assessment annually and will publicly notify users (via in-app message + policy update) if our classification ever changes, at which point the additional obligations under §10 — including the appointment of a separate Data Protection Officer — will be implemented within the timelines mandated by the DPDP Rules.

---

## 12. App Store / Play Store data-collection declarations

### 12.1 Apple App Store Privacy Nutrition Labels

| Category | Type | Linked to user | Used for tracking |
|---|---|---|---|
| Contact Info | Phone number | Yes | No |
| User Content | Reflections (text) | Yes | No |
| Identifiers | User ID (auth.uid), Device ID (FCM token) | Yes | No |
| Usage Data | Product interaction | Yes | No |
| Diagnostics | Crash data, Performance data (Sentry) | Yes | No |
| Purchases | Purchase history (wallet transactions) | Yes | No |

### 12.2 Google Play Data Safety

- Data collected: yes (all of the above)
- Data shared with third parties: yes (processors per §3)
- Data encryption in transit: yes
- Users can request data deletion: yes (in-app via `/profile/delete-account`)
- Independent security review: no (yet — note as a v1.x goal)

### 12.3 Mandatory URLs at submission

- **Privacy Policy URL:** `https://playcafediaries.in/privacy`
- **Terms of Service URL:** `https://playcafediaries.in/terms`
- **Refund Policy URL:** `https://playcafediaries.in/refund-policy`
- **Support URL:** `https://playcafediaries.in/support` (or whichever page exists)

All four URLs must be live, publicly accessible, and clearly reference "Diaries Club" by name before submission. Apple's review bot fetches the Privacy URL during automation.

---

## 13. Pre-launch policy checklist

- [ ] Draft Privacy Policy, Terms of Service, Refund Policy from this inventory (Claude / lawyer)
- [ ] Host all three at `https://playcafediaries.in/{privacy, terms, refund-policy}`
- [ ] Each policy doc opens with §1 Operator Block verbatim
- [ ] Each policy doc explicitly mentions "Diaries Club" by name (App Store review check)
- [ ] Fill in §1 placeholders: grievance officer email, support email, support phone
- [ ] Set `venue_config.privacy_policy_url`, `venue_config.terms_of_service_url` (via `/admin/config` Module 2.8 — no rebuild needed, reads live)
- [ ] Add `refund_policy_url` to `venue_config` and surface it in the wallet history screen *(optional v1.x — most apps link only from website footer)*
- [ ] Add the same three URLs to Razorpay merchant dashboard (KYC re-verification will recheck — must be live before flipping to live Razorpay keys)
- [ ] App Store Connect: paste Privacy Policy URL in the listing
- [ ] Play Console: complete the Data Safety questionnaire using §12.2 + paste the same URL
- [ ] Verify deletion flow works end-to-end on a test account before submission (mandatory for Play Store + recommended for App Store)
- [ ] Set the policy's "Effective from" date to the actual app-store launch date before publishing the policy URLs

---

## 14. Policy changes and re-consent

Privacy and product practices evolve. When we update this policy, we follow this process:

1. **Minor / cosmetic edits** (typo fixes, formatting, clarifications that don't change what data we collect or how we use it): the new version is published with an incremented version number. No fresh consent is required.
2. **Material changes** — anything that adds a new data category, a new third-party processor, a new purpose, or a different retention window: the next time you open the app after the change, we will show a one-time, full-screen consent prompt that summarises what is changing. You must **accept the new policy** before continuing into the app. You may also choose to delete your account at that prompt instead of accepting.
3. **Effective dates and history.** Every published version of this policy carries an explicit *Effective from* date and *Version number*. Older versions remain available on request to the grievance officer.
4. **Notification reach.** Material changes are also announced via an in-app push notification to all active users 7 days before the change takes effect, so you have time to read the new version before the consent gate appears.
5. **Version numbering.** Minor edits bump the patch number (`1.0` → `1.0.1`). A new section or substantive rewrite bumps the minor number (`1.0` → `1.1`). A material change requiring fresh consent bumps the major number (`1.x` → `2.0`).

If we are ever uncertain whether a change is material, we default to treating it as material — the customer should never be surprised by a quiet expansion of what we collect or share.

---

## 15. Government and law-enforcement requests

We respect lawful process while protecting our customers' privacy. Our standard practice when we receive a data request from any government authority, police, court, or regulator is:

1. **Verify legality.** We only respond to requests that arrive in writing, on official letterhead, and that cite the specific Indian statutory provision under which the data is being sought (e.g. Section 91 CrPC, IT Act §69, DPDP §17). Informal phone calls or unsigned WhatsApp messages are politely declined and asked to be re-issued through proper channels.
2. **Narrow the scope.** We push back on overbroad requests. If the order asks for "all data on all users in city X," we will require the requester to specify identified users and the minimum data needed.
3. **Notify the affected user** wherever legally permitted. Where the request comes with a gag order, we follow the order — but we will publish an annual transparency report stating the *number* and *type* of requests received and complied with, even if we cannot identify individual cases.
4. **No bulk handovers.** We do not maintain a "law-enforcement portal" and we do not pre-emptively volunteer data to anyone. Each request is handled individually by the grievance officer.
5. **Refusal record.** Where we believe a request is unlawful or disproportionate, we refuse in writing and challenge it through the appropriate forum.

If you ever want to know whether a request involving your data has been made, ask the grievance officer (§1) — we will tell you within the limits of any active gag order.
