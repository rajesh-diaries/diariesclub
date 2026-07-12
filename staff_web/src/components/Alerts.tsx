import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { useAuth } from '../state/auth'
import { KitchenIcon, SessionsIcon, CloseIcon } from './icons'

/** In-app real-time alerting for the counter tablet. Subscribes to new café
 *  orders and new play-session check-ins for this venue and, on each one:
 *   • plays a distinct chime (unless muted),
 *   • drops a tap-to-open banner,
 *   • bumps an "unseen" count that shows as a badge on the Kitchen / Live nav
 *     icons and clears when staff open that tab.
 *  No backend needed — sessions & orders are already realtime-published. */

type AlertKind = 'order' | 'session'
interface Banner {
  id: number
  kind: AlertKind
  text: string
}

interface AlertsValue {
  unseenOrders: number
  unseenSessions: number
  muted: boolean
  toggleMute: () => void
  markSeen: (kind: AlertKind) => void
}

const Ctx = createContext<AlertsValue>({
  unseenOrders: 0,
  unseenSessions: 0,
  muted: false,
  toggleMute: () => {},
  markSeen: () => {},
})
export const useAlerts = () => useContext(Ctx)

const MUTE_KEY = 'pd-staff-muted'

export function AlertsProvider({ children }: { children: ReactNode }) {
  const { venueId } = useAuth()
  const loc = useLocation()
  const qc = useQueryClient()

  const [unseenOrders, setUnseenOrders] = useState(0)
  const [unseenSessions, setUnseenSessions] = useState(0)
  const [banners, setBanners] = useState<Banner[]>([])
  const [muted, setMuted] = useState(() => {
    try {
      return localStorage.getItem(MUTE_KEY) === '1'
    } catch {
      return false
    }
  })

  const audioRef = useRef<AudioContext | null>(null)
  const mutedRef = useRef(muted)
  useEffect(() => {
    mutedRef.current = muted
  }, [muted])
  const bannerId = useRef(0)

  // Browsers block audio until the user interacts. Create/resume the audio
  // context on the first pointer gesture so the first alert can chime.
  useEffect(() => {
    const prime = () => {
      if (!audioRef.current) {
        const AC =
          window.AudioContext ||
          (window as unknown as { webkitAudioContext?: typeof AudioContext })
            .webkitAudioContext
        if (AC) audioRef.current = new AC()
      }
      void audioRef.current?.resume?.()
    }
    window.addEventListener('pointerdown', prime)
    return () => window.removeEventListener('pointerdown', prime)
  }, [])

  const chime = useCallback((kind: AlertKind) => {
    if (mutedRef.current) return
    const ctx = audioRef.current
    if (!ctx) return
    void ctx.resume?.()
    const now = ctx.currentTime
    // Two-note motifs: order = bright A5→D6, check-in = warm E5→B5.
    const notes = kind === 'order' ? [880, 1174.7] : [659.3, 987.8]
    notes.forEach((f, i) => {
      const osc = ctx.createOscillator()
      const gain = ctx.createGain()
      osc.type = 'sine'
      osc.frequency.value = f
      const t = now + i * 0.14
      gain.gain.setValueAtTime(0.0001, t)
      gain.gain.exponentialRampToValueAtTime(0.3, t + 0.02)
      gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.22)
      osc.connect(gain)
      gain.connect(ctx.destination)
      osc.start(t)
      osc.stop(t + 0.26)
    })
  }, [])

  const pushBanner = useCallback((kind: AlertKind, text: string) => {
    const id = ++bannerId.current
    setBanners((b) => [...b, { id, kind, text }].slice(-3))
    setTimeout(() => setBanners((b) => b.filter((x) => x.id !== id)), 7000)
  }, [])

  const dismiss = useCallback(
    (id: number) => setBanners((b) => b.filter((x) => x.id !== id)),
    [],
  )

  // Realtime: new orders + new check-ins at this venue.
  useEffect(() => {
    if (!venueId) return
    const ch = supabase
      .channel(`alerts-${venueId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'orders',
          filter: `venue_id=eq.${venueId}`,
        },
        () => {
          setUnseenOrders((n) => n + 1)
          chime('order')
          pushBanner('order', 'New café order')
          void qc.invalidateQueries({ queryKey: ['pending-payments'] })
        },
      )
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'sessions',
          filter: `venue_id=eq.${venueId}`,
        },
        () => {
          setUnseenSessions((n) => n + 1)
          chime('session')
          pushBanner('session', 'New check-in')
          void qc.invalidateQueries({ queryKey: ['active-sessions'] })
        },
      )
      .subscribe()
    return () => {
      void supabase.removeChannel(ch)
    }
  }, [venueId, chime, pushBanner, qc])

  // Opening a tab acknowledges its alerts. Functional bail (return same value
  // when already 0) so React skips a redundant render.
  useEffect(() => {
    if (loc.pathname === '/kitchen') setUnseenOrders((n) => (n ? 0 : n))
    else if (loc.pathname === '/live') setUnseenSessions((n) => (n ? 0 : n))
  }, [loc.pathname])

  const markSeen = useCallback((kind: AlertKind) => {
    if (kind === 'order') setUnseenOrders(0)
    else setUnseenSessions(0)
  }, [])

  const toggleMute = useCallback(() => {
    setMuted((m) => {
      const next = !m
      try {
        localStorage.setItem(MUTE_KEY, next ? '1' : '0')
      } catch {
        /* ignore */
      }
      return next
    })
  }, [])

  return (
    <Ctx.Provider
      value={{ unseenOrders, unseenSessions, muted, toggleMute, markSeen }}
    >
      {children}
      <AlertBanners banners={banners} onDismiss={dismiss} />
    </Ctx.Provider>
  )
}

function AlertBanners({
  banners,
  onDismiss,
}: {
  banners: Banner[]
  onDismiss: (id: number) => void
}) {
  const nav = useNavigate()
  if (banners.length === 0) return null
  return (
    <div className="pointer-events-none fixed inset-x-0 top-0 z-50 flex flex-col items-center gap-2 px-4 pt-[max(env(safe-area-inset-top),0.75rem)]">
      {banners.map((b) => (
        <div
          key={b.id}
          role="button"
          tabIndex={0}
          onClick={() => {
            nav(b.kind === 'order' ? '/kitchen' : '/live')
            onDismiss(b.id)
          }}
          className={`animate-rise pointer-events-auto flex w-full max-w-sm items-center gap-3 rounded-2xl border px-4 py-3 text-left shadow-2xl backdrop-blur-md ${
            b.kind === 'order'
              ? 'border-primary/40 bg-primary/20'
              : 'border-active/40 bg-active/20'
          }`}
        >
          <span className={b.kind === 'order' ? 'text-primary' : 'text-active'}>
            {b.kind === 'order' ? (
              <KitchenIcon size={22} />
            ) : (
              <SessionsIcon size={22} />
            )}
          </span>
          <span className="flex-1">
            <span className="block text-sm font-black">{b.text}</span>
            <span className="block text-xs text-dim">Tap to open</span>
          </span>
          <button
            aria-label="Dismiss"
            onClick={(e) => {
              e.stopPropagation()
              onDismiss(b.id)
            }}
            className="rounded-full p-1 text-faint active:bg-surface-2"
          >
            <CloseIcon size={18} />
          </button>
        </div>
      ))}
    </div>
  )
}
