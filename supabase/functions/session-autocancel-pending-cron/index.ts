// ===========================================================================
//  Diaries Club — session-autocancel-pending-cron Edge Function (BUG-004)
//
//  Sweeps customer-initiated wallet sessions that hit the pre-scan timeout
//  without a staff QR scan. Calls session_cancel_pending RPC for each,
//  which atomically:
//    - releases the wallet hold (held_paise -= amount)
//    - sets status='cancelled_pre_scan'
//    - audit-logs as actor_type='system'
//
//  Concurrency: session_cancel_pending re-checks status='pending' inside
//  FOR UPDATE — if qr_scan_validate races us, that branch wins and the
//  cron sees status != 'pending' and returns idempotent no-op.
//
//  Schedule: every minute (registered in 0024). Per-venue timeout via
//  venue_config.session_pre_scan_timeout_minutes (default 15).
//
//  Auth: service-role bearer. verify_jwt=true.
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

interface PendingSessionRow {
  id: string;
  venue_id: string;
  family_id: string | null;
  amount_paise: number;
  created_at: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "method_not_allowed" });
  }

  try {
    requireServiceRole(req);

    // Per-venue timeout. Walking each venue lets us honour
    // venue_config.session_pre_scan_timeout_minutes individually.
    const { data: venues, error: vErr } = await admin
      .from("venue_config")
      .select("venue_id, session_pre_scan_timeout_minutes");
    if (vErr) throw vErr;

    let cancelled = 0;
    let raced = 0;

    for (const v of venues ?? []) {
      const timeoutMin =
        ((v as { session_pre_scan_timeout_minutes?: number }).session_pre_scan_timeout_minutes) ??
        15;
      const cutoff = new Date(Date.now() - timeoutMin * 60 * 1000).toISOString();

      const { data: stale, error: sErr } = await admin
        .from("sessions")
        .select("id, venue_id, family_id, amount_paise, created_at")
        .eq("venue_id", (v as { venue_id: string }).venue_id)
        .eq("status", "pending")
        .lt("created_at", cutoff)
        .limit(200);
      if (sErr) throw sErr;
      if (!stale || stale.length === 0) continue;

      for (const s of stale as PendingSessionRow[]) {
        try {
          const { data, error } = await admin.rpc(
            "session_cancel_pending",
            { p_session_id: s.id },
          );
          if (error) {
            await captureException(error, {
              function: "session-autocancel-pending-cron",
              extra: { session_id: s.id },
            });
            continue;
          }
          // RPC returns idempotent=true when the session moved on between
          // our SELECT and the lock acquisition (qr_scan_validate won).
          if (
            (data as { idempotent?: boolean } | null)?.idempotent === true
          ) {
            raced++;
          } else {
            cancelled++;
          }
        } catch (e) {
          await captureException(e, {
            function: "session-autocancel-pending-cron",
            extra: { session_id: s.id },
          });
        }
      }
    }

    if (cancelled > 0 || raced > 0) {
      await audit({
        action: "cron.session_autocancel.run",
        entityType: "cron",
        newValue: { cancelled, raced },
      });
    }

    return jsonResponse(200, { ok: true, cancelled, raced });
  } catch (e) {
    await captureException(e, { function: "session-autocancel-pending-cron" });
    return errorResponse(e);
  }
});
