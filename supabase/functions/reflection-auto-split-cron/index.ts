// ===========================================================================
//  Diaries Club — reflection-auto-split-cron Edge Function (Session 13)
//
//  Hourly. Wraps the existing reflection_auto_split() RPC built in
//  Session 6 / 0010_reflection_auto_split.sql. The RPC iterates
//  hero_recaps where reflection_status='pending' and reflection_deadline
//  has passed, awarding the XP pool equally across the four traits.
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
import { captureException } from "./_shared/sentry.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "method_not_allowed" });
  }

  try {
    requireServiceRole(req);

    const { data, error } = await admin.rpc("reflection_auto_split");
    if (error) throw error;

    await audit({
      action: "cron.reflection_auto_split.run",
      entityType: "cron",
      newValue: (data as Record<string, unknown> | null) ?? {},
    });

    return jsonResponse(200, { ok: true, result: data });
  } catch (e) {
    await captureException(e, { function: "reflection-auto-split-cron" });
    return errorResponse(e);
  }
});
