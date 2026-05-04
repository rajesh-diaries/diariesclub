// ===========================================================================
//  Diaries Club — admin-create-auth-user Edge Function (Session 13)
//
//  Closes the bootstrap-ceremony loop from Session 11. Lets the admin web
//  create new admin_users rows without the founder having to drop into
//  Supabase Studio.
//
//  Wire format
//  -----------
//    POST { email, name, role }   # role ∈ 'admin' | 'super_admin'
//      → { ok: true, admin_id, auth_user_id, invite_sent: true }
//
//  Auth: super_admin only (verified via requireSuperAdmin). The customer
//  uses inviteUserByEmail rather than createUser+password — Supabase
//  sends the invite email with a sign-up link, the new admin sets their
//  own password on first click. No password handoff dance.
//
//  After invite → admin_create_user RPC inserts the admin_users row.
//  RPC enforces super_admin too; we do it client-side for fast 403 + at
//  the RPC for defence in depth.
//
//  Errors:
//    - 403 not_super_admin
//    - 400 invalid_email / invalid_role
//    - 409 email_already_admin (RPC raises on duplicate)
//    - 502 invite_email_failed
// ===========================================================================

import { admin } from "./_shared/admin.ts";
import { requireSuperAdmin } from "./_shared/auth.ts";
import {
  corsPreflight,
  errorResponse,
  jsonResponse,
} from "./_shared/response.ts";
import { captureException } from "./_shared/sentry.ts";

const EMAIL_REGEX = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

interface CreateRequest {
  email?: string;
  name?: string;
  role?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "method_not_allowed" });
  }

  try {
    await requireSuperAdmin(req);

    const body = await req.json() as CreateRequest;
    const email = body.email?.trim().toLowerCase() ?? "";
    const name = body.name?.trim() ?? "";
    const role = body.role ?? "admin";

    if (!EMAIL_REGEX.test(email)) {
      return jsonResponse(400, { ok: false, error: "invalid_email" });
    }
    if (role !== "admin" && role !== "super_admin") {
      return jsonResponse(400, { ok: false, error: "invalid_role" });
    }
    if (name.length === 0 || name.length > 100) {
      return jsonResponse(400, { ok: false, error: "invalid_name" });
    }

    // Step 1: invite the user via email. Supabase creates auth.users,
    // sends the invite link. If the email already has an auth user
    // (e.g., a customer with that email), inviteUserByEmail errors;
    // we surface that.
    const { data: invite, error: inviteErr } =
      await admin.auth.admin.inviteUserByEmail(email);

    if (inviteErr || !invite.user) {
      // Common Supabase errors here: "User already registered",
      // "Email rate limit exceeded".
      if (inviteErr?.message?.includes("already")) {
        return jsonResponse(409, { ok: false, error: "email_already_in_use" });
      }
      await captureException(inviteErr ?? new Error("invite_failed_silent"), {
        function: "admin-create-auth-user",
        level: "warning",
        extra: { email },
      });
      return jsonResponse(502, { ok: false, error: "invite_email_failed" });
    }

    const authUserId = invite.user.id;

    // Step 2: insert admin_users row via the existing RPC. The RPC also
    // checks is_super_admin() and writes to audit_log. If it fails
    // (extremely unlikely now that auth.users exists), we leave the
    // auth.users row in place — super_admin can re-attempt without
    // re-inviting (the invite email is still valid for ~24h).
    const { data: rpcData, error: rpcErr } = await admin.rpc("admin_create_user", {
      p_auth_user_id: authUserId,
      p_name: name,
      p_email: email,
      p_role: role,
    });

    if (rpcErr) {
      await captureException(rpcErr, {
        function: "admin-create-auth-user",
        extra: { email, auth_user_id: authUserId },
      });
      // Don't 500 — surface the typed error so admin web can retry
      // with a clearer message.
      return jsonResponse(409, {
        ok: false,
        error: "admin_users_insert_failed",
        detail: rpcErr.message,
      });
    }

    return jsonResponse(200, {
      ok: true,
      admin_id: (rpcData as { admin_id?: string } | null)?.admin_id ?? null,
      auth_user_id: authUserId,
      invite_sent: true,
    });
  } catch (e) {
    await captureException(e, { function: "admin-create-auth-user" });
    return errorResponse(e);
  }
});
