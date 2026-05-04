// ===========================================================================
//  Diaries Club — generate-hero-recap-image Edge Function (Session 13)
//
//  Renders the post-session recap card as a PNG (social-share-friendly,
//  fixed 1080×1350 portrait — Instagram story aspect). Uses resvg-js
//  WASM to convert an SVG template to PNG.
//
//  Input
//  -----
//    POST { session_id }
//      → { ok: true, image_url, recap_id, total_xp_pool }
//
//  Auth: service-role bearer. Triggered from session_complete RPC's
//  follow-up worker (or manually for back-fill).
//
//  Side effects:
//    - Generates PNG, uploads to storage bucket `hero-recaps`
//      (public-read; non-PII content)
//    - Inserts hero_recaps row with image_url + reflection_deadline
//    - Updates sessions.total_xp_earned + reflection_deadline
//    - Inserts notifications row (type=recap_ready) — the
//      notify_push_dispatch trigger then fires send-push
//
//  Cold start: ~1.5s (resvg WASM load). Acceptable for async work.
//
//  Idempotency: if a hero_recaps row already exists for this session_id,
//  returns the existing image_url unchanged.
// ===========================================================================

import { Resvg, initWasm } from "https://esm.sh/@resvg/resvg-wasm@2.6.2";
import { admin } from "./_shared/admin.ts";
import { requireServiceRole } from "./_shared/auth.ts";
import { audit } from "./_shared/audit.ts";
import {
  corsPreflight,
  errorResponse,
  jsonResponse,
} from "./_shared/response.ts";
import { captureException } from "./_shared/sentry.ts";

let wasmInitialised = false;
async function ensureWasm() {
  if (wasmInitialised) return;
  const wasmRes = await fetch(
    "https://esm.sh/@resvg/resvg-wasm@2.6.2/index_bg.wasm",
  );
  await initWasm(wasmRes);
  wasmInitialised = true;
}

interface RecapRequest {
  session_id: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "method_not_allowed" });
  }

  try {
    requireServiceRole(req);
    const { session_id }: RecapRequest = await req.json();
    if (!session_id) {
      return jsonResponse(400, { ok: false, error: "missing_session_id" });
    }

    // Idempotency: existing recap → short-circuit.
    const { data: existing } = await admin
      .from("hero_recaps")
      .select("id, image_url, total_xp_pool")
      .eq("session_id", session_id)
      .maybeSingle();
    if (existing) {
      return jsonResponse(200, {
        ok: true,
        recap_id: existing.id,
        image_url: existing.image_url,
        total_xp_pool: existing.total_xp_pool,
        idempotent: true,
      });
    }

    // Load session + child + venue_config in one shot.
    const { data: session, error: sErr } = await admin
      .from("sessions")
      .select(
        "id, family_id, child_id, venue_id, duration_minutes, healthy_bite_earned, status, completed_at, child:children(name, favourite_hero)",
      )
      .eq("id", session_id)
      .maybeSingle();

    if (sErr || !session) {
      return jsonResponse(404, { ok: false, error: "session_not_found" });
    }
    if (session.status !== "completed" && session.status !== "auto_closed") {
      return jsonResponse(400, { ok: false, error: "session_not_completed" });
    }
    if (!session.child_id) {
      // Walk-in sessions don't have a child; no recap to generate.
      return jsonResponse(200, { ok: true, skipped: "walkin_no_child" });
    }

    const { data: config } = await admin
      .from("venue_config")
      .select("xp_per_minute, xp_healthy_bite_bonus, reflection_window_hours")
      .eq("venue_id", session.venue_id)
      .maybeSingle();

    const xpPerMinute = (config?.xp_per_minute as number | null) ?? 1;
    const xpHealthyBite = (config?.xp_healthy_bite_bonus as number | null) ?? 20;
    const reflectionHours = (config?.reflection_window_hours as number | null) ?? 24;

    const baseXp = session.duration_minutes * xpPerMinute;
    const bonusXp = session.healthy_bite_earned ? xpHealthyBite : 0;
    const totalXp = baseXp + bonusXp;

    const childName = (session.child as { name?: string } | null)?.name ?? "Hero";
    const hero = (session.child as { favourite_hero?: string } | null)?.favourite_hero ?? "rafi";

    // Render PNG.
    await ensureWasm();
    const svg = renderSvg({
      childName,
      heroName: heroDisplayName(hero),
      durationMinutes: session.duration_minutes,
      totalXp,
      healthyBite: session.healthy_bite_earned,
    });
    const png = new Resvg(svg, { fitTo: { mode: "width", value: 1080 } })
      .render()
      .asPng();

    // Upload to Supabase Storage (bucket: hero-recaps, public-read).
    const fileName = `${session_id}.png`;
    const { error: upErr } = await admin.storage
      .from("hero-recaps")
      .upload(fileName, png, {
        contentType: "image/png",
        upsert: true,
      });
    if (upErr) {
      throw new Error(`storage_upload_failed: ${upErr.message}`);
    }

    const { data: pub } = admin.storage.from("hero-recaps").getPublicUrl(fileName);
    const imageUrl = pub.publicUrl;

    // Insert recap + update session in a small transaction (best-effort).
    const reflectionDeadline = new Date(
      Date.now() + reflectionHours * 60 * 60 * 1000,
    );

    const { data: recap, error: insErr } = await admin
      .from("hero_recaps")
      .insert({
        session_id,
        child_id: session.child_id,
        image_url: imageUrl,
        total_xp_pool: totalXp,
        reflection_deadline: reflectionDeadline.toISOString(),
        generated_at: new Date().toISOString(),
      })
      .select()
      .single();
    if (insErr) throw new Error(`recap_insert_failed: ${insErr.message}`);

    await admin
      .from("sessions")
      .update({
        total_xp_earned: totalXp,
        reflection_deadline: reflectionDeadline.toISOString(),
      })
      .eq("id", session_id);

    // Recap-ready notification (Push fires via notify_push_dispatch trigger.)
    await admin.from("notifications").insert({
      family_id: session.family_id,
      type: "recap_ready",
      title: `${childName} had an adventure!`,
      body: `${session.duration_minutes} minutes of play. Tap to reflect & award XP.`,
      deep_link: `/reflection/${session_id}`,
      reference_id: session_id,
    });

    await audit({
      action: "hero_recap.generated",
      entityType: "hero_recap",
      entityId: recap.id,
      venueId: session.venue_id,
      newValue: { total_xp_pool: totalXp, healthy_bite: session.healthy_bite_earned },
    });

    return jsonResponse(200, {
      ok: true,
      recap_id: recap.id,
      image_url: imageUrl,
      total_xp_pool: totalXp,
    });
  } catch (e) {
    await captureException(e, { function: "generate-hero-recap-image" });
    return errorResponse(e);
  }
});

function heroDisplayName(hero: string): string {
  return ({
    rafi: "Rafi",
    ellie: "Ellie",
    gerry: "Gerry",
    zena: "Zena",
  } as Record<string, string>)[hero] ?? "Hero";
}

interface SvgInput {
  childName: string;
  heroName: string;
  durationMinutes: number;
  totalXp: number;
  healthyBite: boolean;
}

function renderSvg(o: SvgInput): string {
  // Tiny escape — child names can contain &, <, >.
  const esc = (s: string) =>
    s
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");

  return `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1350" viewBox="0 0 1080 1350">
    <defs>
      <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#1E3A7B" />
        <stop offset="1" stop-color="#0F1626" />
      </linearGradient>
    </defs>
    <rect width="1080" height="1350" fill="url(#bg)" />

    <text x="540" y="180" text-anchor="middle"
          font-family="Helvetica, Arial, sans-serif" font-size="42"
          font-weight="600" fill="#A0AAC0" letter-spacing="6">
      DIARIES CLUB
    </text>

    <text x="540" y="430" text-anchor="middle"
          font-family="Helvetica, Arial, sans-serif" font-size="86"
          font-weight="900" fill="#F5C442">
      ${esc(o.childName)}'s
    </text>
    <text x="540" y="540" text-anchor="middle"
          font-family="Helvetica, Arial, sans-serif" font-size="86"
          font-weight="900" fill="#FFFFFF">
      adventure
    </text>

    <text x="540" y="780" text-anchor="middle"
          font-family="Helvetica, Arial, sans-serif" font-size="180"
          font-weight="900" fill="#FFFFFF">
      ${o.durationMinutes}
    </text>
    <text x="540" y="850" text-anchor="middle"
          font-family="Helvetica, Arial, sans-serif" font-size="36"
          font-weight="600" fill="#A0AAC0" letter-spacing="3">
      MINUTES
    </text>

    <rect x="240" y="950" width="600" height="120" rx="60"
          fill="#F5C442" />
    <text x="540" y="1028" text-anchor="middle"
          font-family="Helvetica, Arial, sans-serif" font-size="56"
          font-weight="900" fill="#1E3A7B">
      +${o.totalXp} XP
    </text>

    ${o.healthyBite ? `
    <text x="540" y="1170" text-anchor="middle"
          font-family="Helvetica, Arial, sans-serif" font-size="32"
          font-weight="700" fill="#7BC74D">
      🥕  Healthy Bite earned
    </text>` : ""}

    <text x="540" y="1280" text-anchor="middle"
          font-family="Helvetica, Arial, sans-serif" font-size="26"
          font-weight="500" fill="#6B7280">
      ${esc(o.heroName)} is proud of ${esc(o.childName)}
    </text>
  </svg>`;
}
