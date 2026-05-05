// ===========================================================================
//  Diaries Club — child-birthday-wishes-cron Edge Function (FEATURE-001)
//
//  Universal birthday wish for every active child on their DOB, regardless
//  of whether the family has booked a party with us. Daily 00:30 UTC = 06:00
//  IST. Two flavors:
//
//    Celebrating (any confirmed|completed birthday_reservation today):
//      "Happy birthday {child}! 🎂 Thank you for celebrating with your
//       Play Diaries family today. May your day be filled with joy ✨"
//
//    Default (everyone else):
//      "Happy birthday {child}! 🎂 Wishing you joy and lots of laughter
//       today, from your Play Diaries family ✨"
//
//  Idempotency: child_birthday_wishes_sent has UNIQUE(child_id, year). The
//  cron pre-checks; concurrent runs would also collide on insert.
//
//  Eligibility filters:
//    - children.deleted_at IS NULL
//    - children.created_at < now() - 30 days (don't wish kids who just
//      onboarded — likely a fake DOB or admin import test)
//    - families.is_walk_in = FALSE
//    - families.deleted_at IS NULL AND is_anonymised = FALSE
//    - families.last_active_at > now() - 6 months (skip dormant families)
//    - families.notification_preferences->>'birthday_wish_enabled' != 'false'
//    - venue_config.child_birthday_wish_enabled = TRUE for the child's venue
//
//  Interaction with FEATURE-002 (birthday_interest_state):
//    The wish is a UNIVERSAL brand commitment and is NOT gated by
//    birthday_interest_state. A customer who opts out for the year via
//    the discovery-page card silences the journey + sales reminders only;
//    the wish on the actual DOB still fires (preserves the delightful
//    surprise). The only opt-out path for the wish itself is the
//    per-family notification_preferences.birthday_wish_enabled = false
//    toggle in Profile → Notifications.
//
//  Channel: v1 sends push only (via the notify_push_dispatch trigger that
//  fires on notifications INSERT). SMS is deferred to v1.1 — requires
//  MSG91 DLT-approved template registration per venue.
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
import { captureException, captureMessage } from "./_shared/sentry.ts";

interface ChildRow {
  id: string;
  family_id: string;
  name: string;
  date_of_birth: string;
  venue_id?: string;
}

interface VenueCopyConfig {
  enabled: boolean;
  copy_celebrating: string;
  copy_default: string;
}

const KONDAPUR_VENUE_ID = "00000000-0000-0000-0000-000000000001";

function istToday(): { year: number; month: number; day: number } {
  const ist = new Date(Date.now() + 5.5 * 60 * 60 * 1000);
  return {
    year: ist.getUTCFullYear(),
    month: ist.getUTCMonth() + 1,
    day: ist.getUTCDate(),
  };
}

function substitute(template: string, childName: string): string {
  return template.replaceAll("{child}", childName);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "method_not_allowed" });
  }

  try {
    requireServiceRole(req);

    const today = istToday();

    // Load venue config (single-venue v1; multi-venue would loop).
    const { data: cfg } = await admin
      .from("venue_config")
      .select(
        "venue_id, child_birthday_wish_enabled, child_birthday_wish_copy_celebrating, child_birthday_wish_copy_default",
      )
      .eq("venue_id", KONDAPUR_VENUE_ID)
      .maybeSingle();

    const venueCfg: VenueCopyConfig = {
      enabled: (cfg?.child_birthday_wish_enabled as boolean | null) ?? true,
      copy_celebrating:
        (cfg?.child_birthday_wish_copy_celebrating as string | null) ??
        "Happy birthday {child}! 🎂 Thank you for celebrating with your Play Diaries family today. May your day be filled with joy ✨",
      copy_default:
        (cfg?.child_birthday_wish_copy_default as string | null) ??
        "Happy birthday {child}! 🎂 Wishing you joy and lots of laughter today, from your Play Diaries family ✨",
    };

    if (!venueCfg.enabled) {
      await audit({
        action: "cron.birthday_wishes.skipped",
        entityType: "cron",
        newValue: { reason: "venue_disabled" },
      });
      return jsonResponse(200, { ok: true, skipped: "venue_disabled" });
    }

    // Pull all candidate children. Bulk load + filter in-memory; volume is
    // small at v1 (hundreds of children, not millions).
    const { data: children, error: cErr } = await admin
      .from("children")
      .select(
        "id, family_id, name, date_of_birth, created_at, " +
          "family:families(is_walk_in, deleted_at, is_anonymised, " +
          "last_active_at, notification_preferences)",
      )
      .is("deleted_at", null);
    if (cErr) throw cErr;

    const sixMonthsAgo = Date.now() - 6 * 30 * 24 * 60 * 60 * 1000;
    const thirtyDaysAgo = Date.now() - 30 * 24 * 60 * 60 * 1000;

    let sent = 0;
    let skippedAlreadySent = 0;
    let skippedIneligible = 0;

    for (const c of children ?? []) {
      const dob = (c as { date_of_birth?: string }).date_of_birth;
      if (!dob) {
        skippedIneligible++;
        continue;
      }
      const [, mm, dd] = dob.split("-").map(Number);
      if (mm !== today.month || dd !== today.day) {
        continue;
      }

      const createdAt = new Date(
        (c as { created_at: string }).created_at,
      ).getTime();
      if (createdAt > thirtyDaysAgo) {
        skippedIneligible++;
        continue;
      }

      const f = (c as {
        family?: {
          is_walk_in?: boolean;
          deleted_at?: string | null;
          is_anonymised?: boolean;
          last_active_at?: string;
          notification_preferences?: Record<string, unknown>;
        };
      }).family;

      if (!f || f.is_walk_in || f.deleted_at || f.is_anonymised) {
        skippedIneligible++;
        continue;
      }

      const lastActive = f.last_active_at
        ? new Date(f.last_active_at).getTime()
        : 0;
      if (lastActive < sixMonthsAgo) {
        skippedIneligible++;
        continue;
      }

      const prefs = f.notification_preferences ?? {};
      if (prefs.birthday_wish_enabled === false) {
        skippedIneligible++;
        continue;
      }

      // Idempotency check (also enforced by the UNIQUE index).
      const { data: existing } = await admin
        .from("child_birthday_wishes_sent")
        .select("id")
        .eq("child_id", (c as { id: string }).id)
        .eq("year", today.year)
        .maybeSingle();
      if (existing) {
        skippedAlreadySent++;
        continue;
      }

      // Flavor: any confirmed/completed reservation today?
      const { data: res } = await admin
        .from("birthday_reservations")
        .select("id, status")
        .eq("child_id", (c as { id: string }).id)
        .in("status", ["confirmed", "completed"])
        .limit(1);

      const isCelebrating = Array.isArray(res) && res.length > 0;
      const childName = (c as { name?: string }).name ?? "your hero";
      const body = substitute(
        isCelebrating ? venueCfg.copy_celebrating : venueCfg.copy_default,
        childName,
      );

      try {
        // Insert wishes_sent FIRST so a crash mid-loop won't double-send
        // when the cron retries. UNIQUE(child_id, year) is the safety net.
        const { error: insErr } = await admin
          .from("child_birthday_wishes_sent")
          .insert({
            child_id: (c as { id: string }).id,
            year: today.year,
            was_celebrating: isCelebrating,
            channel: "push",
          });
        if (insErr) {
          // 23505 means another concurrent run already inserted; benign.
          if ((insErr as { code?: string }).code === "23505") {
            skippedAlreadySent++;
            continue;
          }
          throw insErr;
        }

        // Insert notification — push fires via notify_push_dispatch trigger.
        await admin.from("notifications").insert({
          family_id: (c as { family_id: string }).family_id,
          type: "birthday_wish",
          title: `Happy birthday, ${childName}! 🎂`,
          body,
          deep_link: "/home",
          reference_id: (c as { id: string }).id,
        });

        sent++;
      } catch (e) {
        await captureException(e, {
          function: "child-birthday-wishes-cron",
          extra: { child_id: (c as { id: string }).id },
        });
      }
    }

    await audit({
      action: "cron.birthday_wishes.run",
      entityType: "cron",
      newValue: {
        sent,
        skipped_already_sent: skippedAlreadySent,
        skipped_ineligible: skippedIneligible,
        date_ist: `${today.year}-${today.month}-${today.day}`,
      },
    });

    return jsonResponse(200, {
      ok: true,
      sent,
      skipped_already_sent: skippedAlreadySent,
      skipped_ineligible: skippedIneligible,
    });
  } catch (e) {
    await captureException(e, { function: "child-birthday-wishes-cron" });
    return errorResponse(e);
  }
});
