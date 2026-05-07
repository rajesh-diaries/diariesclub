// ===========================================================================
//  Diaries Club — auth-otp Edge Function
//
//  POST /auth-otp { action: "send",   phone }
//  POST /auth-otp { action: "verify", phone, code }
//
//  Modes
//  -----
//    OTP_MODE=mock — accepts only "123456"; no SMS sent.
//    OTP_MODE=real — generates random code, sends via MSG91.
//
//  Session minting
//  ---------------
//  After verify, ensure the auth user exists, then call
//  auth.admin.generateLink({ type:'magiclink' }) against a
//  deterministic synthetic email derived from the phone, extract
//  the token_hash from the returned action_link, and return it to
//  the client. Client redeems via verifyOtp({ token_hash, type:
//  'magiclink' }) — that gives a real session with refresh tokens.
//  The synthetic email never leaves the server.
//
//  Existing-user resolution (BUG-042, v14)
//  ---------------------------------------
//  v12 looked up existing users via /admin/users?phone=. v13 tried
//  ?email=. NEITHER is honoured by GoTrue — both query params are
//  silently ignored and the endpoint returns the first 50 users
//  ordered by created_at desc. So once auth.users grew past one
//  page (33 users today), older customers fell off page 1 and the
//  client-side `find()` returned undefined → fall through to
//  createUser → "phone already exists" → 500 user_lookup_failed
//  (and later 400-shaped variants depending on which line tripped).
//
//  v14 replaces the GoTrue REST lookup with a SECURITY DEFINER SQL
//  RPC `find_auth_user_for_otp(p_phone)` (migration 0045). The RPC
//  queries auth.users directly. service_role-only EXECUTE; no
//  client can call it.
//
//  Family payload in verify response (BUG-043, v15)
//  ------------------------------------------------
//  After verifyOTP resolves on web, there's a microtask gap before
//  the new JWT is attached to the PostgREST client. The OTP screen
//  was reading `currentFamilyProvider` immediately, which queried
//  `families` under the pre-signin context, hit `id = auth.uid()`
//  RLS denial, got null, and routed existing users to onboarding.
//  v15 returns the families row alongside the token_hash so the
//  client can route off the response directly without depending on
//  auth-state propagation. Eliminates the first-login-wrong-route
//  race entirely.
//
//  Verbose error reporting
//  -----------------------
//  Every error branch now logs `console.error("step", ...)` and
//  returns { ok:false, error, step, debug:{...} }. If something
//  still goes wrong, the response body identifies the exact branch
//  rather than us guessing from a status code alone.
//
//  Rate limiting
//  -------------
//    * 3 sends per phone per 15 min — REAL mode only (mock skips).
//    * 3 verify attempts per code (after which the row is deleted)
// ===========================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL              = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OTP_MODE                  = (Deno.env.get("OTP_MODE") ?? "mock").toLowerCase();

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

function errResponse(
  step: string,
  error: string,
  status: number,
  debug?: Record<string, unknown>,
): Response {
  console.error(`auth-otp.error step=${step} error=${error}`, debug ?? {});
  return jsonResponse({ ok: false, error, step, debug }, status);
}

// ---------------------------------------------------------------------------
//  Action: send
// ---------------------------------------------------------------------------
async function handleSend(phone: string): Promise<Response> {
  if (!E164_REGEX.test(phone)) {
    return errResponse("send.validate", "invalid_phone", 400, { phone });
  }

  try { await admin.rpc("otp_codes_cleanup"); } catch (_e) { /* ignore */ }

  if (OTP_MODE !== "mock") {
    const windowStart = new Date(Date.now() - RATE_LIMIT_WINDOW_MIN * 60_000).toISOString();
    const { count, error: countError } = await admin
      .from("otp_codes")
      .select("id", { count: "exact", head: true })
      .eq("phone", phone)
      .gte("created_at", windowStart);

    if (countError) {
      return errResponse("send.rate_limit_check", "internal", 500, {
        msg: countError.message,
      });
    }

    if ((count ?? 0) >= RATE_LIMIT_MAX_SENDS) {
      return errResponse("send.rate_limit", "rate_limited", 429, {
        sends_in_window: count,
      });
    }
  }

  const code = OTP_MODE === "mock" ? MOCK_CODE : generateOtp();
  const codeHash = await sha256Hex(code);
  const expiresAt = new Date(Date.now() + OTP_TTL_SECONDS * 1000).toISOString();

  const { error: insertError } = await admin.from("otp_codes").insert({
    phone, code_hash: codeHash, expires_at: expiresAt, attempts: 0,
  });

  if (insertError) {
    return errResponse("send.insert", "internal", 500, {
      msg: insertError.message,
    });
  }

  if (OTP_MODE === "mock") {
    console.log(`auth-otp.send.mock phone=${phone} code=${MOCK_CODE} expires=${expiresAt}`);
  } else {
    if (!MSG91_AUTH_KEY || !MSG91_TEMPLATE_ID) {
      return errResponse("send.msg91_config", "msg91_not_configured", 500);
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
        return errResponse("send.msg91_call", "sms_send_failed", 502, { result });
      }
    } catch (e) {
      return errResponse("send.msg91_throw", "sms_send_failed", 502, {
        msg: e instanceof Error ? e.message : String(e),
      });
    }
  }

  console.log(`auth-otp.send.ok phone=${phone} mode=${OTP_MODE}`);
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
    return errResponse("verify.validate_phone", "invalid_phone", 400, { phone });
  }
  if (!/^\d{6}$/.test(code)) {
    return errResponse("verify.validate_code", "invalid_code_format", 400);
  }

  const { data: rows, error: selectError } = await admin
    .from("otp_codes")
    .select("id, code_hash, expires_at, attempts, created_at")
    .eq("phone", phone)
    .gte("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false })
    .limit(1);

  if (selectError) {
    return errResponse("verify.select_otp", "internal", 500, {
      msg: selectError.message,
    });
  }

  const row = rows?.[0];
  if (!row) {
    // Diagnostic: how many otp rows exist for this phone at all (any expiry)?
    const { count: totalForPhone } = await admin
      .from("otp_codes")
      .select("id", { count: "exact", head: true })
      .eq("phone", phone);
    return errResponse("verify.no_active_code", "code_expired_or_missing", 400, {
      phone,
      now: new Date().toISOString(),
      total_rows_for_phone: totalForPhone ?? 0,
    });
  }

  if (row.attempts >= MAX_VERIFY_ATTEMPTS) {
    await admin.from("otp_codes").delete().eq("id", row.id);
    return errResponse("verify.too_many_attempts", "too_many_attempts", 429);
  }

  const candidateHash = await sha256Hex(code);
  if (candidateHash !== row.code_hash) {
    const newAttempts = row.attempts + 1;
    if (newAttempts >= MAX_VERIFY_ATTEMPTS) {
      await admin.from("otp_codes").delete().eq("id", row.id);
    } else {
      await admin.from("otp_codes").update({ attempts: newAttempts }).eq("id", row.id);
    }
    return errResponse("verify.wrong_code", "wrong_code", 400, {
      attempts_remaining: Math.max(0, MAX_VERIFY_ATTEMPTS - newAttempts),
    });
  }

  // Code matches — burn it.
  await admin.from("otp_codes").delete().eq("id", row.id);

  // BUG-042 fix (v14): use SQL RPC to look up existing users.
  const syntheticEmail = `${phone.replace("+", "")}@phone.diariesclub.local`;
  let userId: string;

  const { data: foundRows, error: findError } = await admin.rpc(
    "find_auth_user_for_otp",
    { p_phone: phone },
  );

  if (findError) {
    return errResponse("verify.find_user_rpc", "user_lookup_failed", 500, {
      msg: findError.message,
    });
  }

  const existing = (foundRows as Array<{ id: string }> | null)?.[0];

  if (existing) {
    userId = existing.id;
    const upd = await admin.auth.admin.updateUserById(userId, {
      phone: phone.replace("+", ""),
      phone_confirm: true,
      email_confirm: true,
    });
    if (upd.error) {
      // Non-fatal: log and continue with the existing id.
      console.error(`auth-otp.verify.update_user_warn id=${userId} msg=${upd.error.message}`);
    }
  } else {
    const created = await admin.auth.admin.createUser({
      phone: phone.replace("+", ""),
      email: syntheticEmail,
      phone_confirm: true,
      email_confirm: true,
    });
    if (created.error || !created.data.user) {
      return errResponse("verify.create_user", "user_create_failed", 500, {
        msg: created.error?.message,
      });
    }
    userId = created.data.user.id;
  }

  // Mint magic link → token_hash → client redeems for a session.
  const linkRes = await admin.auth.admin.generateLink({
    type:  "magiclink",
    email: syntheticEmail,
  });

  if (linkRes.error || !linkRes.data?.properties) {
    return errResponse("verify.generate_link", "session_mint_failed", 500, {
      msg: linkRes.error?.message,
    });
  }

  const tokenHash = linkRes.data.properties.hashed_token as string | undefined;

  if (!tokenHash) {
    return errResponse("verify.token_hash_missing", "session_mint_failed", 500, {
      properties_keys: Object.keys(linkRes.data.properties ?? {}),
    });
  }

  // BUG-043 fix (v15): fetch the families row server-side and return it
  // alongside the token_hash. Client routes off this directly so we don't
  // depend on auth-state propagation timing post-verifyOTP.
  const { data: familyRow, error: famErr } = await admin
    .from("families")
    .select("id, name, phone, has_children, is_cafe_only, deleted_at, is_anonymised")
    .eq("id", userId)
    .maybeSingle();

  if (famErr) {
    // Log but don't fail — client can fall back to its own family lookup.
    console.error(`auth-otp.verify.family_lookup_warn msg=${famErr.message}`);
  }

  // Soft-treat soft-deleted / anonymised families as "no family" so the
  // client routes through onboarding rather than into a tombstoned row.
  const family = (familyRow &&
    !familyRow.deleted_at &&
    !familyRow.is_anonymised)
    ? familyRow
    : null;

  console.log(`auth-otp.verify.ok phone=${phone} user_id=${userId} has_family=${family !== null}`);
  return jsonResponse({
    ok:         true,
    user_id:    userId,
    token_hash: tokenHash,
    type:       "magiclink",
    email:      syntheticEmail,
    family,
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
      return errResponse("entry.method", "method_not_allowed", 405);
    }

    let body: { action?: string; phone?: string; code?: string };
    try {
      body = await req.json();
    } catch (_e) {
      return errResponse("entry.parse_json", "invalid_json", 400);
    }

    const action = body.action;
    const phone  = body.phone;

    if (!action || !phone) {
      return errResponse("entry.missing_fields", "missing_fields", 400, {
        has_action: !!action, has_phone: !!phone,
      });
    }

    if (action === "send") {
      return await handleSend(phone);
    }
    if (action === "verify") {
      if (!body.code) return errResponse("entry.missing_code", "missing_code", 400);
      return await handleVerify(phone, body.code);
    }
    return errResponse("entry.unknown_action", "unknown_action", 400, { action });
  } catch (err) {
    const msg = err instanceof Error ? `${err.name}: ${err.message}` : String(err);
    return errResponse("entry.uncaught", "uncaught", 500, { msg });
  }
});
