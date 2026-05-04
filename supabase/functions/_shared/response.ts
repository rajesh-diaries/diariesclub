// ===========================================================================
//  JSON response helpers. Standardise the wire format so the customer +
//  staff + admin apps can rely on a consistent { ok: true } / { ok: false,
//  error: '<slug>' } shape across every Edge Function.
//
//  Errors NEVER include stack traces or raw exception messages — those
//  leak implementation details to clients. The `detail` field is only
//  populated for `internal` errors and even then is summarised.
// ===========================================================================

import { AuthError } from "./auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function corsPreflight(): Response {
  return new Response(null, { status: 204, headers: corsHeaders });
}

export function jsonResponse(
  status: number,
  body: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

export function errorResponse(error: unknown): Response {
  if (error instanceof AuthError) {
    return jsonResponse(error.status, { ok: false, error: error.message });
  }
  // Surface a stable slug; never leak raw error text.
  console.error("uncaught_edge_function_error", error);
  return jsonResponse(500, { ok: false, error: "internal" });
}
