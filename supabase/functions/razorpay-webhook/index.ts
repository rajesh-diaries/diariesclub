// ===========================================================================
//  Diaries Club — razorpay-webhook Edge Function (Session 13)
//
//  Receives Razorpay webhook events. Verifies signature against
//  RAZORPAY_WEBHOOK_SECRET. Routes by event type:
//
//    payment.captured  → wallet_topup RPC (idempotent on payment_id)
//    payment.failed    → log + sentry, no DB writes
//    refund.processed  → mark refunds.status='completed' + razorpay_refund_id
//    refund.failed     → mark refunds.status='rejected', admin alert
//    order.paid        → backup for payment.captured, same handler
//
//  Auth: signature header verification — no Supabase Auth JWT involved.
//  verify_jwt MUST be set to false at deploy time so anonymous Razorpay
//  servers can POST.
//
//  Idempotency: every webhook fires through wallet_topup which is
//  idempotent on (razorpay_payment_id). Re-deliveries are safe.
// ===========================================================================

import { admin } from "./_shared/admin.ts";
import { audit } from "./_shared/audit.ts";
import {
  corsPreflight,
  errorResponse,
  jsonResponse,
} from "./_shared/response.ts";
import { captureException, captureMessage } from "./_shared/sentry.ts";

const RAZORPAY_WEBHOOK_SECRET = Deno.env.get("RAZORPAY_WEBHOOK_SECRET") ?? "";

async function hmacSha256Hex(key: string, body: string): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    cryptoKey,
    new TextEncoder().encode(body),
  );
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

interface RazorpayEvent {
  event: string;
  payload: {
    payment?: { entity: RazorpayPayment };
    refund?: { entity: RazorpayRefund };
    order?: { entity: RazorpayOrder };
  };
}

interface RazorpayPayment {
  id: string;
  amount: number;
  status: string;
  notes?: Record<string, string>;
  error_code?: string;
  error_description?: string;
}

interface RazorpayRefund {
  id: string;
  amount: number;
  payment_id: string;
  status: string;
  notes?: Record<string, string>;
  failure_reason?: string;
}

interface RazorpayOrder {
  id: string;
  amount: number;
  notes?: Record<string, string>;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "method_not_allowed" });
  }

  let rawBody: string;
  try {
    rawBody = await req.text();
  } catch (e) {
    return errorResponse(e);
  }

  // ── Signature check ─────────────────────────────────────────────────
  if (!RAZORPAY_WEBHOOK_SECRET) {
    await captureMessage("razorpay-webhook called without secret configured", {
      function: "razorpay-webhook",
      level: "error",
    });
    return jsonResponse(500, { ok: false, error: "webhook_secret_missing" });
  }

  const signature = req.headers.get("X-Razorpay-Signature") ?? "";
  if (!signature) {
    return jsonResponse(401, { ok: false, error: "missing_signature" });
  }

  const expected = await hmacSha256Hex(RAZORPAY_WEBHOOK_SECRET, rawBody);
  if (expected !== signature) {
    await captureMessage("razorpay-webhook bad signature", {
      function: "razorpay-webhook",
      level: "warning",
      extra: { received_len: signature.length },
    });
    return jsonResponse(401, { ok: false, error: "bad_signature" });
  }

  let event: RazorpayEvent;
  try {
    event = JSON.parse(rawBody) as RazorpayEvent;
  } catch (e) {
    await captureException(e, { function: "razorpay-webhook" });
    return jsonResponse(400, { ok: false, error: "bad_json" });
  }

  try {
    // Audit every event before processing.
    const entityId =
      event.payload.payment?.entity?.id ??
      event.payload.refund?.entity?.id ??
      event.payload.order?.entity?.id ??
      null;

    await audit({
      action: `razorpay.webhook.${event.event}`,
      entityType: "razorpay_event",
      entityId,
      newValue: { event_name: event.event },
    });

    switch (event.event) {
      case "payment.captured":
      case "order.paid":
        await handlePaymentCaptured(event);
        break;
      case "payment.failed":
        await handlePaymentFailed(event);
        break;
      case "refund.processed":
        await handleRefundProcessed(event);
        break;
      case "refund.failed":
        await handleRefundFailed(event);
        break;
      default:
        // Subscribed but not handled — keep audit, no error.
        console.log(`unhandled razorpay event: ${event.event}`);
    }

    return jsonResponse(200, { ok: true });
  } catch (e) {
    await captureException(e, {
      function: "razorpay-webhook",
      extra: { event: event.event },
    });
    return errorResponse(e);
  }
});

// ── Handlers ──────────────────────────────────────────────────────────────

async function handlePaymentCaptured(event: RazorpayEvent) {
  const payment =
    event.payload.payment?.entity ??
    // order.paid fires with payment in payload too sometimes; also accept
    // the order.entity as a fallback (we'd need the matching payment id
    // in notes for that, which is rare).
    null;
  if (!payment) {
    await captureMessage("payment.captured without payment entity", {
      function: "razorpay-webhook",
      level: "warning",
    });
    return;
  }

  const notes = payment.notes ?? {};
  const idempotencyKey = notes.idempotency_key ?? null;
  const familyId = notes.family_id ?? null;
  const bonusPaise = parseInt(notes.bonus_paise ?? "0", 10);

  if (!idempotencyKey || !familyId) {
    await captureMessage("payment.captured missing notes", {
      function: "razorpay-webhook",
      level: "warning",
      extra: {
        payment_id: payment.id,
        has_idempotency_key: Boolean(idempotencyKey),
        has_family_id: Boolean(familyId),
      },
    });
    return;
  }

  const { error } = await admin.rpc("wallet_topup", {
    p_family_id: familyId,
    p_amount_paise: payment.amount,
    p_bonus_paise: bonusPaise,
    p_razorpay_payment_id: payment.id,
    p_idempotency_key: idempotencyKey,
  });

  if (error) {
    await captureException(error, {
      function: "razorpay-webhook",
      extra: { payment_id: payment.id, family_id: familyId },
    });
    throw error;
  }
}

async function handlePaymentFailed(event: RazorpayEvent) {
  const payment = event.payload.payment?.entity;
  if (!payment) return;

  await captureMessage("razorpay payment failed", {
    function: "razorpay-webhook",
    level: "info",
    extra: {
      payment_id: payment.id,
      error_code: payment.error_code,
    },
  });
}

async function handleRefundProcessed(event: RazorpayEvent) {
  const refund = event.payload.refund?.entity;
  if (!refund) return;

  const ourRefundId = refund.notes?.refund_id;
  if (!ourRefundId) {
    await captureMessage("refund.processed without our refund_id in notes", {
      function: "razorpay-webhook",
      level: "warning",
      extra: { razorpay_refund_id: refund.id },
    });
    return;
  }

  const { error } = await admin
    .from("refunds")
    .update({
      status: "completed",
      razorpay_refund_id: refund.id,
      approved_at: new Date().toISOString(),
    })
    .eq("id", ourRefundId);

  if (error) {
    await captureException(error, {
      function: "razorpay-webhook",
      extra: { our_refund_id: ourRefundId },
    });
  }
}

async function handleRefundFailed(event: RazorpayEvent) {
  const refund = event.payload.refund?.entity;
  if (!refund) return;

  const ourRefundId = refund.notes?.refund_id;
  if (!ourRefundId) return;

  await admin
    .from("refunds")
    .update({ status: "rejected" })
    .eq("id", ourRefundId);

  // Critical alert — manual intervention needed (admin must reissue or
  // contact customer). Sentry warning surfaces in the admin dashboard
  // via existing Sentry → Slack integration (when wired).
  await captureMessage(
    `razorpay refund failed: ${refund.id}`,
    {
      function: "razorpay-webhook",
      level: "warning",
      extra: {
        our_refund_id: ourRefundId,
        razorpay_refund_id: refund.id,
        failure_reason: refund.failure_reason,
      },
    },
  );
}
