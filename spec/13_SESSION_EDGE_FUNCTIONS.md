# Session 13 — Edge Functions

> Paste `00_CONTEXT.md` first, then this file. Fresh Claude Code conversation.
> **Prerequisites:** Sessions 1-12 + 5b complete.

---

## Session Header

```
I am building Diaries Club. App + integrations are spec'd. This session:
implement the 12 Supabase Edge Functions that power asynchronous workloads
and external integrations.

Estimated time: 5-6 hours
What to build:
  Webhook & verification:
    1. razorpay-webhook
    2. verify-session-qr
    3. generate-session-qr

  Cron-driven:
    4. razorpay-reconcile (every 15 min)
    5. force-close-grace-sessions (every minute)
    6. reflection-auto-split-cron (every hour)
    7. birthday-journey-cron (daily at 9 AM IST)
    8. wall-of-legends-aggregate (daily at midnight IST)
    9. system-health-snapshot (every 5 min)

  Sender:
    10. send-push
    11. send-sms
    12. reactivation-blast

  Other:
    13. generate-hero-recap (image generation, called from session_complete)
    14. generate-invoice-pdf (called when order placed)
    15. admin-impersonate-token

What NOT to build:
  - Customer/staff/admin app (already done)
  - SMS templates (configured in MSG91 dashboard, see Session 12)

Output expected:
  - 15 Deno-based Edge Functions in supabase/functions/
  - All with proper auth (service_role for cron; signature verify for webhooks)
  - Cron schedules configured in supabase/config.toml or via dashboard
  - Sentry error tracking on all functions

Acceptance:
  - Each function deployable individually via `supabase functions deploy <name>`
  - Each function has documented inputs/outputs
  - Cron functions actually fire on schedule (verified after deployment)
  - Error states properly logged
```

---

## 1. Edge Function Patterns

### 1.1 Common boilerplate

Every Edge Function starts with this pattern:

```typescript
// supabase/functions/<name>/index.ts
import { serve } from 'https://deno.land/std/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import * as Sentry from 'https://deno.land/x/sentry/index.mjs';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SENTRY_DSN = Deno.env.get('SENTRY_DSN_EDGE');

if (SENTRY_DSN) {
  Sentry.init({ dsn: SENTRY_DSN, environment: Deno.env.get('ENV') ?? 'unknown' });
}

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

serve(async (req) => {
  try {
    return await handler(req);
  } catch (e) {
    Sentry.captureException(e);
    return new Response(JSON.stringify({ error: 'internal' }), { status: 500 });
  }
});

async function handler(req: Request): Promise<Response> {
  // function-specific logic
}
```

### 1.2 Auth check helper

```typescript
async function verifyAdminCaller(req: Request): Promise<string | null> {
  const auth = req.headers.get('Authorization')?.replace('Bearer ', '');
  if (!auth) return null;

  const { data: { user } } = await supabaseAdmin.auth.getUser(auth);
  if (!user) return null;

  const { data: admin } = await supabaseAdmin
    .from('admin_users')
    .select()
    .eq('auth_user_id', user.id)
    .eq('is_active', true)
    .maybeSingle();

  return admin ? user.id : null;
}
```

---

## 2. Edge Function 1 — razorpay-webhook

```typescript
// supabase/functions/razorpay-webhook/index.ts
import { createHmac } from 'node:crypto';

const RAZORPAY_WEBHOOK_SECRET = Deno.env.get('RAZORPAY_WEBHOOK_SECRET')!;

async function handler(req: Request) {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const rawBody = await req.text();
  const signature = req.headers.get('X-Razorpay-Signature') ?? '';

  // Verify signature
  const expected = createHmac('sha256', RAZORPAY_WEBHOOK_SECRET).update(rawBody).digest('hex');
  if (expected !== signature) {
    Sentry.captureMessage('Razorpay webhook signature invalid');
    return new Response('Invalid signature', { status: 401 });
  }

  const event = JSON.parse(rawBody);

  // Audit log entry
  await supabaseAdmin.from('audit_log').insert({
    actor_type: 'system',
    action: `razorpay.webhook.${event.event}`,
    entity_type: 'razorpay_event',
    entity_id: event.payload?.payment?.entity?.id ?? event.payload?.refund?.entity?.id,
    new_value: event,
  });

  switch (event.event) {
    case 'payment.captured':
      await handlePaymentCaptured(event);
      break;

    case 'payment.failed':
      await handlePaymentFailed(event);
      break;

    case 'refund.processed':
      await handleRefundProcessed(event);
      break;

    case 'refund.failed':
      await handleRefundFailed(event);
      break;

    default:
      // Unhandled event — log but don't error
      console.log(`Unhandled Razorpay event: ${event.event}`);
  }

  return new Response('OK', { status: 200 });
}

async function handlePaymentCaptured(event: any) {
  const payment = event.payload.payment.entity;
  const notes = payment.notes ?? {};
  const idempotencyKey = notes.idempotency_key;
  const familyId = notes.family_id;

  if (!idempotencyKey || !familyId) {
    Sentry.captureMessage('payment.captured missing notes', { extra: { payment } });
    return;
  }

  const amountPaise = payment.amount;
  const bonusPaise = parseInt(notes.bonus_paise ?? '0');

  const { error } = await supabaseAdmin.rpc('wallet_topup', {
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

async function handlePaymentFailed(event: any) {
  const payment = event.payload.payment.entity;
  // Just log; client side already handles failure UX
  Sentry.captureMessage('Razorpay payment failed', {
    level: 'info',
    extra: { payment_id: payment.id, error_code: payment.error_code },
  });
}

async function handleRefundProcessed(event: any) {
  const refund = event.payload.refund.entity;
  const refundId = refund.notes?.refund_id;

  if (!refundId) return;

  await supabaseAdmin
    .from('refunds')
    .update({
      status: 'completed',
      razorpay_refund_id: refund.id,
    })
    .eq('id', refundId);
}

async function handleRefundFailed(event: any) {
  const refund = event.payload.refund.entity;
  const refundId = refund.notes?.refund_id;

  if (!refundId) return;

  await supabaseAdmin
    .from('refunds')
    .update({ status: 'rejected' })
    .eq('id', refundId);

  // Critical alert to admin
  await sendAdminAlert(`Razorpay refund failed: ${refund.id}, reason: ${refund.failure_reason}`);
}

async function sendAdminAlert(message: string) {
  // For v1: Sentry message + email/Slack via separate Edge Function
  Sentry.captureMessage(`Admin alert: ${message}`, { level: 'warning' });
  // Future: integrate with PagerDuty / SMS
}
```

---

## 3. Edge Function 2 — generate-session-qr

```typescript
// supabase/functions/generate-session-qr/index.ts
import { encode as encodeBase64 } from 'https://deno.land/std/encoding/base64.ts';
import { create as createJwt } from 'https://deno.land/x/djwt/mod.ts';

const QR_SIGNING_KEY = Deno.env.get('QR_SIGNING_KEY')!;

async function handler(req: Request) {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const userId = await verifyCustomerCaller(req);
  if (!userId) {
    return new Response('Unauthorised', { status: 401 });
  }

  const { session_id } = await req.json();

  const { data: session } = await supabaseAdmin
    .from('sessions')
    .select()
    .eq('id', session_id)
    .single();

  if (!session || session.family_id !== userId) {
    return new Response('Forbidden', { status: 403 });
  }

  // Generate nonce
  const nonce = crypto.randomUUID();
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000); // 15 min

  await supabaseAdmin.from('qr_nonces').insert({
    nonce,
    expires_at: expiresAt.toISOString(),
  });

  // Sign JWT payload
  const payload = {
    nonce,
    session_id: session.id,
    family_id: session.family_id,
    venue_id: session.venue_id,
    exp: Math.floor(expiresAt.getTime() / 1000),
  };

  const jwt = await createJwt(
    { alg: 'HS256', typ: 'JWT' },
    payload,
    await getSigningKey(),
  );

  return new Response(JSON.stringify({
    encoded: jwt,
    expires_at: expiresAt.toISOString(),
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function getSigningKey() {
  // Return CryptoKey for HMAC-SHA256
  return await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(QR_SIGNING_KEY),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

async function verifyCustomerCaller(req: Request): Promise<string | null> {
  const auth = req.headers.get('Authorization')?.replace('Bearer ', '');
  if (!auth) return null;
  const { data: { user } } = await supabaseAdmin.auth.getUser(auth);
  return user?.id ?? null;
}
```

---

## 4. Edge Function 3 — verify-session-qr

```typescript
// supabase/functions/verify-session-qr/index.ts
import { verify as verifyJwt } from 'https://deno.land/x/djwt/mod.ts';

async function handler(req: Request) {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const tabletUserId = await verifyTabletCaller(req);
  if (!tabletUserId) {
    return new Response('Unauthorised', { status: 401 });
  }

  const { qr_payload, staff_id } = await req.json();

  let payload;
  try {
    payload = await verifyJwt(qr_payload, await getSigningKey());
  } catch {
    return new Response(JSON.stringify({ valid: false, error: 'invalid_qr' }), { status: 200 });
  }

  // Check nonce not used
  const { data: nonceRow, error: nonceErr } = await supabaseAdmin
    .from('qr_nonces')
    .update({ used_at: new Date().toISOString() })
    .eq('nonce', payload.nonce)
    .is('used_at', null)
    .gt('expires_at', new Date().toISOString())
    .select()
    .maybeSingle();

  if (!nonceRow) {
    return new Response(JSON.stringify({ valid: false, error: 'qr_used_or_expired' }), { status: 200 });
  }

  // Verify session is still active
  const { data: session } = await supabaseAdmin
    .from('sessions')
    .select()
    .eq('id', payload.session_id)
    .single();

  if (!session || !['active', 'grace'].includes(session.status)) {
    return new Response(JSON.stringify({ valid: false, error: 'session_inactive' }), { status: 200 });
  }

  // Audit
  await supabaseAdmin.from('audit_log').insert({
    actor_id: staff_id,
    actor_type: 'staff',
    action: 'session.qr_verify',
    entity_type: 'session',
    entity_id: session.id,
    venue_id: session.venue_id,
  });

  // Update session if it was inactive (e.g., set started_at if guest session)
  // Per spec: session_create already starts the timer; here we just confirm check-in
  await supabaseAdmin
    .from('sessions')
    .update({ notes: (session.notes ?? '') + ` | qr_verified_by_staff_${staff_id}` })
    .eq('id', session.id);

  return new Response(JSON.stringify({
    valid: true,
    session_id: session.id,
    family_id: session.family_id,
    child_id: session.child_id,
    duration_minutes: session.duration_minutes,
    expires_at: session.expires_at,
    healthy_bite_earned: session.healthy_bite_earned,
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function verifyTabletCaller(req: Request): Promise<string | null> {
  const auth = req.headers.get('Authorization')?.replace('Bearer ', '');
  if (!auth) return null;

  const { data: { user } } = await supabaseAdmin.auth.getUser(auth);
  if (!user) return null;

  // Must be a tablet device
  const { data: tablet } = await supabaseAdmin
    .from('tablet_devices')
    .select('id')
    .eq('auth_user_id', user.id)
    .eq('is_active', true)
    .maybeSingle();

  return tablet ? user.id : null;
}
```

---

## 5. Edge Function 4 — razorpay-reconcile (cron)

```typescript
// supabase/functions/razorpay-reconcile/index.ts
const RAZORPAY_KEY_ID = Deno.env.get('RAZORPAY_KEY_ID')!;
const RAZORPAY_KEY_SECRET = Deno.env.get('RAZORPAY_KEY_SECRET')!;

async function handler(req: Request) {
  // Cron-only: require service role bearer
  if (req.headers.get('Authorization') !== `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`) {
    return new Response('Unauthorised', { status: 401 });
  }

  const since = new Date(Date.now() - 30 * 60 * 1000);

  // Fetch payments from Razorpay
  const auth = btoa(`${RAZORPAY_KEY_ID}:${RAZORPAY_KEY_SECRET}`);
  const response = await fetch(
    `https://api.razorpay.com/v1/payments?from=${Math.floor(since.getTime()/1000)}&count=100`,
    { headers: { 'Authorization': `Basic ${auth}` } }
  );

  const { items: payments } = await response.json();

  let mismatches = 0;
  let corrected = 0;
  const correctedAmounts: number[] = [];

  for (const payment of payments) {
    if (payment.status !== 'captured') continue;

    const { data: existing } = await supabaseAdmin
      .from('wallet_transactions')
      .select('id')
      .eq('razorpay_payment_id', payment.id)
      .maybeSingle();

    if (!existing) {
      mismatches++;
      const idempotencyKey = payment.notes?.idempotency_key ?? `recon-${payment.id}`;
      const familyId = payment.notes?.family_id;

      if (!familyId) {
        Sentry.captureMessage(`Reconcile: payment ${payment.id} missing family_id in notes`);
        continue;
      }

      const { error } = await supabaseAdmin.rpc('wallet_topup', {
        p_family_id: familyId,
        p_amount_paise: payment.amount,
        p_bonus_paise: parseInt(payment.notes.bonus_paise ?? '0'),
        p_razorpay_payment_id: payment.id,
        p_idempotency_key: idempotencyKey,
      });

      if (!error) {
        corrected++;
        correctedAmounts.push(payment.amount);

        // Critical alert if large amount
        if (payment.amount >= 100000) { // ≥ ₹1,000
          Sentry.captureMessage(
            `Reconciliation corrected missing topup ${payment.id} (₹${payment.amount/100})`,
            { level: 'warning' }
          );
        }
      }
    }
  }

  await supabaseAdmin.from('reconciliation_log').insert({
    type: 'razorpay',
    payments_checked: payments.length,
    discrepancies_found: mismatches,
    total_corrected_paise: correctedAmounts.reduce((a, b) => a + b, 0),
    status: mismatches === corrected ? 'success' : 'partial',
    details: { corrected_payment_ids: correctedAmounts.length },
  });

  return new Response(JSON.stringify({
    payments_checked: payments.length,
    mismatches,
    corrected,
  }));
}
```

**Cron schedule:** every 15 minutes. Configure in `supabase/config.toml`:

```toml
[functions.razorpay-reconcile]
schedule = "*/15 * * * *"
```

---

## 6. Edge Function 5 — force-close-grace-sessions (cron)

```typescript
// supabase/functions/force-close-grace-sessions/index.ts
async function handler(req: Request) {
  if (req.headers.get('Authorization') !== `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`) {
    return new Response('Unauthorised', { status: 401 });
  }

  const { data, error } = await supabaseAdmin.rpc('force_close_grace_sessions');

  if (error) {
    Sentry.captureException(error);
    return new Response(JSON.stringify({ error }), { status: 500 });
  }

  return new Response(JSON.stringify(data));
}
```

The RPC `force_close_grace_sessions` (referenced in Session 2 patterns) does:

```sql
CREATE OR REPLACE FUNCTION force_close_grace_sessions() RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_closed INTEGER := 0;
  v_session sessions%ROWTYPE;
BEGIN
  FOR v_session IN
    SELECT * FROM sessions
    WHERE status IN ('active', 'grace')
      AND grace_force_close_at < now()
    LIMIT 100
  LOOP
    UPDATE sessions SET
      status = 'auto_closed',
      completed_at = now(),
      notes = COALESCE(notes, '') || ' | auto-closed by cron'
    WHERE id = v_session.id;

    -- Notify family
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      v_session.family_id, 'session_closed',
      'Session ended',
      'Your session has been closed. Hope you had fun!',
      '/home', v_session.id
    );

    -- TODO: trigger generate-hero-recap Edge Function for this session

    v_closed := v_closed + 1;
  END LOOP;

  RETURN jsonb_build_object('closed_count', v_closed);
END $$;
```

**Cron schedule:** every minute (`* * * * *`).

---

## 7. Edge Function 6 — reflection-auto-split-cron

```typescript
// supabase/functions/reflection-auto-split-cron/index.ts
async function handler(req: Request) {
  if (req.headers.get('Authorization') !== `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`) {
    return new Response('Unauthorised', { status: 401 });
  }

  const { data, error } = await supabaseAdmin.rpc('reflection_auto_split');

  if (error) {
    Sentry.captureException(error);
    return new Response(JSON.stringify({ error }), { status: 500 });
  }

  return new Response(JSON.stringify(data));
}
```

The RPC was already implemented in Session 6. **Cron:** every hour.

---

## 8. Edge Function 7 — birthday-journey-cron

Daily at 9 AM IST. Sends D-N notifications to families with upcoming birthdays.

```typescript
// supabase/functions/birthday-journey-cron/index.ts
async function handler(req: Request) {
  if (req.headers.get('Authorization') !== `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`) {
    return new Response('Unauthorised', { status: 401 });
  }

  const stats = { sent: 0, errors: 0 };

  // Process each touchpoint window
  const touchpoints = [
    { days: 90, type: 'birthday_d_minus_90', sent_field: 'd_minus_90_sent', title: '90 days to go!' },
    { days: 60, type: 'birthday_d_minus_60', sent_field: 'd_minus_60_sent', title: '60 days to go!' },
    { days: 30, type: 'birthday_d_minus_30', sent_field: 'd_minus_30_sent', title: '30 days to go!' },
    { days: 14, type: 'birthday_d_minus_14', sent_field: 'd_minus_14_sent', title: '2 weeks to go!' },
    { days: 7,  type: 'birthday_d_minus_7',  sent_field: 'd_minus_7_sent',  title: 'One week!' },
    { days: 3,  type: 'birthday_d_minus_3',  sent_field: 'd_minus_3_sent',  title: '3 days!' },
    { days: 1,  type: 'birthday_d_minus_1',  sent_field: 'd_minus_1_sent',  title: 'Tomorrow!' },
    { days: 0,  type: 'birthday_d_zero',     sent_field: 'd_zero_sent',     title: 'Happy birthday! 🎉' },
  ];

  for (const tp of touchpoints) {
    const targets = await findFamiliesAtTouchpoint(tp.days, tp.sent_field);

    for (const target of targets) {
      try {
        // MARK BEFORE SEND (prevent double-fire if function retries)
        await supabaseAdmin
          .from('birthday_journey_state')
          .upsert({
            child_id: target.child_id,
            [tp.sent_field]: true,
            arc_type: target.arc_type,
            updated_at: new Date().toISOString(),
          });

        // Insert notification
        await supabaseAdmin.from('notifications').insert({
          family_id: target.family_id,
          type: tp.type,
          title: tp.title,
          body: birthdayBody(tp.days, target),
          deep_link: target.has_reservation
            ? `/birthday/status/${target.reservation_id}`
            : '/birthday',
          reference_id: target.child_id,
        });

        stats.sent++;
      } catch (e) {
        Sentry.captureException(e);
        stats.errors++;
      }
    }
  }

  return new Response(JSON.stringify(stats));
}

async function findFamiliesAtTouchpoint(days: number, sentField: string) {
  // Find children whose next birthday is exactly `days` away (in IST)
  // and whose journey state for this touchpoint is not yet sent
  const sql = `
    SELECT
      c.id as child_id,
      c.family_id,
      c.name,
      bjs.arc_type,
      EXISTS(
        SELECT 1 FROM birthday_reservations
        WHERE child_id = c.id AND status IN ('interested', 'admin_contacted', 'confirmed')
      ) as has_reservation,
      (SELECT id FROM birthday_reservations
       WHERE child_id = c.id AND status IN ('interested', 'admin_contacted', 'confirmed')
       ORDER BY created_at DESC LIMIT 1) as reservation_id
    FROM children c
    LEFT JOIN birthday_journey_state bjs ON bjs.child_id = c.id
    WHERE
      DATE(MAKE_DATE(EXTRACT(YEAR FROM CURRENT_DATE)::int, EXTRACT(MONTH FROM c.date_of_birth)::int, EXTRACT(DAY FROM c.date_of_birth)::int)) - CURRENT_DATE = ${days}
      AND COALESCE(bjs.${sentField}, false) = false
      AND COALESCE(bjs.comms_paused, false) = false
  `;

  const { data } = await supabaseAdmin.rpc('exec_sql', { query: sql });
  // ^ Or use a typed RPC. For brevity here, illustrative.
  return data ?? [];
}

function birthdayBody(days: number, target: any): string {
  if (target.has_reservation) {
    return switch (days) {
      case 7:  return `Your party is one week away — exciting!`;
      case 3:  return `3 days to go. Anything we should know?`;
      case 1:  return `Tomorrow's the big day! See you at Diaries.`;
      case 0:  return `It's ${target.name}'s birthday! 🎉`;
      default: return `Your party plans are coming together. Track status in the app.`;
    };
  }
  // No reservation yet — funnel push
  return switch (days) {
    case 90: return `${target.name}'s birthday is in 90 days. Plan it with us?`;
    case 60: return `60 days to ${target.name}'s birthday. Browse packages.`;
    case 30: return `One month until ${target.name}'s big day. Reserve a slot?`;
    case 14: return `${target.name}'s birthday is in 2 weeks!`;
    case 7:  return `7 days. Want a memorable celebration?`;
    case 3:  return `Last call for ${target.name}'s birthday — 3 days away.`;
    default: return `${target.name}'s birthday approaches. Let's plan!`;
  };
}
```

**Cron:** daily at 9 AM IST = 3:30 AM UTC. `30 3 * * *`.

---

## 9. Edge Function 8 — wall-of-legends-aggregate

Daily at midnight IST. Aggregates yesterday's notable events.

```typescript
// supabase/functions/wall-of-legends-aggregate/index.ts
async function handler(req: Request) {
  if (req.headers.get('Authorization') !== `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`) {
    return new Response('Unauthorised', { status: 401 });
  }

  const istNow = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Kolkata' }));
  const yesterday = new Date(istNow);
  yesterday.setDate(yesterday.getDate() - 1);
  const yesterdayDate = yesterday.toISOString().substring(0, 10);

  // Get all venues
  const { data: venues } = await supabaseAdmin.from('venues').select().eq('is_active', true);

  for (const venue of venues ?? []) {
    const highlights = await collectHighlights(venue.id, yesterdayDate);
    const stats = await collectStats(venue.id, yesterdayDate);

    await supabaseAdmin.from('wall_of_legends_daily').upsert({
      venue_id: venue.id,
      ist_date: yesterdayDate,
      ...stats,
      highlights,
      computed_at: new Date().toISOString(),
    });
  }

  return new Response(JSON.stringify({ success: true }));
}

async function collectHighlights(venueId: string, date: string) {
  const highlights: any[] = [];

  // 1. Stage transitions yesterday
  const { data: transitions } = await supabaseAdmin
    .from('xp_events')
    .select('child_id, metadata, created_at, child:children(name)')
    .eq('venue_id', venueId)
    .gte('created_at', `${date}T00:00:00+05:30`)
    .lt('created_at', `${date}T23:59:59+05:30`)
    .not('metadata->stage_transitions', 'is', null);

  for (const e of transitions ?? []) {
    const t = (e.metadata as any).stage_transitions[0];
    if (!t) continue;
    highlights.push({
      type: 'stage_transition',
      text: `${anonymise(e.child.name)}'s ${heroName(t.trait)} reached ${stageName(t.to)}`,
      timestamp: e.created_at,
    });
  }

  // 2. Birthdays celebrated
  const { data: bdays } = await supabaseAdmin
    .from('birthday_reservations')
    .select('child:children(name), package:birthday_packages(name)')
    .eq('venue_id', venueId)
    .eq('status', 'completed')
    .gte('updated_at', `${date}T00:00:00+05:30`)
    .lt('updated_at', `${date}T23:59:59+05:30`);

  for (const b of bdays ?? []) {
    highlights.push({
      type: 'birthday',
      text: `${anonymise(b.child.name)} celebrated their birthday with ${b.package.name}`,
    });
  }

  // 3. Streak milestones
  // ... similar pattern

  return highlights;
}

function anonymise(name: string): string {
  return name.charAt(0).toUpperCase() + '.';
}

function heroName(trait: string): string {
  return ({ rafi: 'Rafi', ellie: 'Ellie', gerry: 'Gerry', zena: 'Zena' })[trait] ?? '';
}

function stageName(stage: string): string {
  return ({
    seedling: 'Seedling', explorer: 'Explorer',
    adventurer: 'Adventurer', champion: 'Champion', legend: 'Legend',
  })[stage] ?? stage;
}
```

**Cron:** daily at 12:30 AM IST = 7 PM UTC. `0 19 * * *`.

---

## 10. Edge Function 9 — system-health-snapshot

```typescript
// supabase/functions/system-health-snapshot/index.ts
async function handler(req: Request) {
  if (req.headers.get('Authorization') !== `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`) {
    return new Response('Unauthorised', { status: 401 });
  }

  const fiveMinAgo = new Date(Date.now() - 5 * 60 * 1000);

  // Active sessions count
  const { count: activeSessions } = await supabaseAdmin
    .from('sessions')
    .select('id', { count: 'exact', head: true })
    .in('status', ['active', 'grace']);

  // Push delivery rate (last 5 min)
  const { count: pushSent } = await supabaseAdmin
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .gte('created_at', fiveMinAgo.toISOString())
    .not('push_sent_at', 'is', null);

  const { count: pushFailed } = await supabaseAdmin
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .gte('created_at', fiveMinAgo.toISOString())
    .eq('push_status', 'failed');

  const pushRate = pushSent ? ((pushSent - (pushFailed ?? 0)) / pushSent * 100) : 100;

  // Reconciliation health
  const { data: lastRecon } = await supabaseAdmin
    .from('reconciliation_log')
    .select()
    .order('ran_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  const reconAge = lastRecon ? (Date.now() - new Date(lastRecon.ran_at).getTime()) / 60000 : 999;
  const reconHealth = reconAge < 20 ? 'green' : reconAge < 60 ? 'yellow' : 'red';

  await supabaseAdmin.from('system_health_snapshots').insert({
    snapshot_at: new Date().toISOString(),
    active_sessions: activeSessions ?? 0,
    push_delivery_rate: pushRate,
    reconciliation_health: reconHealth,
  });

  // Critical phone alert if anything red
  if (reconHealth === 'red') {
    Sentry.captureMessage('System health: reconciliation stale', { level: 'error' });
  }

  return new Response(JSON.stringify({ success: true }));
}
```

**Cron:** every 5 min. `*/5 * * * *`.

---

## 11. Edge Function 10 — send-push

Already designed in Session 12. Full implementation:

```typescript
// supabase/functions/send-push/index.ts
const FCM_SERVER_KEY = Deno.env.get('FCM_SERVER_KEY')!;

async function handler(req: Request) {
  // Internal call from DB trigger (service role auth)
  if (req.headers.get('Authorization') !== `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`) {
    return new Response('Unauthorised', { status: 401 });
  }

  const { family_id, type, title, body, deep_link, reference_id } = await req.json();

  const { data: family } = await supabaseAdmin
    .from('families')
    .select('fcm_token, fcm_platform, notification_preferences, is_anonymised')
    .eq('id', family_id)
    .single();

  if (!family || family.is_anonymised) {
    return new Response(JSON.stringify({ skipped: 'family_inactive' }));
  }

  if (!family.fcm_token) {
    await markPushFailed(family_id, type, reference_id, 'no_token');
    return new Response(JSON.stringify({ skipped: 'no_token' }));
  }

  if (!checkPreference(type, family.notification_preferences)) {
    await markPushSkipped(family_id, type, reference_id);
    return new Response(JSON.stringify({ skipped: 'preference_disabled' }));
  }

  const payload = {
    to: family.fcm_token,
    notification: { title, body, sound: 'default' },
    data: {
      type,
      deep_link: deep_link ?? '',
      reference_id: reference_id ?? '',
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
    await markPushDispatched(family_id, type, reference_id);
    return new Response(JSON.stringify({ success: true }));
  } else {
    const errCode = result.results?.[0]?.error;
    if (errCode === 'NotRegistered' || errCode === 'InvalidRegistration') {
      await supabaseAdmin.from('families').update({ fcm_token: null }).eq('id', family_id);
    }
    await markPushFailed(family_id, type, reference_id, errCode);
    return new Response(JSON.stringify({ error: errCode }), { status: 200 }); // 200 — don't retry
  }
}

function checkPreference(type: string, prefs: any): boolean {
  if (!prefs) return true;
  // ... (logic from Session 12)
  return true; // simplified for brevity
}

async function markPushDispatched(family_id: string, type: string, ref: string) {
  await supabaseAdmin
    .from('notifications')
    .update({ push_status: 'dispatched', push_sent_at: new Date().toISOString() })
    .eq('family_id', family_id).eq('type', type).eq('reference_id', ref);
}

async function markPushFailed(family_id: string, type: string, ref: string, error: string) {
  await supabaseAdmin
    .from('notifications')
    .update({ push_status: 'failed' })
    .eq('family_id', family_id).eq('type', type).eq('reference_id', ref);
  Sentry.captureMessage(`FCM push failed: ${error}`, { level: 'info' });
}

async function markPushSkipped(family_id: string, type: string, ref: string) {
  await supabaseAdmin
    .from('notifications')
    .update({ push_status: 'skipped' })
    .eq('family_id', family_id).eq('type', type).eq('reference_id', ref);
}
```

---

## 12. Edge Function 11 — send-sms

```typescript
// supabase/functions/send-sms/index.ts
const MSG91_AUTH_KEY = Deno.env.get('MSG91_AUTH_KEY')!;
const MSG91_SENDER_ID = Deno.env.get('MSG91_SENDER_ID')!;

async function handler(req: Request) {
  if (req.headers.get('Authorization') !== `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`) {
    return new Response('Unauthorised', { status: 401 });
  }

  const { phone, template_id, variables } = await req.json();

  const mobile = phone.replace('+', '');

  const recipientVars: any = { mobiles: mobile };
  variables.forEach((v: string, i: number) => {
    recipientVars[`var${i + 1}`] = v;
  });

  const response = await fetch('https://control.msg91.com/api/v5/flow/', {
    method: 'POST',
    headers: {
      'authkey': MSG91_AUTH_KEY,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      template_id,
      sender: MSG91_SENDER_ID,
      short_url: '0',
      recipients: [recipientVars],
    }),
  });

  const result = await response.json();

  if (result.type === 'success') {
    return new Response(JSON.stringify({ success: true, msg91_id: result.message }));
  }
  return new Response(JSON.stringify({ success: false, error: result.message }), { status: 200 });
}
```

---

## 13. Edge Function 12 — reactivation-blast

```typescript
// supabase/functions/reactivation-blast/index.ts
const BRANCH_KEY = Deno.env.get('BRANCH_KEY')!;

async function handler(req: Request) {
  const adminId = await verifyAdminCaller(req);
  if (!adminId) return new Response('Unauthorised', { status: 401 });

  const { venue_id } = await req.json();

  // Fetch all pending contacts for this venue
  const { data: contacts } = await supabaseAdmin
    .from('reactivation_contacts')
    .select()
    .eq('sms_status', 'pending')
    .eq('is_paused', false)
    .limit(2500);

  if (!contacts || contacts.length === 0) {
    return new Response(JSON.stringify({ sent: 0 }));
  }

  // Audit
  await supabaseAdmin.from('audit_log').insert({
    actor_id: adminId,
    actor_type: 'admin',
    action: 'reactivation.blast',
    entity_type: 'reactivation_contacts',
    new_value: { count: contacts.length },
  });

  let sent = 0, failed = 0;
  const BATCH_SIZE = 100;
  const BATCH_DELAY = 1000;

  for (let i = 0; i < contacts.length; i += BATCH_SIZE) {
    const batch = contacts.slice(i, i + BATCH_SIZE);

    await Promise.all(batch.map(async (contact) => {
      try {
        // Generate Branch link with contact_id
        const branchLink = await generateBranchLink({
          type: 'welcome-back',
          contact_id: contact.id,
        });

        // Send SMS via MSG91
        const smsResult = await sendSms({
          phone: contact.phone,
          template_id: 'REACTIVATION_BLAST',
          variables: [branchLink],
        });

        if (smsResult.success) {
          await supabaseAdmin
            .from('reactivation_contacts')
            .update({
              sms_status: 'dispatched',
              sms_msg91_id: smsResult.msg91_id,
              sms_dispatched_at: new Date().toISOString(),
            })
            .eq('id', contact.id);
          sent++;
        } else {
          await supabaseAdmin
            .from('reactivation_contacts')
            .update({
              sms_status: 'failed',
              sms_failure_reason: smsResult.error,
            })
            .eq('id', contact.id);
          failed++;
        }
      } catch (e) {
        Sentry.captureException(e);
        failed++;
      }
    }));

    if (i + BATCH_SIZE < contacts.length) {
      await new Promise(r => setTimeout(r, BATCH_DELAY));
    }
  }

  return new Response(JSON.stringify({ sent, failed }));
}

async function generateBranchLink(data: { type: string; contact_id: string }) {
  const response = await fetch('https://api2.branch.io/v1/url', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      branch_key: BRANCH_KEY,
      data,
      campaign: 'reactivation_blast',
      channel: 'sms',
    }),
  });
  const { url } = await response.json();
  return url;
}

async function sendSms(opts: any) {
  // Calls send-sms Edge Function
  const response = await fetch(`${SUPABASE_URL}/functions/v1/send-sms`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(opts),
  });
  return await response.json();
}
```

---

## 14. Edge Function 13 — generate-hero-recap

Generates the recap card image (PNG) and inserts hero_recaps row.

```typescript
// supabase/functions/generate-hero-recap/index.ts
async function handler(req: Request) {
  if (req.headers.get('Authorization') !== `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`) {
    return new Response('Unauthorised', { status: 401 });
  }

  const { session_id } = await req.json();

  const { data: session } = await supabaseAdmin
    .from('sessions')
    .select('*, child:children(name)')
    .eq('id', session_id)
    .single();

  if (!session || session.status !== 'completed') {
    return new Response('Session not completed', { status: 400 });
  }

  // Compute total XP for this session
  // Base: 1 XP per minute = duration_minutes
  // Plus healthy_bite_earned bonus, etc.
  const { data: config } = await supabaseAdmin
    .from('venue_config').select().eq('venue_id', session.venue_id).single();

  const baseXp = session.duration_minutes * (config?.xp_per_minute ?? 1);
  const bonusXp = session.healthy_bite_earned ? (config?.xp_healthy_bite ?? 20) : 0;
  const totalXp = baseXp + bonusXp;

  // Generate image (use a simple SVG → PNG conversion via @resvg/resvg-js or similar)
  const imageUrl = await generateRecapImage({
    childName: session.child.name,
    durationMinutes: session.duration_minutes,
    xpPool: totalXp,
    healthyBite: session.healthy_bite_earned,
  });

  // Insert recap row
  const reflectionDeadline = new Date(Date.now() + 24 * 60 * 60 * 1000);

  await supabaseAdmin.from('hero_recaps').insert({
    session_id,
    child_id: session.child_id,
    image_url: imageUrl,
    total_xp_pool: totalXp,
    reflection_deadline: reflectionDeadline.toISOString(),
    generated_at: new Date().toISOString(),
  });

  // Update session
  await supabaseAdmin.from('sessions').update({
    total_xp_earned: totalXp,
    reflection_deadline: reflectionDeadline.toISOString(),
  }).eq('id', session_id);

  // Push notification: recap ready
  await supabaseAdmin.from('notifications').insert({
    family_id: session.family_id,
    type: 'recap_ready',
    title: `${session.child.name} had an adventure!`,
    body: 'Tap to reflect and award XP.',
    deep_link: `/reflection/${session_id}`,
    reference_id: session_id,
  });

  return new Response(JSON.stringify({ success: true, image_url: imageUrl }));
}

async function generateRecapImage(opts: any): Promise<string> {
  // Build SVG markup
  const svg = `
    <svg width="600" height="400" xmlns="http://www.w3.org/2000/svg">
      <rect width="600" height="400" fill="#1E3A7B"/>
      <text x="300" y="100" text-anchor="middle" fill="#FFD700" font-size="32" font-weight="bold">
        ${opts.childName}'s Adventure
      </text>
      <text x="300" y="200" text-anchor="middle" fill="white" font-size="48">
        ${opts.durationMinutes} min
      </text>
      <text x="300" y="280" text-anchor="middle" fill="white" font-size="24">
        +${opts.xpPool} XP earned
      </text>
      ${opts.healthyBite ? `<text x="300" y="340" text-anchor="middle" fill="#FFD700" font-size="20">+ Healthy Bite earned</text>` : ''}
    </svg>
  `;

  // Convert SVG to PNG using resvg
  // Upload to Supabase Storage
  const fileName = `recaps/${crypto.randomUUID()}.png`;
  // ... upload PNG bytes to storage bucket
  // Return public URL
  const publicUrl = supabaseAdmin.storage.from('hero-recaps').getPublicUrl(fileName).data.publicUrl;
  return publicUrl;
}
```

This is triggered by a DB trigger on `sessions.status` flipping to `completed`.

---

## 15. Edge Function 14 — generate-invoice-pdf

Triggered after order placement. Uses a simple HTML-to-PDF approach.

```typescript
// supabase/functions/generate-invoice-pdf/index.ts
async function handler(req: Request) {
  if (req.headers.get('Authorization') !== `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`) {
    return new Response('Unauthorised', { status: 401 });
  }

  const { order_id } = await req.json();

  const { data: order } = await supabaseAdmin
    .from('orders')
    .select(`
      *,
      family:families(name, phone, email),
      items:order_items(*)
    `)
    .eq('id', order_id)
    .single();

  if (!order) return new Response('Order not found', { status: 404 });

  // Build HTML invoice
  const html = buildInvoiceHtml(order);

  // Convert to PDF (via external service or library)
  // For Deno: use puppeteer or browserless.io API
  const pdfBytes = await htmlToPdf(html);

  // Upload to Storage
  const fileName = `invoices/${order.id}.pdf`;
  await supabaseAdmin.storage.from('invoices').upload(fileName, pdfBytes, {
    contentType: 'application/pdf',
  });

  const publicUrl = supabaseAdmin.storage.from('invoices').getPublicUrl(fileName).data.publicUrl;

  await supabaseAdmin.from('orders').update({
    invoice_pdf_url: publicUrl,
  }).eq('id', order_id);

  return new Response(JSON.stringify({ success: true, invoice_url: publicUrl }));
}

function buildInvoiceHtml(order: any): string {
  // GST-compliant invoice template (per CA approval, see Pre-Launch 2.6)
  return `
    <!DOCTYPE html>
    <html>
    <head><style>/* PDF styles */</style></head>
    <body>
      <header>
        <h1>Diaries Club</h1>
        <p>GSTIN: 36ABCDE1234F1Z5</p>
      </header>
      <h2>Tax Invoice</h2>
      <p>Invoice No: ${order.id.substring(0,8).toUpperCase()}</p>
      <p>Date: ${order.created_at}</p>
      <p>Customer: ${order.family.name} | ${order.family.phone}</p>
      <table>
        <tr><th>Item</th><th>Qty</th><th>Price</th><th>Total</th></tr>
        ${order.items.map((i: any) => `
          <tr>
            <td>${i.name_snapshot}</td>
            <td>${i.quantity}</td>
            <td>₹${(i.unit_price_paise/100).toFixed(2)}</td>
            <td>₹${((i.unit_price_paise * i.quantity)/100).toFixed(2)}</td>
          </tr>
        `).join('')}
      </table>
      <p>Subtotal: ₹${(order.subtotal_paise/100).toFixed(2)}</p>
      <p>CGST 2.5%: ₹${(order.gst_paise/200).toFixed(2)}</p>
      <p>SGST 2.5%: ₹${(order.gst_paise/200).toFixed(2)}</p>
      <p><strong>Total: ₹${(order.total_paise/100).toFixed(2)}</strong></p>
    </body>
    </html>
  `;
}

async function htmlToPdf(html: string): Promise<Uint8Array> {
  // Recommended: use a managed service like browserless.io
  // or run a headless Chrome via Puppeteer + Chromium binary
  // For v1 simplicity: defer to a simple SVG/text-based approach OR use a library

  // Stub:
  return new TextEncoder().encode('PDF stub');
}
```

---

## 16. Edge Function 15 — admin-impersonate-token

```typescript
// supabase/functions/admin-impersonate-token/index.ts
async function handler(req: Request) {
  const adminId = await verifyAdminCaller(req);
  if (!adminId) return new Response('Unauthorised', { status: 401 });

  const { family_id, mode } = await req.json();
  if (mode !== 'readonly') {
    return new Response('Only readonly mode supported', { status: 400 });
  }

  // Generate short-lived JWT (5 min expiry) for the family_id with is_impersonation: true
  const token = await createJwt(
    { alg: 'HS256', typ: 'JWT' },
    {
      sub: family_id,
      role: 'authenticated',
      is_impersonation: true,
      impersonated_by: adminId,
      exp: Math.floor(Date.now() / 1000) + 300,
    },
    await getSigningKey()
  );

  // Audit
  await supabaseAdmin.from('audit_log').insert({
    actor_id: adminId,
    actor_type: 'admin',
    action: 'admin.impersonate',
    entity_type: 'family',
    entity_id: family_id,
  });

  return new Response(JSON.stringify({ token }));
}
```

The customer app on receiving this token via URL hash (only works in admin web flow):
- Sets a global flag `isImpersonating = true`
- Renders a yellow banner at top of every screen
- Disables all "submit" / "create" / "edit" actions
- After 5 min, token expires; app shows "Session ended" and routes to /auth/phone

---

## 17. Cron Schedule Summary

```toml
# supabase/config.toml

[functions.razorpay-reconcile]
schedule = "*/15 * * * *"

[functions.force-close-grace-sessions]
schedule = "* * * * *"

[functions.reflection-auto-split-cron]
schedule = "0 * * * *"

[functions.birthday-journey-cron]
schedule = "30 3 * * *"

[functions.wall-of-legends-aggregate]
schedule = "0 19 * * *"

[functions.system-health-snapshot]
schedule = "*/5 * * * *"
```

---

## 18. Deployment

```bash
# Per-function deploy
supabase functions deploy razorpay-webhook
supabase functions deploy verify-session-qr
# ... etc

# Set secrets
supabase secrets set RAZORPAY_WEBHOOK_SECRET=...
supabase secrets set MSG91_AUTH_KEY=...
supabase secrets set MSG91_SENDER_ID=DIARYC
supabase secrets set FCM_SERVER_KEY=...
supabase secrets set BRANCH_KEY=...
supabase secrets set QR_SIGNING_KEY=...
supabase secrets set SENTRY_DSN_EDGE=...
```

---

## 19. Acceptance Tests

```
TEST 1 — razorpay-webhook
  1. Use Razorpay test webhook tool to send sample payment.captured
  2. Webhook URL receives, verifies signature
  3. wallet_topup RPC fires, balance updates
  4. Audit log entry created

TEST 2 — verify-session-qr
  1. Generate QR via generate-session-qr
  2. Within 15 min: scan via staff app, verify-session-qr called
  3. nonce marked used, session confirmed
  4. Subsequent verify with same QR returns "qr_used_or_expired"

TEST 3 — Razorpay reconciliation
  1. Manually create a Razorpay payment in dashboard, then prevent webhook
  2. Wait for next reconcile cron
  3. Mismatch detected, wallet_topup fires, audit logged

TEST 4 — Force close grace sessions
  1. Manually update a session: started_at = 2hr ago, duration = 60 min, status='grace', grace_force_close_at < now
  2. Cron fires within 1 min
  3. Session status flips to 'auto_closed'
  4. Family receives notification

TEST 5 — Reflection auto-split
  1. hero_recap with reflection_status='pending', reflection_deadline = 1 min ago
  2. Cron fires
  3. xp_credit_with_split called with equal split
  4. Status flips to auto_split

TEST 6 — Birthday journey D-30 trigger
  1. Child with DOB 30 days from today, birthday_journey_state.d_minus_30_sent=false
  2. Daily cron fires
  3. d_minus_30_sent set to true BEFORE notification insert (prevents double-fire)
  4. notification inserted, push fires

TEST 7 — Wall of Legends aggregation
  1. Yesterday's stage_transitions, birthdays exist
  2. Daily cron fires
  3. wall_of_legends_daily row inserted with anonymised highlights
  4. Customer wall-of-legends sub-screen renders

TEST 8 — System health snapshot
  1. Cron fires every 5 min
  2. system_health_snapshots row inserted
  3. Admin dashboard reflects values

TEST 9 — send-push happy path
  1. Insert notifications row
  2. Trigger fires, send-push called
  3. FCM responds 200
  4. push_status='dispatched'
  5. Device receives notification

TEST 10 — send-push token-expired handling
  1. families.fcm_token contains expired/invalid token
  2. send-push called
  3. FCM returns NotRegistered
  4. families.fcm_token set to NULL
  5. push_status='failed'

TEST 11 — Reactivation blast end-to-end
  1. CSV imported, contacts=10, all pending
  2. Admin clicks SEND ALL
  3. reactivation-blast called
  4. Branch links generated, MSG91 SMS sent in batches
  5. All 10 marked sms_status='dispatched'
  6. Bell received on test phone within 30s

TEST 12 — generate-hero-recap
  1. Session marked 'completed'
  2. DB trigger calls generate-hero-recap
  3. PNG generated, uploaded to storage
  4. hero_recaps row inserted
  5. notification 'recap_ready' fired

TEST 13 — admin-impersonate-token
  1. Admin clicks impersonate from customer detail
  2. Token generated with 5-min exp
  3. Customer app opens with token, banner shown
  4. After 5 min, token expires, app re-prompts
  5. Audit log captures impersonation
```

---

## 20. Open Items for Founder

- [ ] Decide PDF generation approach: managed service (browserless.io ~$30/mo) vs self-hosted Chromium (more complex). Recommend browserless for v1.
- [ ] Confirm Sentry project per Edge Function vs single project (recommend single)
- [ ] Decide retry policy for failed pushes (currently: no retry per spec)
- [ ] Confirm branch.io campaign labels for analytics
- [ ] Verify cron timezone handling (Supabase uses UTC; we use IST for business logic)

---

## What's NOT in this session

- Customer/Staff/Admin app code (already done)
- Testing (Session 14)
- Pre-launch verification (Session 15)
