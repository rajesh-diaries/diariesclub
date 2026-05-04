// ===========================================================================
//  Auth helpers for Edge Functions.
//
//    requireServiceRole(req)  → decodes the bearer JWT, checks role claim
//                                is 'service_role'. Functions using this
//                                MUST be deployed with verify_jwt=true so
//                                the Supabase gateway validates the JWT
//                                signature before our code runs. Without
//                                gateway verification this would be a
//                                forgery hole.
//
//                                Why not literal string equality against
//                                Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?
//                                Because in practice the env-injected
//                                value drifts from the dashboard's
//                                visible service_role key (Supabase API-key
//                                transition / per-project quirks), and
//                                literal-equality 401's even with a
//                                freshly-copied bearer.
//
//    requireSuperAdmin(req)   → verifies a Supabase Auth JWT, checks the
//                                resulting auth.uid() against admin_users
//                                with role='super_admin' AND is_active.
//                                Returns the auth.uid() on success.
//
//    requireAdmin(req)        → same as requireSuperAdmin but accepts any
//                                active admin_users row (admin or
//                                super_admin).
//
//  All helpers throw a typed AuthError on failure. The Edge Function's
//  outer try/catch translates that into a 401/403 JSON response — see
//  errorResponse() in this module.
// ===========================================================================

import { admin } from "./admin.ts";

export class AuthError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
    this.name = "AuthError";
  }
}

/// Decode (without verifying signature) the bearer JWT and return its
/// payload. Caller must rely on the gateway (verify_jwt=true) for
/// signature validation — we only inspect claims.
function decodeBearerPayload(req: Request): Record<string, unknown> {
  const auth = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!auth) throw new AuthError(401, "missing_auth");
  const parts = auth.split(".");
  if (parts.length !== 3) throw new AuthError(401, "invalid_jwt_format");
  try {
    const payloadB64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = payloadB64.padEnd(
      payloadB64.length + ((4 - (payloadB64.length % 4)) % 4),
      "=",
    );
    const json = atob(padded);
    return JSON.parse(json) as Record<string, unknown>;
  } catch (_) {
    throw new AuthError(401, "invalid_jwt_payload");
  }
}

/// Service-role bearer check via JWT role claim. Functions using this
/// MUST be deployed with verify_jwt=true.
export function requireServiceRole(req: Request): void {
  const payload = decodeBearerPayload(req);
  if (payload.role !== "service_role") {
    throw new AuthError(403, "service_role_required");
  }
}

/// Resolves auth.uid() from the request's Bearer JWT. Throws on missing
/// or invalid JWT.
async function authenticatedUserId(req: Request): Promise<string> {
  const auth = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!auth) throw new AuthError(401, "missing_auth");
  const { data, error } = await admin.auth.getUser(auth);
  if (error || !data.user) throw new AuthError(401, "invalid_auth");
  return data.user.id;
}

/// Verifies the caller is any active admin (super_admin OR admin).
/// Returns auth.users.id.
export async function requireAdmin(req: Request): Promise<string> {
  const userId = await authenticatedUserId(req);
  const { data: row } = await admin
    .from("admin_users")
    .select("id, role, is_active")
    .eq("auth_user_id", userId)
    .eq("is_active", true)
    .maybeSingle();
  if (!row) throw new AuthError(403, "not_admin");
  return userId;
}

/// Verifies the caller is an active super_admin. Used for "promote
/// another admin" flows.
export async function requireSuperAdmin(req: Request): Promise<string> {
  const userId = await authenticatedUserId(req);
  const { data: row } = await admin
    .from("admin_users")
    .select("id, role, is_active")
    .eq("auth_user_id", userId)
    .eq("is_active", true)
    .maybeSingle();
  if (!row) throw new AuthError(403, "not_admin");
  if (row.role !== "super_admin") throw new AuthError(403, "not_super_admin");
  return userId;
}
