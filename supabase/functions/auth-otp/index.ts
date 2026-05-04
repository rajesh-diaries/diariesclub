// ===========================================================================
//  Diaries Club — auth-otp Edge Function (Session 4)
//
//  Pattern B: this function owns OTP issuance + verification end-to-end.
//
//  Flow
//  ----
//    POST /auth-otp { action: "send",   phone }
//    POST /auth-otp { action: "verify", phone, code }
//
//  Modes
//  -----
//    OTP_MODE=mock   — accepts only "123456"; no SMS sent.
//                      Used in dev so devs don't burn MSG91 credit.
//    OTP_MODE=real   — generates a random 6-digit code, hashes it, stores
//                      it, sends via MSG91. (MSG91 fetch path is sketched
//                      but not exercised until Session 12 plugs in keys.)
//
//  Session minting
//  ---------------
//  After a successful verify, we ensure the auth user exists (admin.createUser
//  with phone_confirm:true), then call auth.admin.generateLink with type
//  'magiclink' against a synthetic phone-tied email. We extract the
//  `token_hash` from the returned action_link and return it to the client.
//  The client redeems it via supabase.auth.verifyOtp({ token_hash, type:
//  'magiclink' }) — that's what gives us a real session with refresh tokens.
//  The synthetic email never leaves the server (we don't email it; we just
//  need it to satisfy generateLink's signature).
//
//  Rate limiting
//  -------------
//    * 3 sends per phone per 15 minutes (returns 429)
//    * 3 verify attempts per code (after which the code row is deleted)
//
//  Audit / logging
//  ---------------
//  Edge Function logs (visible via `supabase functions logs auth-otp`) are
//  the audit trail for OTP itself. Once the user is signed in and family_create
//  runs, audit_log gets a 'family.create' entry — that's the durable record.
// ===========================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
// Use the built-in WebCrypto API (globalThis.crypto). It's available in
// every modern runtime including Supabase Edge Functions, no extra import
// needed. (We had a deno.land/std import here that crashed cold-start.)

const SUPABASE_URL              = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OTP_MODE                  = (Deno.env.get("OTP_MODE") ?? "mock").toLowerCase();

// MSG91 — populated in Session 12. Referenced here so the real-mode code
// compiles, but never exercised while OTP_MODE=mock.
const MSG91_AUTH_KEY    = Deno.env.get("MSG91_AUTH_KEY")    ?? "";
const MSG91_TEMPLATE_ID = Deno.env.get("MSG91_TEMPLATE_ID") ?? "";
const MSG91_SENDER_ID   = Deno.env.get("MSG91_SENDER_ID")   ?? "DIARYC";

const OTP_TTL_SECONDS         = 600;            // 10 minutes
const RATE_LIMIT_WINDOW_MIN   = 15;
const RATE_LIMIT_MAX_SENDS    = 3;
const MAX_VERIFY_ATTEMPTS     = 3;
const MOCK_CODE               = "123456";

const E164_REGEX = /^\+91[6-9]\d{9}$/;

const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const corsHeaders = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Headers": "authorization, content-type, x-client-info, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ---------------------------------------------------------------------------
//  Crypto helpers
// ---------------------------------------------------------------------------
async function sha256Hex(input: string): Promise<string> {
  const buf = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", buf);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function generateOtp(): string {
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000;
  return n.toString().padStart(6, "0");
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

// ---------------------------------------------------------------------------
//  Action: send
// ---------------------------------------------------------------------------
async function handleSend(phone: string): Promise<Response> {
  if (!E164_REGEX.test(phone)) {
    return jsonResponse({ ok: false, error: "invalid_phone" }, 400);
  }

  // Best-effort cleanup of stale rows.
  try { await admin.rpc("otp_codes_cleanup"); } catch (_e) { /* ignore */ }

  // Rate limit: count sends for this phone in the rolling window.
  const windowStart = new Date(Date.now() - RATE_LIMIT_WINDOW_MIN * 60_000).toISOString();
  const { count, error: countError } = await admin
    .from("otp_codes")
    .select("id", { count: "exact", head: true })
    .eq("phone", phone)
    .gte("created_at", windowStart);

  if (countError) {
    console.error("rate_limit_check_failed", countError);
    return jsonResponse({ ok: false, error: "internal" }, 500);
  }

  if ((count ?? 0) >= RATE_LIMIT_MAX_SENDS) {
    return jsonResponse({ ok: false, error: "rate_limited" }, 429);
  }

  const code = OTP_MODE === "mock" ? MOCK_CODE : generateOtp();
  const codeHash = await sha256Hex(code);
  const expiresAt = new Date(Date.now() + OTP_TTL_SECONDS * 1000).toISOString();

  const { error: insertError } = await admin.from("otp_codes").insert({
    phone, code_hash: codeHash, expires_at: expiresAt, attempts: 0,
  });

  if (insertError) {
    console.error("otp_insert_failed", insertError);
    return jsonResponse({ ok: false, error: "internal" }, 500);
  }

  if (OTP_MODE === "mock") {
    console.log(`[mock] OTP for ${phone} = ${MOCK_CODE} (expires ${expiresAt})`);
  } else {
    // Session 12 wires the real MSG91 keys + DLT-approved template_id.
    if (!MSG91_AUTH_KEY || !MSG91_TEMPLATE_ID) {
      console.error("msg91_not_configured");
      return jsonResponse({ ok: false, error: "msg91_not_configured" }, 500);
    }
    try {
      const mobile = phone.replace("+", "");
      const res = await fetch("https://control.msg91.com/api/v5/flow/", {
        method:  "POST",
        headers: { authkey: MSG91_AUTH_KEY, "content-type": "application/json" },
        body: JSON.stringify({
          template_id: MSG91_TEMPLATE_ID,
          sender:      MSG91_SENDER_ID,
          short_url:   "0",
          recipients:  [{ mobiles: mobile, var1: code }],
        }),
      });
      const result = await res.json();
      if (result.type !== "success") {
        console.error("msg91_failed", result);
        return jsonResponse({ ok: false, error: "sms_send_failed" }, 502);
      }
    } catch (e) {
      console.error("msg91_threw", e);
      return jsonResponse({ ok: false, error: "sms_send_failed" }, 502);
    }
  }

  return jsonResponse({
    ok: true,
    expires_in: OTP_TTL_SECONDS,
    mode: OTP_MODE,
  });
}

// ---------------------------------------------------------------------------
//  Action: verify
// ---------------------------------------------------------------------------
async function handleVerify(phone: string, code: string): Promise<Response> {
  if (!E164_REGEX.test(phone)) {
    return jsonResponse({ ok: false, error: "invalid_phone" }, 400);
  }
  if (!/^\d{6}$/.test(code)) {
    return jsonResponse({ ok: false, error: "invalid_code_format" }, 400);
  }

  // Mock mode: belt-and-braces — verify against the stored hash like real
  // mode does. We don't accept "any 6-digit code" — only "123456". The hash
  // check below enforces that because mock-mode `send` only ever stores
  // hash(MOCK_CODE).
  // (We could also short-circuit `if (code !== MOCK_CODE) reject`, but going
  // through the same path keeps the two modes' behaviour symmetric, including
  // rate-limiting and attempts.)

  // Latest unexpired row for this phone.
  const { data: rows, error: selectError } = await admin
    .from("otp_codes")
    .select("id, code_hash, expires_at, attempts")
    .eq("phone", phone)
    .gte("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false })
    .limit(1);

  if (selectError) {
    console.error("otp_select_failed", selectError);
    return jsonResponse({ ok: false, error: "internal" }, 500);
  }

  const row = rows?.[0];
  if (!row) {
    return jsonResponse({ ok: false, error: "code_expired_or_missing" }, 400);
  }

  if (row.attempts >= MAX_VERIFY_ATTEMPTS) {
    await admin.from("otp_codes").delete().eq("id", row.id);
    return jsonResponse({ ok: false, error: "too_many_attempts" }, 429);
  }

  const candidateHash = await sha256Hex(code);
  if (candidateHash !== row.code_hash) {
    const newAttempts = row.attempts + 1;
    if (newAttempts >= MAX_VERIFY_ATTEMPTS) {
      await admin.from("otp_codes").delete().eq("id", row.id);
    } else {
      await admin.from("otp_codes").update({ attempts: newAttempts }).eq("id", row.id);
    }
    return jsonResponse({
      ok: false,
      error: "wrong_code",
      attempts_remaining: Math.max(0, MAX_VERIFY_ATTEMPTS - newAttempts),
    }, 400);
  }

  // Code matches — burn it.
  await admin.from("otp_codes").delete().eq("id", row.id);

  // Ensure the auth user exists. Synthetic email so generateLink works.
  const syntheticEmail = `${phone.replace("+", "")}@phone.diariesclub.local`;
  let userId: string;

  // Try to create; if a user with this phone already exists, look it up.
  const created = await admin.auth.admin.createUser({
    phone,
    email: syntheticEmail,
    phone_confirm: true,
    email_confirm: true,
  });

  if (!created.error && created.data.user) {
    userId = created.data.user.id;
  } else {
    // Existing user. Look up via the GoTrue admin REST endpoint, which
    // supports filtering by phone (the JS SDK doesn't expose this directly).
    const lookupRes = await fetch(
      `${SUPABASE_URL}/auth/v1/admin/users?phone=${encodeURIComponent(phone.replace("+", ""))}`,
      {
        headers: {
          apikey:        SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        },
      },
    );
    if (!lookupRes.ok) {
      const txt = await lookupRes.text();
      console.error("user_lookup_failed", lookupRes.status, txt);
      return jsonResponse({ ok: false, error: "user_lookup_failed" }, 500);
    }
    const lookup = await lookupRes.json();
    const existing = lookup.users?.find(
      (u: { phone?: string }) => u.phone === phone.replace("+", ""),
    );
    if (!existing) {
      console.error("user_not_found_after_create_conflict", created.error);
      return jsonResponse({ ok: false, error: "user_lookup_failed" }, 500);
    }
    userId = existing.id;

    // Make sure the synthetic email + phone confirmation are set on the
    // existing row — pre-existing rows from earlier sessions might lack them.
    await admin.auth.admin.updateUserById(userId, {
      email:         existing.email ?? syntheticEmail,
      phone_confirm: true,
      email_confirm: true,
    });
  }

  // Mint a magic link → extract token_hash → client redeems it for a session.
  const linkRes = await admin.auth.admin.generateLink({
    type:  "magiclink",
    email: syntheticEmail,
  });

  if (linkRes.error || !linkRes.data?.properties) {
    console.error("generate_link_failed", linkRes.error);
    return jsonResponse({ ok: false, error: "session_mint_failed" }, 500);
  }

  // generateLink returns the hashed token directly in `properties.hashed_token`.
  // That's what the client passes to supabase.auth.verifyOtp(tokenHash:..., type: magiclink).
  const tokenHash = linkRes.data.properties.hashed_token as string | undefined;

  if (!tokenHash) {
    console.error("token_hash_missing", linkRes.data.properties);
    return jsonResponse({ ok: false, error: "session_mint_failed" }, 500);
  }

  return jsonResponse({
    ok:         true,
    user_id:    userId,
    token_hash: tokenHash,
    type:       "magiclink",
    email:      syntheticEmail,
  });
}

// ---------------------------------------------------------------------------
//  Entry
// ---------------------------------------------------------------------------
Deno.serve(async (req) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }
    if (req.method !== "POST") {
      return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
    }

    let body: { action?: string; phone?: string; code?: string };
    try {
      body = await req.json();
    } catch (_e) {
      return jsonResponse({ ok: false, error: "invalid_json" }, 400);
    }

    const action = body.action;
    const phone  = body.phone;

    if (!action || !phone) {
      return jsonResponse({ ok: false, error: "missing_fields" }, 400);
    }

    if (action === "send") {
      return await handleSend(phone);
    }
    if (action === "verify") {
      if (!body.code) return jsonResponse({ ok: false, error: "missing_code" }, 400);
      return await handleVerify(phone, body.code);
    }
    return jsonResponse({ ok: false, error: "unknown_action" }, 400);
  } catch (err) {
    // Surface the error message to the client so we can see what blew up.
    // (Stub-only — we'd want to scrub before shipping to prod.)
    const msg = err instanceof Error ? `${err.name}: ${err.message}` : String(err);
    console.error("uncaught", msg, err);
    return jsonResponse({ ok: false, error: "uncaught", detail: msg }, 500);
  }
});
