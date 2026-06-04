import {
  createContext,
  useCallback,
  useContext,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { rpc } from '../lib/supabase'

/** The staff account operating this device. Resolved automatically from the
 *  venue roster (no picker, no PIN) and attributed to every action purely so
 *  the backend has a staff id for its audit trail. Venues have one staff row,
 *  so there's nothing to choose. */
export interface Actor {
  staffId: string
  staffName: string
  role: string
}

interface RosterRow {
  staff_id: string
  staff_name: string
  role: string
}

const STORAGE_KEY = 'pd-staff-actor'

interface ActorValue {
  current: Actor | null
  /** Resolve the staff member to attribute actions to. Loads the venue roster
   *  on first use and caches it; resolves null only if the venue has no staff. */
  requireActor: () => Promise<Actor | null>
  clearActor: () => void
}

const Ctx = createContext<ActorValue>({
  current: null,
  requireActor: async () => null,
  clearActor: () => {},
})
export const useActor = () => useContext(Ctx)

export function ActorProvider({ children }: { children: ReactNode }) {
  const [current, setCurrent] = useState<Actor | null>(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY)
      return raw ? (JSON.parse(raw) as Actor) : null
    } catch {
      return null
    }
  })
  // De-dupe concurrent first-use lookups so we hit staff_roster only once.
  const inflight = useRef<Promise<Actor | null> | null>(null)

  function persist(a: Actor | null) {
    setCurrent(a)
    try {
      if (a) localStorage.setItem(STORAGE_KEY, JSON.stringify(a))
      else localStorage.removeItem(STORAGE_KEY)
    } catch {
      /* ignore */
    }
  }

  const requireActor = useCallback<ActorValue['requireActor']>(() => {
    if (current) return Promise.resolve(current)
    if (inflight.current) return inflight.current
    const p = rpc<RosterRow[]>('staff_roster')
      .then((rows) => {
        const first = rows?.[0]
        if (!first) return null
        const a: Actor = {
          staffId: first.staff_id,
          staffName: first.staff_name,
          role: first.role,
        }
        persist(a)
        return a
      })
      .catch(() => null)
      .finally(() => {
        inflight.current = null
      })
    inflight.current = p
    return p
  }, [current])

  return (
    <Ctx.Provider
      value={{ current, requireActor, clearActor: () => persist(null) }}
    >
      {children}
    </Ctx.Provider>
  )
}
