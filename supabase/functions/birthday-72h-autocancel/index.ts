// ===========================================================================
//  Diaries Club — birthday-72h-autocancel cron Edge Function (Session 13)
//
//  Sweeps interest reservations that admin hasn't moved within
//  venue_config.birthday_interest_ttl_hours (default 72). Sets status to
//  cancelled with cancelled_reason='auto_72h_no_admin_contact'. Notifies
//  the family that the request expired and they can re-submit.
//
//  Auth: service-role bearer (cron). Schedule: every hour, set up via
//  pg_cron in migration 0018.
//
//  Why an hourly cron and not a per-row trigger? Because the deadline is
//  a moving target (admin can move status 'interested → admin_contacted'
//  at any minute). An hourly sweep with a single SQL statement is
//  cheaper than triggers tracking per-row TTL.
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

const KONDAPUR_VENUE_ID = "00000000-0000-0000-0000-000000000001";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "method_not_allowed" });
  }

  try {
    requireServiceRole(req);

    const { data: cfg } = await admin
      .from("venue_config")
      .select("birthday_interest_ttl_hours")
      .eq("venue_id", KONDAPUR_VENUE_ID)
      .maybeSingle();

    const ttlHours = (cfg?.birthday_interest_ttl_hours as number | null) ?? 72;
    const cutoff = new Date(Date.now() - ttlHours * 60 * 60 * 1000);

    const { data: stale, error: selErr } = await admin
      .from("birthday_reservations")
      .select("id, family_id, child_id, venue_id, package_price_paise")
      .eq("status", "interested")
      .lt("created_at", cutoff.toISOString())
      .limit(200);

    if (selErr) throw selErr;
    if (!stale || stale.length === 0) {
      return jsonResponse(200, { ok: true, cancelled: 0 });
    }

    let cancelled = 0;

    for (const r of stale) {
      const { error: updErr } = await admin
        .from("birthday_reservations")
        .update({
          status: "cancelled",
          cancelled_reason: "auto_72h_no_admin_contact",
          cancelled_at: new Date().toISOString(),
        })
        .eq("id", r.id)
        .eq("status", "interested"); // race-safe re-check

      if (updErr) {
        await captureException(updErr, {
          function: "birthday-72h-autocancel",
          extra: { reservation_id: r.id },
        });
        continue;
      }

      // Pause the journey state so D-N reminders stop.
      await admin
        .from("birthday_journey_state")
        .update({ arc_type: "paused", updated_at: new Date().toISOString() })
        .eq("child_id", r.child_id);

      // Notify family. They can re-submit interest later.
      await admin.from("notifications").insert({
        family_id: r.family_id,
        type: "birthday_d_minus_60",
        title: "Birthday request expired",
        body:
          "We didn't get a chance to reach out. Re-submit anytime — we'd love to celebrate with you.",
        deep_link: "/birthday",
        reference_id: r.id,
      });

      cancelled++;
    }

    await audit({
      action: "cron.birthday_72h_autocancel.run",
      entityType: "cron",
      newValue: { ttl_hours: ttlHours, candidates: stale.length, cancelled },
    });

    return jsonResponse(200, { ok: true, cancelled });
  } catch (e) {
    await captureException(e, { function: "birthday-72h-autocancel" });
    return errorResponse(e);
  }
});
