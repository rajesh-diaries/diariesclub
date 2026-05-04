# Integration secrets — setup

This file is the single reference for **where each external-service
credential lives**. Half belong on the client (env files, gitignored
locally, dart-defined at build time). Half belong on the server (Supabase
project secrets, set once, read by Edge Functions).

**No secret in this list ever lives in source control.** The example env
files (`env/*.example.json`) are templates; the real `.json` siblings are
gitignored. Server secrets live exclusively in the Supabase dashboard.

---

## 1. Client-side (env/*.json)

Each flavor reads its own `env/<flavor>.json` at build time via
`--dart-define-from-file`. Copy from the example, fill values, save.

| Key | Where to get it | Used by |
|---|---|---|
| `SUPABASE_URL` | Supabase dashboard → Project settings → API → Project URL | All flavors |
| `SUPABASE_ANON_KEY` | Same panel → `anon public` key (NOT service_role) | All flavors |
| `RAZORPAY_KEY_ID` | Razorpay dashboard → Settings → API Keys → KEY ID (`rzp_test_*` or `rzp_live_*`) | Customer (dev/staging/prod) |
| `RAZORPAY_MODE` | One of `mock` / `test` / `live`. Picks the client behaviour. | Customer |
| `SENTRY_DSN` | Sentry → Settings → Projects → `<your-project>` → Client Keys (DSN) | All flavors (per-project DSN) |
| `OTP_MODE` | `mock` (dev) / `real` (staging+prod). Customer auth path branches. | Customer |
| `BRANCH_KEY` | Empty for v1 (Branch deferred). When wired: Branch dashboard → Account Settings → Live SDK Key. | Customer |
| `ENV` | String tag echoed into Sentry environment. | All |
| `ADMIN_WEB` | `true` only in admin envs. | Admin only |

**Sentry recommendation: three projects.** Customer / Staff / Admin each
get their own DSN so error volume from the customer app doesn't drown
the staff tablet's couple-of-events-per-day. Free tier covers all three.

**Razorpay live keys** stay in `env/prod.json` only. The `assertSafeRazorpayKeys()`
guard in `flavors.dart` halts a debug build that ships `rzp_live_*`.

---

## 2. Server-side (Supabase project secrets)

These are read by Edge Functions (Session 13 deliverables). Set them
once via the Supabase dashboard → Project settings → Edge Functions →
Secrets, or via the CLI:

```bash
supabase secrets set MSG91_AUTH_KEY="..." \
  --project-ref stpxtenyatjwcazuxhtu
```

| Secret | Where to get it | Used by Edge Function |
|---|---|---|
| `MSG91_AUTH_KEY` | MSG91 dashboard → Auth Key | `auth-otp`, `send-sms`, `reactivation-blast` |
| `MSG91_SENDER_ID` | MSG91 dashboard → DLT-approved sender ID (e.g., `DIARYC`) | All MSG91 functions |
| `MSG91_DLT_TEMPLATE_ID` | DLT registry → registered template ID for OTP login | `auth-otp` |
| `MSG91_OTP_TEMPLATE_ID` | MSG91 → OTP template ID (their own ID, not DLT) | `auth-otp` |
| `MSG91_REACTIVATION_TEMPLATE_ID` | MSG91 → DLT-approved reactivation template | `reactivation-blast` |
| `RAZORPAY_KEY_ID` | Razorpay dashboard → API Keys → KEY ID | `razorpay-topup`, `razorpay-webhook`, `razorpay-reconcile` |
| `RAZORPAY_KEY_SECRET` | Razorpay dashboard → API Keys → KEY SECRET (one-time view; save in 1Password) | Server-side signature verify |
| `RAZORPAY_WEBHOOK_SECRET` | Razorpay dashboard → Webhooks → secret you set when registering | `razorpay-webhook` |
| `FCM_SERVER_KEY` | Firebase console → Project settings → Cloud Messaging → Server key (legacy). For HTTP v1 API switch to a service-account JSON instead. | `send-push` |
| `SENTRY_DSN` | Same Sentry project DSN used by Edge Functions. Can match the customer-app DSN; we'll filter by `flavor` tag. | All Edge Functions |
| `SUPABASE_URL` (auto) | Set by Supabase. Don't touch. | All |
| `SUPABASE_SERVICE_ROLE_KEY` (auto) | Set by Supabase. Don't touch. | All |

After setting, deploy the function (Session 13 work) and verify
`supabase functions deploy <name> --project-ref <ref>` reports the env
correctly.

---

## 3. Razorpay webhook URL

Set once in Razorpay dashboard → Webhooks → Add new endpoint.

```
URL:    https://stpxtenyatjwcazuxhtu.supabase.co/functions/v1/razorpay-webhook
Events: payment.captured, payment.failed, refund.processed, refund.failed, order.paid
Active: yes
Secret: <generate a strong random; save as RAZORPAY_WEBHOOK_SECRET in Supabase secrets above>
```

---

## 4. FCM project info

Stored on disk after `flutterfire configure`:

| File | Path | Status |
|---|---|---|
| Android | `android/app/google-services.json` | ✅ in repo |
| iOS | `ios/Runner/GoogleService-Info.plist` | ⚠️ TODO when iOS push lands |
| Dart options | `lib/firebase_options.dart` | ✅ in repo |

These files are not strictly secrets (they're embedded in the released
app binary anyway), but treat them as such — don't share them in
screenshots.

**Android push will work as soon as the customer app builds against
`google-services.json` and runs on a device with Google Play Services.**
iOS needs an APNs auth key uploaded to Firebase + push capability +
provisioning profile — defer until iOS testing begins.

---

## 5. Bootstrap ceremony recap

Done in Sessions 10 and 11; recorded here for traceability:

- **Tablet auth user** — Supabase Studio → Auth → Users → `tablet-kondapur-001@diariesclub.local` (UUID `4ad8a152-755a-4034-b3ba-3b2891deca22`). Linked to `tablet_devices` row.
- **Founder admin auth user** — Supabase Studio → Auth → Users → `planovativediaries@gmail.com` (UUID `d698dd0e-d0b5-4575-839a-f4852edf7d70`). Linked to `admin_users` row with `role='super_admin'`.
- **Founder staff PIN** — `staff` row `8ba2eace…`, PIN currently `0000` with `force_pin_change=true`. Pending: founder rotates PIN on first staff-app login.

---

## 6. What about Branch.io?

Deferred to post-launch. The `BRANCH_KEY` slot is empty across all env
files. `flutter_branch_sdk` no-ops when the key is empty (verified in
`bootstrap.dart`). Reactivation campaign SMS will need a fallback URL
strategy when v1 launches without Branch — likely a `diariesclub.com`
landing page that mirrors the deferred-deep-link payload. Tracked in
`spec/14_PRELAUNCH_CHECKLIST.md`.
