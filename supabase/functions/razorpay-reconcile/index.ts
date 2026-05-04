// ===========================================================================
//  Diaries Club — razorpay-reconcile cron Edge Function (Session 13)
//
//  Every 15 minutes. Catches Razorpay payments that captured but where
//  our webhook either never arrived or failed mid-process. We fetch the
//  last 30 minutes of captured payments via Razorpay API, compare
//  against wallet_transactions, and back-fill via wallet_topup with a
//  recon-{payment_id} idempotency key.
//
//  wallet_topup is idempotent on (razorpay_payment_id) — if we race with
//  a delayed webhook, no double credit.
//
//  Auth: service-role bearer (cron caller).
// ===========================================================================

import { admin } from "./_shared/admin.ts";
import { requireServiceRole } from "./_shared/auth.ts";
import { audit } from "./_shared/audit.ts";
import {
  corsPreflight,
  errorResponse,
  jsonResponse,
} from "./_shared/response.ts";
import { captureException, captureMessage } from "./_shared/sentry.ts";

const RAZORPAY_KEY_ID = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
const RAZORPAY_KEY_SECRET = Deno.env.get("RAZORPAY_KEY_SECRET") ?? "";

interface RazorpayPayment {
  id: string;
  amount: number;
  status: string;
  notes?: Record<string, string>;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "method_not_allowed" });
  }

  try {
    requireServiceRole(req);

    if (!RAZORPAY_KEY_ID || !RAZORPAY_KEY_SECRET) {
      return jsonResponse(500, { ok: false, error: "razorpay_not_configured" });
    }

    const since = Math.floor((Date.now() - 30 * 60 * 1000) / 1000);
    const auth = btoa(`${RAZORPAY_KEY_ID}:${RAZORPAY_KEY_SECRET}`);

    const res = await fetch(
      `https://api.razorpay.com/v1/payments?from=${since}&count=100`,
      { headers: { Authorization: `Basic ${auth}` } },
    );
    if (!res.ok) {
      const detail = await res.text();
      throw new Error(`razorpay_fetch_failed: ${res.status} ${detail}`);
    }
    const body = await res.json() as { items?: RazorpayPayment[] };
    const payments = body.items ?? [];

    let mismatches = 0;
    let corrected = 0;
    let totalCorrectedPaise = 0;

    for (const payment of payments) {
      if (payment.status !== "captured") continue;

      const { data: existing } = await admin
        .from("wallet_transactions")
        .select("id")
        .eq("razorpay_payment_id", payment.id)
        .maybeSingle();

      if (existing) continue;

      mismatches++;

      const familyId = payment.notes?.family_id;
      if (!familyId) {
        await captureMessage(
          `reconcile: payment ${payment.id} missing family_id in notes`,
          {
            function: "razorpay-reconcile",
            level: "warning",
            extra: { payment_id: payment.id, amount: payment.amount },
          },
        );
        continue;
      }

      const idempotencyKey =
        payment.notes?.idempotency_key ?? `recon-${payment.id}`;
      const bonusPaise = parseInt(payment.notes?.bonus_paise ?? "0", 10);

      const { error: rpcErr } = await admin.rpc("wallet_topup", {
        p_family_id: familyId,
        p_amount_paise: payment.amount,
        p_bonus_paise: bonusPaise,
        p_razorpay_payment_id: payment.id,
        p_idempotency_key: idempotencyKey,
      });

      if (rpcErr) {
        await captureException(rpcErr, {
          function: "razorpay-reconcile",
          extra: { payment_id: payment.id, family_id: familyId },
        });
        continue;
      }

      corrected++;
      totalCorrectedPaise += payment.amount;

      // Big-amount → escalate as warning. Most reconciles are small or
      // duplicate-of-webhook; a missing ₹1k+ topup means a real customer
      // is short on balance.
      if (payment.amount >= 100000) {
        await captureMessage(
          `reconcile corrected missing topup ${payment.id} (₹${payment.amount / 100})`,
          {
            function: "razorpay-reconcile",
            level: "warning",
            extra: { payment_id: payment.id, family_id: familyId, amount: payment.amount },
          },
        );
      }
    }

    await admin.from("reconciliation_log").insert({
      type: "razorpay",
      ran_at: new Date().toISOString(),
      payments_checked: payments.length,
      discrepancies_found: mismatches,
      total_corrected_paise: totalCorrectedPaise,
      status: mismatches === corrected ? "success" : "partial",
      details: { corrected_count: corrected },
    });

    await audit({
      action: "cron.razorpay_reconcile.run",
      entityType: "cron",
      newValue: {
        payments_checked: payments.length,
        mismatches,
        corrected,
        total_corrected_paise: totalCorrectedPaise,
      },
    });

    return jsonResponse(200, {
      ok: true,
      payments_checked: payments.length,
      mismatches,
      corrected,
    });
  } catch (e) {
    await captureException(e, { function: "razorpay-reconcile" });
    return errorResponse(e);
  }
});
