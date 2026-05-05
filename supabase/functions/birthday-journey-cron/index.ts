// ===========================================================================
//  Diaries Club — birthday-journey-cron Edge Function (Session 13)
//
//  Daily at 9 AM IST (3:30 AM UTC, scheduled in 0018 via pg_cron). Walks
//  the eight D-N touchpoints (90, 60, 30, 14, 7, 3, 1, 0) and inserts
//  notifications for each child whose next birthday matches that delta
//  AND whose journey state for that touchpoint hasn't fired yet AND
//  comms aren't paused.
//
//  Anti-double-fire: we set d_minus_N_sent=true BEFORE inserting the
//  notification. If the function dies mid-run on retry it'll skip
//  already-marked rows.
//
//  Cadence (post-BUG-009): [28, 14, 7, 3]. Day-0 ("Happy birthday") is
//  owned by FEATURE-001's universal-wishes cron; this cron stops at day-3.
//  The new 28-day touch reuses the 'birthday_d_minus_30' notification
//  type and the d_minus_30_sent dedup column from birthday_journey_state
//  — close enough semantically; the 90/60/1/0 columns become unused.
//
//  Interest opt-out (FEATURE-002): children with
//  birthday_interest_state='not_this_year' are skipped entirely.
//
//  Auth: service-role bearer (cron caller). verify_jwt=true.
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

interface Touchpoint {
  days: number;
  type: string;
  sentField: keyof BirthdayJourneyRow;
  title: string;
}

// Cadence reduced to 4 touches (BUG-009). Day-0 owned by FEATURE-001.
// 28-day touch reuses the 'birthday_d_minus_30' type/dedup column.
const TOUCHPOINTS: Touchpoint[] = [
  { days: 28, type: "birthday_d_minus_30", sentField: "d_minus_30_sent", title: "4 weeks to go!" },
  { days: 14, type: "birthday_d_minus_14", sentField: "d_minus_14_sent", title: "2 weeks!" },
  { days: 7,  type: "birthday_d_minus_7",  sentField: "d_minus_7_sent",  title: "1 week!" },
  { days: 3,  type: "birthday_d_minus_3",  sentField: "d_minus_3_sent",  title: "3 days!" },
];

interface BirthdayJourneyRow {
  id?: string;
  child_id?: string;
  comms_paused?: boolean;
  d_minus_90_sent?: boolean;
  d_minus_60_sent?: boolean;
  d_minus_30_sent?: boolean;
  d_minus_14_sent?: boolean;
  d_minus_7_sent?: boolean;
  d_minus_3_sent?: boolean;
  d_minus_1_sent?: boolean;
  d_zero_sent?: boolean;
}

interface ChildRow {
  id: string;
  name: string;
  family_id: string;
  date_of_birth: string;
  daysUntilBirthday: number;
}

/// IST today as a Date at 00:00 IST. Cron runs at 3:30 AM UTC so when
/// this function fires "today" in IST is the day after the cron's UTC
/// date — we always compute against IST-day boundaries so day deltas
/// match what families experience.
function istToday(): Date {
  const nowUtc = new Date();
  // IST is UTC+5:30 (no DST). Shift then truncate to date.
  const istMs = nowUtc.getTime() + 5.5 * 60 * 60 * 1000;
  const ist = new Date(istMs);
  return new Date(Date.UTC(
    ist.getUTCFullYear(),
    ist.getUTCMonth(),
    ist.getUTCDate(),
  ));
}

function daysUntilBirthday(dob: string, today: Date): number {
  // dob is YYYY-MM-DD. Build "this year" version, advance to next year if
  // already past.
  const [, mm, dd] = dob.split("-").map(Number);
  let next = new Date(Date.UTC(today.getUTCFullYear(), mm - 1, dd));
  if (next < today) {
    next = new Date(Date.UTC(today.getUTCFullYear() + 1, mm - 1, dd));
  }
  const ms = next.getTime() - today.getTime();
  return Math.round(ms / (24 * 60 * 60 * 1000));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "method_not_allowed" });
  }

  try {
    requireServiceRole(req);

    const today = istToday();

    // Pull all active children + their journey state. The bulk row count
    // is small (hundreds at v1 scale); filter in-memory.
    // FEATURE-002: skip kids who opted out for this year via interest_state.
    const { data: children, error: cErr } = await admin
      .from("children")
      .select(
        "id, name, family_id, date_of_birth, birthday_interest_state, " +
          "family:families(is_walk_in, deleted_at, is_anonymised)",
      )
      .is("deleted_at", null)
      .neq("birthday_interest_state", "not_this_year");
    if (cErr) throw cErr;

    const eligibleChildren: ChildRow[] = [];
    for (const c of children ?? []) {
      const f = (c as { family?: { is_walk_in?: boolean; deleted_at?: string | null; is_anonymised?: boolean } }).family;
      if (!f || f.is_walk_in || f.deleted_at || f.is_anonymised) continue;
      const dob = (c as { date_of_birth?: string }).date_of_birth;
      if (!dob) continue;
      const days = daysUntilBirthday(dob, today);
      eligibleChildren.push({
        id: (c as { id: string }).id,
        name: (c as { name?: string }).name ?? "",
        family_id: (c as { family_id: string }).family_id,
        date_of_birth: dob,
        daysUntilBirthday: days,
      });
    }

    let total = 0;

    for (const tp of TOUCHPOINTS) {
      const matches = eligibleChildren.filter((c) => c.daysUntilBirthday === tp.days);
      if (matches.length === 0) continue;

      for (const child of matches) {
        try {
          // Existing journey state (may be null on first touchpoint).
          const { data: existing } = await admin
            .from("birthday_journey_state")
            .select("id, comms_paused, " +
              "d_minus_90_sent, d_minus_60_sent, d_minus_30_sent, d_minus_14_sent, " +
              "d_minus_7_sent, d_minus_3_sent, d_minus_1_sent, d_zero_sent")
            .eq("child_id", child.id)
            .maybeSingle();

          if (existing?.comms_paused) continue;
          if (existing && existing[tp.sentField] === true) continue;

          // MARK BEFORE SEND. Upsert ensures the first touchpoint creates
          // the row; subsequent touchpoints just update the field.
          const update: Record<string, unknown> = {
            child_id: child.id,
            birthday_year: today.getUTCFullYear(),
            updated_at: new Date().toISOString(),
            [tp.sentField]: true,
          };
          if (!existing) {
            update["arc_type"] = "discovery";
          }
          const { error: upErr } = await admin
            .from("birthday_journey_state")
            .upsert(update, { onConflict: "child_id" });
          if (upErr) throw upErr;

          // Active reservation?
          const { data: res } = await admin
            .from("birthday_reservations")
            .select("id")
            .eq("child_id", child.id)
            .in("status", ["interested", "admin_contacted", "confirmed"])
            .order("created_at", { ascending: false })
            .limit(1)
            .maybeSingle();

          const hasReservation = Boolean(res);

          await admin.from("notifications").insert({
            family_id: child.family_id,
            type: tp.type,
            title: tp.title,
            body: bodyFor(tp.days, child.name, hasReservation),
            deep_link: hasReservation ? `/birthday/status/${res!.id}` : "/birthday",
            reference_id: child.id,
          });

          total++;
        } catch (e) {
          await captureException(e, {
            function: "birthday-journey-cron",
            extra: { child_id: child.id, days: tp.days },
          });
        }
      }
    }

    await audit({
      action: "cron.birthday_journey.run",
      entityType: "cron",
      newValue: { eligible_children: eligibleChildren.length, sent: total },
    });

    return jsonResponse(200, { ok: true, sent: total });
  } catch (e) {
    await captureException(e, { function: "birthday-journey-cron" });
    return errorResponse(e);
  }
});

function bodyFor(days: number, name: string, hasReservation: boolean): string {
  if (hasReservation) {
    if (days === 3)  return `${name}'s party is in 3 days. Anything we should know?`;
    if (days === 7)  return `${name}'s party is one week away — exciting!`;
    if (days === 14) return `${name}'s party is 2 weeks out. Final headcount soon!`;
    if (days === 28) return `${name}'s party is 4 weeks away. All systems go!`;
    return `Your party plans are coming together. Track status in the app.`;
  }
  if (days === 28) return `${name}'s birthday is 4 weeks away. Plan it with us?`;
  if (days === 14) return `${name}'s birthday is 2 weeks away — reserve a slot?`;
  if (days === 7)  return `One week to ${name}'s birthday. Want a memorable one?`;
  if (days === 3)  return `Last call for ${name}'s birthday — 3 days away.`;
  return `${name}'s birthday approaches. Let's plan!`;
}
