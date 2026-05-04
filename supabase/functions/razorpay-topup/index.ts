// ===========================================================================
//  Diaries Club — razorpay-topup Edge Function (Session 5)
//
//  Owns the wallet top-up flow end-to-end. Mirrors the auth-otp pattern:
//  one function, two actions, mock/test/live mode switch.
//
//  Flow
//  ----
//    POST /razorpay-topup { action: "create_order", amount_paise,
//                          bonus_paise?, idempotency_key? }
//      → { ok: true, order_id, amount_paise, bonus_paise, mock: bool }
//
//    POST /razorpay-topup { action: "confirm", order_id, payment_id,
//                          signature, idempotency_key }
//      → { ok: true, new_balance_paise, amount_credited_paise }
//
//  Modes
//  -----
//    RAZORPAY_MODE=mock — skip Razorpay API, return synthetic order_id;
//                          confirm trusts client amount and credits wallet.
//                          Used for emulator dev when no Razorpay account
//                          is wired yet.
//    RAZORPAY_MODE=test — real Razorpay test-mode keys (rzp_test_*).
//    RAZORPAY_MODE=live — production keys (rzp_live_*).
//
//  Trust model
//  -----------
//  In test/live mode, `confirm` is the security boundary:
//    1. HMAC-SHA256(order_id|payment_id, KEY_SECRET) must equal signature.
//    2. We then GET /v1/orders/{order_id} from Razorpay to fetch the
//       authoritative amount and notes (bonus_paise, family_id). The
//       wallet credit uses Razorpay's amount, NOT the client's claim.
//    3. wallet_topup is service_role only — direct client calls are
//       blocked by GRANTs in migration 0003.
//
//  Idempotency
//  -----------
//  wallet_topup itself is idempotent on idempotency_key (Session 2).
//  Replaying a confirm with the same key returns the same balance, no
//  double credit. The webhook (Session 12) shares the same key path, so
//  even if both client and webhook try to confirm, only one wins.
// ===========================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL              = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_ANON_KEY         = Deno.env.get("SUPABASE_ANON_KEY")!;
const RAZORPAY_MODE     = (Deno.env.get("RAZORPAY_MODE") ?? "mock").toLowerCase();
const RAZORPAY_KEY_ID     = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
const RAZORPAY_KEY_SECRET = Deno.env.get("RAZORPAY_KEY_SECRET") ?? "";

// Hard upper bound: ₹50,000 per top-up. Caps a runaway client / compromised
// session from draining a card before the user notices.
const MAX_TOPUP_PAISE = 50_00_000;
const MIN_TOPUP_PAISE = 100; // ₹1, just to catch zero / negative misuse.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

// HMAC-SHA256 hex using WebCrypto (no external import).
async function hmacSha256Hex(key: string, msg: string): Promise<string> {
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
    new TextEncoder().encode(msg),
  );
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Resolve the authenticated user from the Authorization header. Returns the
// family_id (== auth.uid()) or null if unauthenticated / token invalid.
async function getFamilyIdFromAuth(req: Request): Promise<string | null> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return null;

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data, error } = await userClient.auth.getUser();
  if (error || !data.user) return null;
  return data.user.id;
}

// ---------------------------------------------------------------------------
//  create_order
// ---------------------------------------------------------------------------
async function handleCreateOrder(
  familyId: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const amountPaise = Number(body.amount_paise);
  const bonusPaise  = Number(body.bonus_paise ?? 0);
  const idempotencyKey =
    typeof body.idempotency_key === "string" ? body.idempotency_key : null;

  if (
    !Number.isInteger(amountPaise) ||
    amountPaise < MIN_TOPUP_PAISE ||
    amountPaise > MAX_TOPUP_PAISE
  ) {
    return jsonResponse(400, { ok: false, error: "invalid_amount" });
  }
  if (!Number.isInteger(bonusPaise) || bonusPaise < 0) {
    return jsonResponse(400, { ok: false, error: "invalid_bonus" });
  }

  // Mock mode — skip Razorpay entirely. Useful for emulator dev when the
  // tester doesn't have Razorpay keys configured. The order_id must still
  // be a string the client and the later confirm() call can correlate on.
  if (RAZORPAY_MODE === "mock") {
    const orderId = `order_mock_${crypto.randomUUID()}`;
    return jsonResponse(200, {
      ok: true,
      mock: true,
      order_id: orderId,
      amount_paise: amountPaise,
      bonus_paise: bonusPaise,
      idempotency_key: idempotencyKey,
    });
  }

  // Real mode — call Razorpay Orders API.
  if (!RAZORPAY_KEY_ID || !RAZORPAY_KEY_SECRET) {
    return jsonResponse(500, { ok: false, error: "razorpay_not_configured" });
  }

  const basicAuth = btoa(`${RAZORPAY_KEY_ID}:${RAZORPAY_KEY_SECRET}`);
  const rzpRes = await fetch("https://api.razorpay.com/v1/orders", {
    method: "POST",
    headers: {
      "Authorization": `Basic ${basicAuth}`,
      "Content-Type":  "application/json",
    },
    body: JSON.stringify({
      amount:   amountPaise, // Razorpay accepts paise directly for INR.
      currency: "INR",
      // Notes flow back through the order fetch + the webhook payload.
      notes: {
        family_id:       familyId,
        bonus_paise:     String(bonusPaise),
        idempotency_key: idempotencyKey ?? "",
      },
    }),
  });

  if (!rzpRes.ok) {
    const detail = await rzpRes.text();
    console.error("razorpay create order failed", rzpRes.status, detail);
    return jsonResponse(502, { ok: false, error: "razorpay_create_failed" });
  }

  const order = await rzpRes.json() as { id: string };
  return jsonResponse(200, {
    ok: true,
    mock: false,
    order_id: order.id,
    amount_paise: amountPaise,
    bonus_paise: bonusPaise,
    idempotency_key: idempotencyKey,
  });
}

// ---------------------------------------------------------------------------
//  confirm
// ---------------------------------------------------------------------------
async function handleConfirm(
  familyId: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const orderId   = typeof body.order_id   === "string" ? body.order_id   : "";
  const paymentId = typeof body.payment_id === "string" ? body.payment_id : "";
  const signature = typeof body.signature  === "string" ? body.signature  : "";
  const idempotencyKey =
    typeof body.idempotency_key === "string" ? body.idempotency_key : null;

  if (!orderId || !paymentId) {
    return jsonResponse(400, { ok: false, error: "missing_params" });
  }

  // The service-role client is the only one allowed to call wallet_topup
  // (REVOKE EXECUTE on PUBLIC + anon + authenticated in migration 0003).
  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  let amountPaise: number;
  let bonusPaise:  number;

  if (RAZORPAY_MODE === "mock") {
    // In mock mode the client supplies amount + bonus directly. The order_id
    // starts with "order_mock_" — sanity-check that, so a real production
    // order can never be confirmed via the mock path by accident.
    if (!orderId.startsWith("order_mock_")) {
      return jsonResponse(400, { ok: false, error: "mode_mismatch" });
    }
    amountPaise = Number(body.amount_paise ?? 0);
    bonusPaise  = Number(body.bonus_paise  ?? 0);
    if (
      !Number.isInteger(amountPaise) ||
      amountPaise < MIN_TOPUP_PAISE ||
      amountPaise > MAX_TOPUP_PAISE
    ) {
      return jsonResponse(400, { ok: false, error: "invalid_amount" });
    }
  } else {
    // Real mode — verify HMAC signature.
    if (!signature) {
      return jsonResponse(400, { ok: false, error: "missing_signature" });
    }
    if (!RAZORPAY_KEY_SECRET) {
      return jsonResponse(500, { ok: false, error: "razorpay_not_configured" });
    }
    const expected = await hmacSha256Hex(
      RAZORPAY_KEY_SECRET,
      `${orderId}|${paymentId}`,
    );
    if (expected !== signature) {
      return jsonResponse(401, { ok: false, error: "invalid_signature" });
    }

    // Fetch the authoritative order from Razorpay. The amount the client
    // claimed at create_order time is no longer trusted — we read it back
    // from Razorpay so a tampered client can't credit more than was paid.
    const basicAuth = btoa(`${RAZORPAY_KEY_ID}:${RAZORPAY_KEY_SECRET}`);
    const orderRes = await fetch(
      `https://api.razorpay.com/v1/orders/${orderId}`,
      { headers: { "Authorization": `Basic ${basicAuth}` } },
    );
    if (!orderRes.ok) {
      const detail = await orderRes.text();
      console.error("razorpay fetch order failed", orderRes.status, detail);
      return jsonResponse(502, { ok: false, error: "razorpay_fetch_failed" });
    }
    const order = await orderRes.json() as {
      amount: number;
      notes?: Record<string, string>;
      status: string;
    };

    if (order.notes?.family_id && order.notes.family_id !== familyId) {
      // Someone is trying to confirm an order created by a different user.
      return jsonResponse(403, { ok: false, error: "family_mismatch" });
    }

    amountPaise = Number(order.amount);
    bonusPaise  = Number(order.notes?.bonus_paise ?? "0");
  }

  // Credit via service-role RPC.
  const { data, error } = await admin.rpc("wallet_topup", {
    p_family_id:           familyId,
    p_amount_paise:        amountPaise,
    p_bonus_paise:         bonusPaise,
    p_razorpay_payment_id: paymentId,
    p_idempotency_key:     idempotencyKey,
  });

  if (error) {
    console.error("wallet_topup rpc failed", error);
    return jsonResponse(500, { ok: false, error: "wallet_topup_failed" });
  }

  return jsonResponse(200, {
    ok: true,
    new_balance_paise: data?.new_balance_paise,
    amount_credited_paise: data?.amount_credited,
    idempotent: data?.idempotent ?? false,
  });
}

// ---------------------------------------------------------------------------
//  Entry
// ---------------------------------------------------------------------------
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "method_not_allowed" });
  }

  try {
    const familyId = await getFamilyIdFromAuth(req);
    if (!familyId) {
      return jsonResponse(401, { ok: false, error: "unauthenticated" });
    }

    const body = await req.json() as Record<string, unknown>;
    const action = body.action;

    if (action === "create_order") return await handleCreateOrder(familyId, body);
    if (action === "confirm")      return await handleConfirm(familyId, body);

    return jsonResponse(400, { ok: false, error: "unknown_action" });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("razorpay-topup uncaught", msg);
    return jsonResponse(500, { ok: false, error: "uncaught", detail: msg });
  }
});
