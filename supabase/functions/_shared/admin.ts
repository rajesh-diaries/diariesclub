// ===========================================================================
//  Service-role Supabase client. Used by every Edge Function that writes to
//  the DB on behalf of the system (cron loops, webhook receivers, push
//  dispatch). Never instantiated in customer-facing code paths.
//
//  Re-exports a single shared instance — Deno keeps the module alive for
//  the function instance's lifetime, so we get connection pooling for free.
// ===========================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error(
    "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY env. Check Supabase Secrets.",
  );
}

export const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

export { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY };
