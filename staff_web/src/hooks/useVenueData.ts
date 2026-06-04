import { useQuery } from '@tanstack/react-query'
import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../state/auth'

export interface SessionRow {
  id: string
  child_id: string | null
  family_id: string
  venue_id: string
  status: 'active' | 'grace' | string
  started_at: string
  expires_at: string
  completed_at: string | null
  duration_minutes: number
  payment_method: string
  healthy_bite_earned: boolean
  healthy_bite_distributed: boolean
  healthy_bite_claimed_at: string | null
  children: { name: string } | { name: string }[] | null
  families: { name: string } | { name: string }[] | null
}

export interface OrderItem {
  name_snapshot: string
  quantity: number
  brand: string | null
  notes: string | null
}
export interface OrderRow {
  id: string
  venue_id: string
  status: 'pending' | 'preparing' | 'ready' | string
  created_at: string
  total_paise: number | null
  payment_method: string | null
  fulfillment_mode?: string | null
  family_id?: string | null
  families?: { name: string } | { name: string }[] | null
  order_items?: OrderItem[]
}

const SESSION_COLS =
  'id, child_id, family_id, venue_id, status, started_at, expires_at, ' +
  'completed_at, duration_minutes, payment_method, healthy_bite_earned, ' +
  'healthy_bite_distributed, healthy_bite_claimed_at, children(name), families(name)'

/** Active + grace sessions at this venue. Polled every 15s (embedded
 *  selects aren't supported by .stream()). */
export function useActiveSessions() {
  const { venueId } = useAuth()
  return useQuery({
    queryKey: ['active-sessions', venueId],
    enabled: !!venueId,
    refetchInterval: 15_000,
    queryFn: async (): Promise<SessionRow[]> => {
      const { data, error } = await supabase
        .from('sessions')
        .select(SESSION_COLS)
        .eq('venue_id', venueId!)
        .in('status', ['active', 'grace'])
        .order('expires_at', { ascending: true })
      if (error) throw error
      return (data ?? []) as unknown as SessionRow[]
    },
  })
}

/** In-flight orders (pending/preparing/ready) at this venue, kept live via
 *  Realtime with an initial fetch for first paint. */
export function useOrders() {
  const { venueId } = useAuth()
  const [orders, setOrders] = useState<OrderRow[] | null>(null)

  useEffect(() => {
    if (!venueId) return
    let active = true

    const load = async () => {
      const { data } = await supabase
        .from('orders')
        .select(
          'id, venue_id, family_id, status, created_at, total_paise, ' +
            'payment_method, fulfillment_mode, families(name), ' +
            'order_items(name_snapshot, quantity, brand, notes)',
        )
        .eq('venue_id', venueId)
        .in('status', ['pending', 'preparing', 'ready'])
        .order('created_at', { ascending: true })
      if (active) setOrders((data ?? []) as unknown as OrderRow[])
    }
    load()

    const ch = supabase
      .channel(`orders-${venueId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'orders', filter: `venue_id=eq.${venueId}` },
        () => load(),
      )
      .subscribe()

    return () => {
      active = false
      supabase.removeChannel(ch)
    }
  }, [venueId])

  return orders
}

export interface PendingPayment {
  refType: 'session' | 'order'
  id: string
  name: string
  label: string
  amountPaise: number
  createdAt: string
}

/** Uncollected "pay at counter" (cash) sessions + café orders in the last
 *  24h. Staff need the amount here so they know what to collect — this is
 *  the one place money is shown, by design. */
export function usePendingCounterPayments() {
  const { venueId } = useAuth()
  return useQuery({
    queryKey: ['pending-payments', venueId],
    enabled: !!venueId,
    refetchInterval: 15_000,
    queryFn: async (): Promise<PendingPayment[]> => {
      const sinceIso = new Date(Date.now() - 24 * 3600_000).toISOString()
      const [sess, ord] = await Promise.all([
        supabase
          .from('sessions')
          .select(
            'id, amount_paise, duration_minutes, created_at, is_guest, guest_phone, children(name), families(name)',
          )
          .eq('venue_id', venueId!)
          .eq('payment_method', 'cash')
          .is('counter_paid_at', null)
          .neq('status', 'cancelled')
          .gte('created_at', sinceIso),
        supabase
          .from('orders')
          .select('id, total_paise, created_at, families(name)')
          .eq('venue_id', venueId!)
          .eq('payment_method', 'cash')
          .is('counter_paid_at', null)
          .neq('status', 'cancelled')
          .gte('created_at', sinceIso),
      ])
      const out: PendingPayment[] = []
      for (const s of (sess.data ?? []) as any[]) {
        const guestName = s.is_guest
          ? `Walk-in${s.guest_phone ? ` · ${s.guest_phone}` : ''}`
          : 'Guest'
        out.push({
          refType: 'session',
          id: s.id,
          name: embedName(s.children) || embedName(s.families) || guestName,
          label: `${s.duration_minutes}-min play`,
          amountPaise: s.amount_paise ?? 0,
          createdAt: s.created_at,
        })
      }
      for (const o of (ord.data ?? []) as any[]) {
        out.push({
          refType: 'order',
          id: o.id,
          name: embedName(o.families) || 'Walk-in',
          label: 'Café order',
          amountPaise: o.total_paise ?? 0,
          createdAt: o.created_at,
        })
      }
      return out.sort(
        (a, b) =>
          new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
      )
    },
  })
}

export interface BiteRow {
  id: string
  child_id: string | null
  family_id: string
  status: string
  started_at: string
  completed_at: string | null
  healthy_bite_distributed?: boolean
  healthy_bite_declined_at?: string | null
  healthy_bite_earned?: boolean
  children: { name: string } | { name: string }[] | null
}

/** Where a child's complimentary snack stands right now. */
export type BiteStatus = 'pending' | 'playing' | 'given' | 'skipped'

/** Derive the snack status from the raw session flags. */
export function biteStatus(b: BiteRow): BiteStatus {
  if (b.healthy_bite_distributed) return 'given'
  if (b.healthy_bite_declined_at) return 'skipped'
  if (b.status === 'active' || b.status === 'grace') return 'playing'
  return 'pending'
}

/** Sessions in the last 4h that still need a yes/no on the complimentary
 *  healthy snack (not yet distributed, not yet declined). */
export function usePendingHealthyBites() {
  const { venueId } = useAuth()
  return useQuery({
    queryKey: ['pending-bites', venueId],
    enabled: !!venueId,
    refetchInterval: 20_000,
    queryFn: async (): Promise<BiteRow[]> => {
      const sinceIso = new Date(Date.now() - 4 * 3600_000).toISOString()
      const { data, error } = await supabase
        .from('sessions')
        .select(
          'id, child_id, family_id, status, started_at, completed_at, children(name)',
        )
        .eq('venue_id', venueId!)
        .eq('healthy_bite_distributed', false)
        .eq('is_guest', false) // guests have no child profile → no hero card
        .is('healthy_bite_declined_at', null)
        .in('status', ['active', 'grace', 'completed', 'auto_closed'])
        .gte('started_at', sinceIso)
        .order('started_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as unknown as BiteRow[]
    },
  })
}

/** Every child with a complimentary snack to track today — to-give, already
 *  given, skipped, or still playing — so staff keep a record after handing
 *  out, not just a list that empties to nothing. Sessions that never earned a
 *  snack are left out (there's nothing to manage). */
export function useHealthyBites() {
  const { venueId } = useAuth()
  return useQuery({
    queryKey: ['healthy-bites', venueId],
    enabled: !!venueId,
    refetchInterval: 20_000,
    queryFn: async (): Promise<BiteRow[]> => {
      const sinceIso = new Date(Date.now() - 12 * 3600_000).toISOString()
      const { data, error } = await supabase
        .from('sessions')
        .select(
          'id, child_id, family_id, status, started_at, completed_at, ' +
            'healthy_bite_distributed, healthy_bite_declined_at, healthy_bite_earned, children(name)',
        )
        .eq('venue_id', venueId!)
        .eq('is_guest', false) // guests have no child profile → no hero card
        .or(
          'healthy_bite_earned.eq.true,healthy_bite_distributed.eq.true,healthy_bite_declined_at.not.is.null',
        )
        .in('status', ['active', 'grace', 'completed', 'auto_closed'])
        .gte('started_at', sinceIso)
        .order('started_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as unknown as BiteRow[]
    },
  })
}

/** Today's at-a-glance counts for the home stat bar. Staff never see money,
 *  so this deliberately fetches no amounts — just session + kid counts. */
export function useTodayStats() {
  const { venueId } = useAuth()
  return useQuery({
    queryKey: ['today-stats', venueId],
    enabled: !!venueId,
    refetchInterval: 30_000,
    queryFn: async () => {
      const sinceIso = new Date(Date.now() - 24 * 3600_000).toISOString()
      const { data } = await supabase
        .from('sessions')
        .select('id, child_id, status')
        .eq('venue_id', venueId!)
        .gte('created_at', sinceIso)
      const rows = data ?? []
      const served = rows.filter((r: any) =>
        ['active', 'grace', 'completed', 'auto_closed'].includes(r.status),
      )
      const kids = new Set(served.map((r: any) => r.child_id).filter(Boolean))
      return { sessionsToday: rows.length, kidsToday: kids.size }
    },
  })
}

/** Pull a related name out of a Supabase embed (object or array form). */
export function embedName(
  rel: { name: string } | { name: string }[] | null | undefined,
): string {
  if (!rel) return ''
  return Array.isArray(rel) ? (rel[0]?.name ?? '') : rel.name
}
