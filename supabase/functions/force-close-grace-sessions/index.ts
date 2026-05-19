// ===========================================================================
//  Diaries Club — force-close-grace-sessions cron Edge Function (Session 13)
//
//  Every minute. Wraps the existing force_close_grace_sessions() RPC
//  built in Session 2 / 0003_rpc_functions.sql. The RPC sweeps sessions
//  where grace_force_close_at < now() and flips them to status='auto_closed',
//  inserting a session_closed notification per family.
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

    // Phase 1 (BUG-070 / migration 0152): fire expiry-warning push the
    // moment a session passes its expires_at but before grace_force_close
    // hits. Idempotent — dedupes via notifications table.
    const warn = await admin.rpc("send_session_expiry_warnings");
    if (warn.error) throw warn.error;
    const warnedCount = (warn.data as { warned_count?: number } | null)?.warned_count ?? 0;

    // Phase 2: force-close anything that's now past grace_force_close_at.
    const { data, error } = await admin.rpc("force_close_grace_sessions");
    if (error) throw error;
    const closedCount = (data as { auto_closed_count?: number; closed_count?: number } | null)
      ?.auto_closed_count
      ?? (data as { closed_count?: number } | null)?.closed_count
      ?? 0;

    // Only audit when there's actual work — every-minute "0 / 0" entries
    // would drown audit_log.
    if (closedCount > 0 || warnedCount > 0) {
      await audit({
        action: "cron.force_close_grace.run",
        entityType: "cron",
        newValue: { warned_count: warnedCount, closed_count: closedCount },
      });
    }

    return jsonResponse(200, {
      ok: true,
      warned_count: warnedCount,
      closed_count: closedCount,
    });
  } catch (e) {
    await captureException(e, { function: "force-close-grace-sessions" });
    return errorResponse(e);
  }
});
