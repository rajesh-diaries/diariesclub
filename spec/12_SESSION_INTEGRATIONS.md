# Session 12 — Integrations

> Paste `00_CONTEXT.md` first, then this file. Fresh Claude Code conversation.
> **Prerequisites:** Sessions 1-11 + 5b complete.

---

## Session Header

```
I am building Diaries Club. All app code is spec'd. This session: configure
the four external integrations the app depends on — Razorpay (payments),
MSG91 (SMS), Firebase Cloud Messaging (push), Branch.io (deep links).

Estimated time: 3-4 hours
What to build:
  - Razorpay: webhook configuration, signature verification, reconciliation cron
  - MSG91: SMS provider setup, Supabase Auth phone provider integration
  - Firebase Cloud Messaging: server-side push send, device-token management
  - Branch.io: deep-link configuration, deferred deep-link handling

What NOT to build:
  - Edge Functions themselves (Session 13)
  - Customer/staff/admin app code (already done)

Output expected:
  - Configuration files for each integration
  - Webhook endpoints documented
  - Test cases for each integration

Acceptance:
  - Test Razorpay payment in dev → webhook fires → wallet_topup RPC succeeds
  - Test SMS via Supabase Auth → received within 10s
  - Test FCM push to admin's device → received within 5s
  - Test Branch deferred deep link → install + open routes to /welcome-back
```

---

## 1. Razorpay Integration

### 1.1 Account setup (refer to Pre-Launch Checklist 1.2)

You already have:
- Razorpay merchant account (test + live)
- Test keys: `rzp_test_*`
- Webhook URL configured: `https://<project>.supabase.co/functions/v1/razorpay-webhook`
- Webhook secret saved in Edge Function env: `RAZORPAY_WEBHOOK_SECRET`

### 1.2 Events to subscribe to

In Razorpay dashboard → Settings → Webhooks → Subscribe to:
- ✅ `payment.captured` — primary success event
- ✅ `payment.failed` — for tracking only
- ✅ `refund.processed` — Razorpay-initiated refunds
- ✅ `refund.failed` — alerts admin
- ✅ `order.paid` — backup event (some flows fire this not payment.captured)

### 1.3 Webhook signature verification

Razorpay signs every webhook with HMAC-SHA256 of the raw body using your webhook secret. ALWAYS verify before processing.

```typescript
// In Edge Function razorpay-webhook (full implementation in Session 13)
import { createHmac } from 'node:crypto';

function verifyWebhookSignature(rawBody: string, signature: string, secret: string): boolean {
  const expected = createHmac('sha256', secret).update(rawBody).digest('hex');
  return expected === signature;
}
```

If verification fails → return 401 immediately, log to Sentry, do NOT process.

### 1.4 Webhook event handling

For each `payment.captured` event:

1. Extract `notes.idempotency_key` from the payment payload (Flutter sets this when initiating payment)
2. Extract `notes.family_id`
3. Determine purpose from payment notes (top-up vs birthday deposit — but per locked decision, no in-app deposits, so v1 only handles top-ups)
4. Call `wallet_topup` RPC with idempotency key
5. RPC handles double-fires safely (returns `idempotent: true` on replay)

```typescript
async function handlePaymentCaptured(event: RazorpayEvent) {
  const payment = event.payload.payment.entity;
  const notes = payment.notes ?? {};
  const idempotencyKey = notes.idempotency_key;
  const familyId = notes.family_id;

  if (!idempotencyKey || !familyId) {
    Sentry.captureMessage('payment.captured missing notes', { extra: { payment } });
    return;
  }

  // Determine bonus from notes (set by client during top-up initiation)
  const amountPaise = payment.amount;
  const bonusPaise = parseInt(notes.bonus_paise ?? '0');

  // Call RPC
  const { data, error } = await supabaseAdmin.rpc('wallet_topup', {
    p_family_id: familyId,
    p_amount_paise: amountPaise,
    p_bonus_paise: bonusPaise,
    p_razorpay_payment_id: payment.id,
    p_idempotency_key: idempotencyKey,
  });

  if (error) {
    Sentry.captureException(error, { extra: { payment_id: payment.id } });
    throw error;
  }
}
```

### 1.5 Reconciliation cron

Even with webhooks, network drops happen. Run every 15 minutes:

1. Query Razorpay API for all `captured` payments in the last 30 minutes
2. For each, check if a `wallet_transactions` row with that `razorpay_payment_id` exists
3. If not, fire `wallet_topup` with the appropriate idempotency_key (reuse from notes)
4. Log discrepancies to `reconciliation_log` table

```typescript
// In Edge Function razorpay-reconcile (Session 13)
async function reconcile() {
  const since = new Date(Date.now() - 30 * 60 * 1000);
  const payments = await razorpayApi.getPayments({ from: since, status: 'captured' });

  let mismatches = 0;
  let corrected = 0;

  for (const payment of payments) {
    const exists = await supabaseAdmin
      .from('wallet_transactions')
      .select('id')
      .eq('razorpay_payment_id', payment.id)
      .maybeSingle();

    if (!exists.data) {
      mismatches++;
      const idempotencyKey = payment.notes?.idempotency_key
        ?? `recon-${payment.id}`;  // fallback key

      await supabaseAdmin.rpc('wallet_topup', {
        p_family_id: payment.notes.family_id,
        p_amount_paise: payment.amount,
        p_bonus_paise: parseInt(payment.notes.bonus_paise ?? '0'),
        p_razorpay_payment_id: payment.id,
        p_idempotency_key: idempotencyKey,
      });

      corrected++;

      // Alert admin on mismatch (sometimes intentional, sometimes serious)
      if (payment.amount >= 100000) { // ≥ ₹1,000
        await sendAdminAlert(`Reconciliation: corrected missing topup ${payment.id} (₹${payment.amount/100})`);
      }
    }
  }

  await supabaseAdmin.from('reconciliation_log').insert({
    type: 'razorpay',
    payments_checked: payments.length,
    discrepancies_found: mismatches,
    total_corrected_paise: corrected, // simplified
    status: mismatches === corrected ? 'success' : 'partial',
  });
}
```

### 1.6 Refund integration

For staff/admin-initiated refunds with `destination='razorpay'`:

```typescript
async function processRazorpayRefund(refundId: string) {
  const refund = await supabaseAdmin
    .from('refunds').select().eq('id', refundId).single();

  // Get original payment ID from wallet_transactions
  const originalTxn = await supabaseAdmin
    .from('wallet_transactions')
    .select('razorpay_payment_id')
    .eq('reference_id', refund.data.reference_id)
    .eq('reference_type', refund.data.reference_type)
    .single();

  const razorpayRefund = await razorpayApi.refundPayment(
    originalTxn.data.razorpay_payment_id,
    {
      amount: refund.data.amount_paise,
      notes: { refund_id: refund.data.id },
    }
  );

  await supabaseAdmin
    .from('refunds')
    .update({
      razorpay_refund_id: razorpayRefund.id,
      status: 'processing',  // Razorpay confirms via refund.processed webhook
    })
    .eq('id', refundId);
}
```

### 1.7 Test cards

For dev/staging:

| Scenario | Card | Expiry | CVV |
|---|---|---|---|
| Success | 4111 1111 1111 1111 | Any future | Any 3 digits |
| Failure | 5104 0600 0000 0008 | Any future | Any 3 digits |
| 3DS Auth | 5104 0155 5555 5558 | Any future | Any 3 digits |

UPI test: any UPI ID like `success@razorpay`. Failure: `failure@razorpay`.

---

## 2. MSG91 Integration

### 2.1 Account setup (refer to Pre-Launch Checklist 1.1)

You should already have:
- MSG91 account
- DLT-registered sender ID (e.g., `DIARYC`)
- DLT-approved templates for:
  - OTP login
  - Reactivation welcome
  - Birthday journey D-N reminders
- API auth key

### 2.2 Supabase Auth + MSG91 SMS provider

Supabase doesn't natively support MSG91; use a custom provider via Edge Function.

**Configure in Supabase dashboard → Authentication → Providers → Phone:**
- Enable phone signup
- For SMS provider: choose "Twilio" placeholder, then override via Edge Function hooks

OR (cleaner approach): use Supabase's "phone change" hook plus a custom SMS sender.

**Cleanest implementation:** intercept the OTP send via Auth Hook (when available), or build a custom OTP system entirely using Edge Functions:

```typescript
// Edge Function: send-otp
async function handler(req: Request) {
  const { phone } = await req.json();

  // Generate 6-digit code
  const code = Math.floor(100000 + Math.random() * 900000).toString();
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

  // Store code (hashed) in DB
  await supabaseAdmin.from('otp_codes').insert({
    phone, code_hash: await hash(code), expires_at: expiresAt,
  });

  // Send via MSG91
  await fetch('https://api.msg91.com/api/v5/otp', {
    method: 'POST',
    headers: {
      'authkey': MSG91_AUTH_KEY,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      template_id: MSG91_OTP_TEMPLATE_ID,
      mobile: phone.replace('+', ''),  // MSG91 wants 919876543210 (no plus)
      otp: code,
    }),
  });

  return new Response(JSON.stringify({ success: true }));
}

// Edge Function: verify-otp
async function handler(req: Request) {
  const { phone, code } = await req.json();

  const { data: otpRow } = await supabaseAdmin
    .from('otp_codes')
    .select()
    .eq('phone', phone)
    .gt('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false })
    .limit(1)
    .single();

  if (!otpRow) {
    return new Response(JSON.stringify({ error: 'expired' }), { status: 400 });
  }

  const valid = await verifyHash(code, otpRow.code_hash);
  if (!valid) {
    return new Response(JSON.stringify({ error: 'invalid' }), { status: 400 });
  }

  // Mark used
  await supabaseAdmin.from('otp_codes').update({ used_at: new Date() }).eq('id', otpRow.id);

  // Find or create auth user
  let user;
  const existing = await supabaseAdmin.auth.admin.getUserByPhone(phone);
  if (existing.data) {
    user = existing.data.user;
  } else {
    const { data } = await supabaseAdmin.auth.admin.createUser({
      phone,
      phone_confirm: true,
    });
    user = data.user;
  }

  // Generate session JWT
  const session = await supabaseAdmin.auth.admin.generateLink({
    type: 'magiclink',
    email: '',  // not used
  });
  // Or use a server-side JWT signing approach

  return new Response(JSON.stringify({ session_token: session.data }));
}
```

**Note:** This is a simplified pattern. Full implementation requires careful handling of session token generation. Two viable approaches:
1. Use Supabase's `phone_signup` then trigger SMS via webhook hook (cleanest if Supabase supports it)
2. Build custom OTP entirely (full control but more code)

For v1, use approach 1 if Supabase Phone Auth + custom SMS hook is stable; otherwise approach 2.

### 2.3 SMS template registration

Each template you'll send must be DLT-registered. Templates needed:

| Template ID | Use | Sample (with placeholders) |
|---|---|---|
| `OTP_LOGIN` | OTP for login | `Your Diaries Club code is {#var#}. Valid for 10 minutes.` |
| `REACTIVATION_BLAST` | Welcome-back to paper-book contacts | `Welcome back to Play Diaries! ₹200 added to your account. Open: {#var#}` |
| `BIRTHDAY_D90` | 90 days before birthday | `Hi! Your child's birthday is in 90 days. Plan it with us: {#var#}` |
| `BIRTHDAY_D60` | 60 days | (similar) |
| `BIRTHDAY_D30` | 30 days | `30 days to go! Reserve a slot: {#var#}` |
| `BIRTHDAY_D14` | 14 days | (similar) |
| `BIRTHDAY_D7` | 7 days | (similar) |
| `BIRTHDAY_D1` | Day before | `Tomorrow is your child's birthday! See you at Diaries.` |

Each template is approved per telecom (Jio/Airtel/Vi/BSNL) — turnaround 24-72h.

### 2.4 SMS send wrapper

```typescript
// Edge Function: send-sms
async function sendSms(opts: {
  phone: string;       // E.164 with +
  templateId: string;
  variables: string[];  // ordered list matching {#var#} placeholders
}): Promise<{ success: boolean; msg91_id?: string; error?: string }> {

  const mobile = opts.phone.replace('+', '');

  const response = await fetch('https://control.msg91.com/api/v5/flow/', {
    method: 'POST',
    headers: {
      'authkey': MSG91_AUTH_KEY,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      template_id: opts.templateId,
      sender: MSG91_SENDER_ID,
      short_url: '0',
      recipients: [{
        mobiles: mobile,
        var1: opts.variables[0],
        var2: opts.variables[1],
        // ...
      }],
    }),
  });

  const result = await response.json();
  if (result.type === 'success') {
    return { success: true, msg91_id: result.message };
  }
  return { success: false, error: result.message };
}
```

### 2.5 Cost monitoring

Track SMS spend in admin dashboard. Each SMS to Indian mobile ≈ ₹0.18-0.25 depending on telecom. Reactivation blast of 2,000 ≈ ₹400-500.

---

## 3. Firebase Cloud Messaging

### 3.1 Setup (refer to Pre-Launch Checklist 1.7)

You should have:
- Firebase project
- iOS APNs auth key uploaded
- `GoogleService-Info.plist` in `ios/Runner/`
- `google-services.json` in `android/app/`
- FCM server key in Edge Function env: `FCM_SERVER_KEY`

### 3.2 Token registration

When customer app launches and user is signed in:

```dart
// In bootstrap.dart
await FirebaseMessaging.instance.requestPermission(
  alert: true, badge: true, sound: true,
);

final token = await FirebaseMessaging.instance.getToken();
final platform = Platform.isIOS ? 'ios' : 'android';

await Supabase.instance.client.from('families').update({
  'fcm_token': token,
  'fcm_platform': platform,
  'app_version': (await PackageInfo.fromPlatform()).version,
}).eq('id', Supabase.instance.client.auth.currentUser!.id);

// Listen for token refresh
FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
  await Supabase.instance.client.from('families').update({
    'fcm_token': newToken,
  }).eq('id', Supabase.instance.client.auth.currentUser!.id);
});
```

### 3.3 Push send wrapper (Edge Function)

```typescript
// Edge Function: send-push
async function sendPush(opts: {
  family_id: string;
  type: string;        // matches notifications.type
  title: string;
  body: string;
  deep_link?: string;
  reference_id?: string;
}): Promise<{ success: boolean; error?: string }> {

  const { data: family } = await supabaseAdmin
    .from('families')
    .select('fcm_token, fcm_platform, notification_preferences')
    .eq('id', opts.family_id)
    .single();

  if (!family?.fcm_token) {
    return { success: false, error: 'no_token' };
  }

  // Check per-category preference
  const allowed = checkNotificationPreference(opts.type, family.notification_preferences);
  if (!allowed) {
    return { success: false, error: 'preference_disabled' };
  }

  // Strip PII from notification body for FCM transit (Sentry-strip-style)
  // FCM does NOT log payloads but defense-in-depth

  const payload = {
    to: family.fcm_token,
    notification: {
      title: opts.title,
      body: opts.body,
      sound: 'default',
      badge: 1,
    },
    data: {
      type: opts.type,
      deep_link: opts.deep_link ?? '',
      reference_id: opts.reference_id ?? '',
    },
    priority: 'high',
  };

  const response = await fetch('https://fcm.googleapis.com/fcm/send', {
    method: 'POST',
    headers: {
      'Authorization': `key=${FCM_SERVER_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  const result = await response.json();
  if (result.success > 0) {
    return { success: true };
  }
  if (result.results?.[0]?.error === 'NotRegistered') {
    // Token expired; clear it
    await supabaseAdmin
      .from('families')
      .update({ fcm_token: null })
      .eq('id', opts.family_id);
  }
  return { success: false, error: result.results?.[0]?.error };
}

function checkNotificationPreference(type: string, prefs: any): boolean {
  if (!prefs) return true;
  return switch (type) {
    case 'session_started':
    case 'grace_started':
    case 'session_closed':
      return prefs.session_reminders ?? true;
    case 'stage_transition_revealed':
    case 'stage_transition_imminent':
    case 'level_up':
      return prefs.hero_progression ?? true;
    case 'birthday_d_minus_90':
    case 'birthday_d_minus_60':
    // ...
      return prefs.birthday_reminders ?? true;
    case 'order_confirmed':
    case 'order_ready':
      return prefs.order_status ?? true;
    case 'wallet_topup':
    case 'wallet_low_balance':
      return prefs.wallet_alerts ?? true;
    // marketing-type notifications
    default:
      return true;
  };
}
```

### 3.4 Push delivery best-effort

Per spec: push is best-effort. The `notifications` row is the reliable layer (in-app inbox).

```typescript
// notifications table trigger fires send-push
CREATE OR REPLACE FUNCTION notify_push() RETURNS TRIGGER AS $$
BEGIN
  -- Call Edge Function async (non-blocking)
  PERFORM net.http_post(
    url := current_setting('app.send_push_url'),
    body := jsonb_build_object(
      'family_id', NEW.family_id,
      'type', NEW.type,
      'title', NEW.title,
      'body', NEW.body,
      'deep_link', NEW.deep_link,
      'reference_id', NEW.reference_id
    ),
    headers := jsonb_build_object('Authorization', 'Bearer ' || current_setting('app.service_role_key'))
  );

  -- Update push_status optimistically
  UPDATE notifications SET push_status = 'queued', push_sent_at = now()
    WHERE id = NEW.id;

  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER notify_push_trigger
AFTER INSERT ON notifications
FOR EACH ROW EXECUTE FUNCTION notify_push();
```

`net.http_post` requires the `pg_net` extension enabled in Supabase. The Edge Function updates `push_status` based on FCM response.

---

## 4. Branch.io Integration

### 4.1 Setup (refer to Pre-Launch Checklist 1.8)

You should have:
- Branch.io account
- App configured: iOS bundle ID + Play Store package + URI scheme `diariesclub://`
- Universal Links domain (Branch provides, e.g., `diariesclub.app.link`)
- Branch Key in flavor config

### 4.2 Deep link patterns

```
Reactivation:    https://diariesclub.app.link/welcome-back?contact_id={id}
Referral:        https://diariesclub.app.link/refer?code={referral_code}
Birthday album:  https://diariesclub.app.link/album/{reservation_id}
Hero card share: https://diariesclub.app.link/card/{card_id}
```

### 4.3 Branch SDK initialization

Already in Session 3's `bootstrap.dart`:

```dart
await FlutterBranchSdk.init(enableLogging: !F.isProd);
```

### 4.4 Generate Branch link (when sharing)

```dart
Future<String> _generateBranchLink({
  required String type,         // 'refer', 'album', 'card', 'welcome-back'
  required Map<String, dynamic> data,
  String? title,
  String? description,
  String? imageUrl,
}) async {
  final buo = BranchUniversalObject(
    canonicalIdentifier: '${type}/${data['id'] ?? data.values.first}',
    title: title ?? '',
    contentDescription: description ?? '',
    imageUrl: imageUrl ?? '',
    contentMetadata: BranchContentMetaData()..addCustomMetadata('type', type)..addCustomMetadata('data', jsonEncode(data)),
  );

  final lp = BranchLinkProperties(
    channel: 'app',
    feature: 'sharing',
    stage: 'production',
  );

  for (final entry in data.entries) {
    lp.addControlParam(entry.key, entry.value.toString());
  }
  lp.addControlParam('\$desktop_url', 'https://diariesclub.com');

  final response = await FlutterBranchSdk.getShortUrl(
    buo: buo, linkProperties: lp,
  );

  return response.result;
}
```

### 4.5 Handle deferred deep link on first install

```dart
// In SplashScreen.dart bootstrap()
final session = Supabase.instance.client.auth.currentSession;

if (session == null) {
  // Not signed in — check for deferred deep link
  final branchData = await FlutterBranchSdk.getLatestReferringParams();

  if (branchData['+is_first_session'] == true) {
    // Fresh install via Branch link
    final type = branchData['type'] as String?;

    if (type == 'welcome-back' || branchData['route'] == 'welcome-back') {
      final contactId = branchData['contact_id'];
      // Save contact_id to be auto-applied after OTP verify
      await SharedPreferences.getInstance()
        .then((p) => p.setString('pending_reactivation_contact_id', contactId));

      if (mounted) context.go('/auth/phone?from=reactivation');
      return;
    }

    if (type == 'refer') {
      final code = branchData['code'];
      await SharedPreferences.getInstance()
        .then((p) => p.setString('pending_referral_code', code));

      if (mounted) context.go('/auth/phone?from=referral');
      return;
    }
  }
}
```

### 4.6 Reactivation auto-credit

After OTP verify in a fresh install with reactivation contact_id:

```dart
// In OTP verify success handler
final prefs = await SharedPreferences.getInstance();
final reactivationContactId = prefs.getString('pending_reactivation_contact_id');

if (reactivationContactId != null) {
  await Supabase.instance.client.rpc('reactivation_redeem', params: {
    'p_contact_id': reactivationContactId,
  });

  await prefs.remove('pending_reactivation_contact_id');
}
```

### 4.7 New RPC: `reactivation_redeem`

```sql
CREATE OR REPLACE FUNCTION reactivation_redeem(
  p_contact_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_contact reactivation_contacts%ROWTYPE;
  v_family_id UUID;
  v_wallet wallets%ROWTYPE;
BEGIN
  v_family_id := auth.uid();

  SELECT * INTO v_contact FROM reactivation_contacts
    WHERE id = p_contact_id AND redeemed_at IS NULL FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_or_redeemed');
  END IF;

  -- Verify the phone matches the family's phone (security)
  IF NOT EXISTS (SELECT 1 FROM families WHERE id = v_family_id AND phone = v_contact.phone) THEN
    RAISE EXCEPTION 'phone_mismatch';
  END IF;

  -- Verify not expired
  IF v_contact.credit_expires_at < now() THEN
    RAISE EXCEPTION 'credit_expired';
  END IF;

  -- Credit wallet
  UPDATE wallets SET balance_paise = balance_paise + v_contact.credit_paise, updated_at = now()
    WHERE family_id = v_family_id RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise, payment_method
  ) VALUES (
    v_family_id, 'reactivation_credit', v_contact.credit_paise, v_wallet.balance_paise, 'system'
  );

  -- Mark contact redeemed
  UPDATE reactivation_contacts SET
    redeemed_at = now(),
    redeemed_family_id = v_family_id
  WHERE id = p_contact_id;

  -- Notification
  INSERT INTO notifications(family_id, type, title, body, deep_link)
  VALUES (
    v_family_id, 'reactivation_welcome',
    'Welcome back to Diaries Club! ₹200 added.',
    'Your wallet has been credited. Time to celebrate.',
    '/home'
  );

  RETURN jsonb_build_object(
    'success', true,
    'credit_paise', v_contact.credit_paise
  );
END $$;

GRANT EXECUTE ON FUNCTION reactivation_redeem TO authenticated;
```

### 4.8 Test deferred deep link

1. Generate a test Branch link with `type=welcome-back&contact_id=test-123`
2. Insert a test row in `reactivation_contacts` with that ID
3. Click link on a phone with app NOT installed
4. App Store / Play Store opens; install app
5. Open app first time → splash detects Branch params → routes to `/auth/phone?from=reactivation`
6. Complete OTP → reactivation_redeem fires → ₹200 credited
7. Wallet card on Home shows new balance

---

## 5. Audit Trail for All Integrations

Every integration touchpoint writes to `audit_log` with `actor_type='system'`:

| Event | Audit action |
|---|---|
| Razorpay webhook received | `razorpay.webhook.{event_type}` |
| Razorpay reconciliation correction | `razorpay.reconcile.correction` |
| MSG91 SMS sent | `msg91.send.{template_id}` |
| MSG91 SMS failed | `msg91.send.failed` |
| FCM push sent | `fcm.send.{type}` |
| FCM push failed | `fcm.send.failed` |
| Branch link generated | `branch.link.{type}` |
| Reactivation redeemed | `reactivation.redeem` |

This gives admins full visibility and enables post-hoc debugging.

---

## 6. Rate Limiting & Quotas

| Service | Limit | Backoff strategy |
|---|---|---|
| Razorpay API | 60 req/min | Exponential backoff up to 30s, then alert |
| MSG91 SMS | 1000 msgs/min on default plan | Throttle reactivation blast to 100/sec |
| FCM | 1000 push/sec free tier | None needed at our scale |
| Branch | 10K link generations/month free | None needed at our scale |
| Supabase Edge | 500K invocations/mo Pro | Monitor, upgrade if needed |

Implement throttling in `reactivation-blast` Edge Function:

```typescript
async function blast(contacts: Contact[]) {
  const BATCH_SIZE = 100;
  const BATCH_DELAY_MS = 1000; // 100 SMS per second = 6000/min, well under MSG91 limit

  for (let i = 0; i < contacts.length; i += BATCH_SIZE) {
    const batch = contacts.slice(i, i + BATCH_SIZE);
    await Promise.all(batch.map(c => sendReactivationSms(c)));
    if (i + BATCH_SIZE < contacts.length) {
      await new Promise(r => setTimeout(r, BATCH_DELAY_MS));
    }
  }
}
```

---

## 7. Acceptance Tests

```
TEST 1 — Razorpay test payment end-to-end
  1. In dev, top up ₹500 via app
  2. Complete via test card 4111 1111 1111 1111
  3. Razorpay dashboard shows captured payment
  4. Webhook fires within 30s
  5. Edge Function razorpay-webhook receives event, verifies signature
  6. wallet_topup RPC fires, balance updates
  7. Customer app wallet stream updates

TEST 2 — Razorpay webhook signature verification
  1. Send a request to webhook URL with bad signature
  2. Edge Function returns 401, logs to Sentry
  3. No DB changes

TEST 3 — Razorpay reconciliation
  1. Manually delete a wallet_transactions row that has razorpay_payment_id
  2. Wait for next reconciliation cron (or trigger manually)
  3. Reconcile detects mismatch, calls wallet_topup with idempotency_key
  4. Row recreated, audit trail captures correction

TEST 4 — MSG91 OTP send + receive
  1. New user enters phone +919876543210 (your own number)
  2. SMS arrives within 10s with 6-digit code
  3. Enter code → verifies, signs in

TEST 5 — MSG91 reactivation blast
  1. Admin: upload test CSV of 5 contacts (your own phone among them)
  2. Click "Send to my phone first" → only your phone gets SMS
  3. Verify SMS content, branch link works
  4. Click "SEND ALL" with 5 contacts
  5. All 5 SMS dispatched, sms_status updates to 'dispatched'
  6. Check delivery in MSG91 dashboard

TEST 6 — FCM push delivery
  1. Customer app on physical device, sign in
  2. families.fcm_token saved correctly
  3. Insert a notification row via SQL
  4. Trigger fires, send-push Edge Function called
  5. Push arrives on device within 5s

TEST 7 — FCM token refresh
  1. App force-stopped or reinstalled → new FCM token issued
  2. Customer app onTokenRefresh callback updates families.fcm_token
  3. Subsequent push uses new token

TEST 8 — Push respects notification preferences
  1. User toggles "Marketing & offers" OFF
  2. Send marketing-type notification
  3. send-push Edge Function checks prefs, returns early
  4. notifications row inserted but push_status='skipped'
  5. In-app inbox still shows the notification (silent)

TEST 9 — Branch deep link (already-installed user)
  1. Generate referral link via app
  2. Open link on another device with app installed
  3. App opens, routes to /auth/phone?from=referral
  4. Code captured for post-OTP redemption

TEST 10 — Branch deferred deep link (fresh install)
  1. Reactivation campaign blast sends SMS with Branch link
  2. Click link on phone WITHOUT app
  3. App Store / Play Store opens (verify correct app shown)
  4. Install app
  5. Open app first time
  6. Splash detects branch params, routes to phone entry
  7. Complete OTP → reactivation_redeem fires
  8. ₹200 credit appears in wallet
  9. reactivation_contacts.redeemed_at populated

TEST 11 — Razorpay refund flow
  1. Admin approves a refund with destination='razorpay'
  2. Edge Function calls Razorpay API to issue refund
  3. refunds.razorpay_refund_id populated, status='processing'
  4. Razorpay sends refund.processed webhook within ~5min
  5. Webhook updates status to 'completed'
  6. Customer notification fires

TEST 12 — Rate limiting
  1. Reactivation blast of 1,000 contacts
  2. Throttle at 100/sec confirmed (10s total dispatch time)
  3. No MSG91 errors (under their limit)
```

---

## 8. Files to Create

```
- supabase/functions/razorpay-webhook/index.ts           (Session 13)
- supabase/functions/razorpay-reconcile/index.ts         (Session 13)
- supabase/functions/send-otp/index.ts                   (Session 13)
- supabase/functions/verify-otp/index.ts                 (Session 13)
- supabase/functions/send-sms/index.ts                   (Session 13)
- supabase/functions/send-push/index.ts                  (Session 13)
- supabase/functions/reactivation-blast/index.ts         (Session 13)

- supabase/migrations/0007_otp_codes.sql:
  CREATE TABLE otp_codes (
    id UUID PK,
    phone TEXT,
    code_hash TEXT,
    expires_at TIMESTAMPTZ,
    used_at TIMESTAMPTZ,
    attempts INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
  );
  CREATE INDEX idx_otp_phone ON otp_codes(phone, expires_at) WHERE used_at IS NULL;

- supabase/migrations/0008_notify_push_trigger.sql:
  CREATE EXTENSION IF NOT EXISTS pg_net;
  + the trigger from §3.4

- supabase/migrations/0009_reactivation_redeem.sql:
  + the RPC from §4.7
```

---

## 9. Open Items for Founder

- [ ] Confirm DLT-approved templates list (§2.3) — share template IDs once approved
- [ ] Confirm Razorpay live keys handover process (whose name on the merchant account)
- [ ] Decide whether to use approach 1 (Supabase Phone + custom hook) or approach 2 (custom OTP) — recommend approach 2 for cleaner DLT compliance
- [ ] Confirm Branch app domain (e.g., `diariesclub.app.link`)
- [ ] Approve "$desktop_url" fallback for Branch links (where to send desktop browser users)
- [ ] Decide if SMS retry is needed for failed dispatches (recommended: 1 retry after 5 min, then give up)

---

## What's NOT in this session

- Edge Functions themselves (Session 13)
- pg_net extension verification (Supabase docs)
- Cron schedule configuration (Session 13)
