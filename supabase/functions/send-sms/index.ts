// ===========================================================================
//  Diaries Club — send-sms Edge Function (Session 13)
//
//  Generic MSG91 SMS sender for non-OTP flows:
//    - birthday-journey-cron D-N reminders
//    - reactivation campaigns (when Branch lands; v1.1)
//    - admin one-off blasts (future admin tool)
//
//  OTP send still goes through auth-otp (Session 4) — that function owns
//  the otp_codes table, hashing, and rate limiting. send-sms is for
//  template-driven messaging where the body is fully resolved at the
//  caller (variables passed in).
//
//  Wire format
//  -----------
//    POST { phone, template_id, variables, idempotency_key? }
//      → { ok: true,  msg91_id }
//      → { ok: false, error: <slug> }
//
//  Auth
//  ----
//    Service-role bearer required. Cron jobs and other Edge Functions
//    pass the SUPABASE_SERVICE_ROLE_KEY they read from env.
// ===========================================================================

import { admin } from "./_shared/admin.ts";
import { requireServiceRole } from "./_shared/auth.ts";
import { audit } from "./_shared/audit.ts";
import {
  corsPreflight,
  errorResponse,
  jsonResponse,
} from "./_shared/response.ts";
import { captureException } from "./_shared/sentry.ts";

const MSG91_AUTH_KEY = Deno.env.get("MSG91_AUTH_KEY") ?? "";
const MSG91_SENDER_ID = Deno.env.get("MSG91_SENDER_ID") ?? "DIARYC";

const E164_REGEX = /^\+91[6-9]\d{9}$/;

interface SmsRequest {
  phone: string;
  template_id: string;
  variables?: string[];
  idempotency_key?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "method_not_allowed" });
  }

  try {
    requireServiceRole(req);

    if (!MSG91_AUTH_KEY) {
      return jsonResponse(500, { ok: false, error: "msg91_not_configured" });
    }

    const body = await req.json() as SmsRequest;
    const { phone, template_id, variables, idempotency_key } = body;

    if (!phone || !E164_REGEX.test(phone)) {
      return jsonResponse(400, { ok: false, error: "invalid_phone" });
    }
    if (!template_id) {
      return jsonResponse(400, { ok: false, error: "missing_template_id" });
    }

    // Idempotency. We log every send to audit_log; a matching prior send
    // with the same idempotency_key short-circuits.
    if (idempotency_key) {
      const { data: prior } = await admin
        .from("audit_log")
        .select("new_value")
        .eq("action", "sms.dispatched")
        .filter("new_value->>idempotency_key", "eq", idempotency_key)
        .maybeSingle();
      if (prior) {
        return jsonResponse(200, {
          ok: true,
          idempotent: true,
          msg91_id: (prior.new_value as { msg91_id?: string })?.msg91_id ?? null,
        });
      }
    }

    const mobile = phone.replace("+", "");
    const recipient: Record<string, string> = { mobiles: mobile };
    (variables ?? []).forEach((v, i) => {
      recipient[`var${i + 1}`] = v;
    });

    const res = await fetch("https://control.msg91.com/api/v5/flow/", {
      method: "POST",
      headers: {
        authkey: MSG91_AUTH_KEY,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        template_id,
        sender: MSG91_SENDER_ID,
        short_url: "0",
        recipients: [recipient],
      }),
    });

    const result = await res.json() as { type?: string; message?: string };

    if (result.type !== "success") {
      await captureException(
        new Error(`msg91 dispatch failed: ${result.message ?? "unknown"}`),
        { function: "send-sms", level: "warning", extra: { template_id } },
      );
      await audit({
        action: "sms.failed",
        entityType: "sms",
        newValue: {
          template_id,
          error: result.message ?? "unknown",
          idempotency_key: idempotency_key ?? null,
        },
      });
      return jsonResponse(502, {
        ok: false,
        error: "sms_send_failed",
      });
    }

    await audit({
      action: "sms.dispatched",
      entityType: "sms",
      newValue: {
        template_id,
        msg91_id: result.message,
        idempotency_key: idempotency_key ?? null,
      },
    });

    return jsonResponse(200, {
      ok: true,
      msg91_id: result.message,
    });
  } catch (e) {
    await captureException(e, { function: "send-sms" });
    return errorResponse(e);
  }
});
