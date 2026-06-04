import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string

if (!url || !key) {
  throw new Error(
    'Missing VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY. Copy .env.example → .env.local.',
  )
}

// One tablet auth session per device, persisted so the console survives
// reloads and home-screen relaunches without re-login.
export const supabase = createClient(url, key, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    storageKey: 'pd-staff-auth',
  },
})

/** Thin helper: call an RPC and return its JSON, throwing on Postgrest errors. */
export async function rpc<T = unknown>(
  fn: string,
  params?: Record<string, unknown>,
): Promise<T> {
  const { data, error } = await supabase.rpc(fn, params)
  if (error) throw error
  return data as T
}
