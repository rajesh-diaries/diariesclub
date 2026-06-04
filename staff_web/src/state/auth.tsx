import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'

/** A staff member verified via PIN. Reusable for ~30s so a multi-step
 *  flow (PIN → confirm → submit) doesn't re-prompt. */
export interface VerifiedStaff {
  staffId: string
  staffName: string
  role: string
  forcePinChange: boolean
  verifiedAtMs: number
}

interface TabletDevice {
  venue_id: string
  label?: string | null
  venue_name?: string | null
}

interface AuthValue {
  session: Session | null
  loading: boolean
  device: TabletDevice | null
  deviceError: 'revoked' | null
  venueId: string | null
  venueLabel: string
  signIn: (email: string, password: string) => Promise<void>
  signOut: () => Promise<void>
  /** Last PIN-verified staff, if still fresh (<30s). */
  verifiedStaff: VerifiedStaff | null
  setVerifiedStaff: (s: VerifiedStaff | null) => void
}

const Ctx = createContext<AuthValue | null>(null)
const PIN_TTL_MS = 30_000

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)
  const [device, setDevice] = useState<TabletDevice | null>(null)
  const [deviceError, setDeviceError] = useState<'revoked' | null>(null)
  const [verifiedStaff, setVerifiedStaff] = useState<VerifiedStaff | null>(null)

  // Track the tablet auth session.
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setLoading(false)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => {
      setSession(s)
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  // Resolve this tablet's venue from tablet_devices once signed in.
  useEffect(() => {
    const uid = session?.user?.id
    if (!uid) {
      setDevice(null)
      setDeviceError(null)
      return
    }
    let cancelled = false
    supabase
      .from('tablet_devices')
      .select('venue_id, device_label, is_active, venues(name)')
      .eq('auth_user_id', uid)
      .eq('is_active', true)
      .maybeSingle()
      .then(({ data }) => {
        if (cancelled) return
        if (!data) {
          setDevice(null)
          setDeviceError('revoked')
          return
        }
        setDeviceError(null)
        setDevice({
          venue_id: data.venue_id,
          label: (data as Record<string, any>).device_label,
          // supabase embeds the related row as an object or array
          venue_name:
            (data as Record<string, any>).venues?.name ??
            (Array.isArray((data as Record<string, any>).venues)
              ? (data as Record<string, any>).venues?.[0]?.name
              : null),
        })
      })
    return () => {
      cancelled = true
    }
  }, [session?.user?.id])

  // Expire stale PIN verification automatically.
  useEffect(() => {
    if (!verifiedStaff) return
    const ms = PIN_TTL_MS - (Date.now() - verifiedStaff.verifiedAtMs)
    if (ms <= 0) {
      setVerifiedStaff(null)
      return
    }
    const t = setTimeout(() => setVerifiedStaff(null), ms)
    return () => clearTimeout(t)
  }, [verifiedStaff])

  const value = useMemo<AuthValue>(
    () => ({
      session,
      loading,
      device,
      deviceError,
      venueId: device?.venue_id ?? null,
      venueLabel: device?.venue_name || device?.label || 'Play Diaries',
      verifiedStaff,
      setVerifiedStaff,
      async signIn(email, password) {
        const { error } = await supabase.auth.signInWithPassword({
          email: email.trim(),
          password,
        })
        if (error) throw error
      },
      async signOut() {
        await supabase.auth.signOut()
        setVerifiedStaff(null)
        setDevice(null)
      },
    }),
    [session, loading, device, deviceError, verifiedStaff],
  )

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useAuth(): AuthValue {
  const v = useContext(Ctx)
  if (!v) throw new Error('useAuth must be used within AuthProvider')
  return v
}

/** A fresh (<30s) verified-staff identity, or null. */
export function freshStaff(s: VerifiedStaff | null): VerifiedStaff | null {
  if (!s) return null
  return Date.now() - s.verifiedAtMs < PIN_TTL_MS ? s : null
}
