import { useQuery } from '@tanstack/react-query'
import { rpc } from '../lib/supabase'

/** One most-ordered café item for this family (name_snapshot + total qty). */
export interface TopFoodItem {
  name: string
  count: number
}

/** Full shape of the `staff_customer_summary(p_family_id)` RPC (jsonb).
 *  Every field the backend already computes — the app historically used
 *  only visit_count + last_visit_at. */
export interface CustomerSummary {
  family_id: string
  guardian_name: string | null
  guardian_phone: string | null
  is_walk_in: boolean
  child_names: string[]
  visit_count: number
  last_visit_at: string | null
  avg_session_length_minutes: number
  lifetime_spend_paise: number
  session_spend_paise: number
  food_spend_paise: number
  workshop_spend_paise: number
  birthday_spend_paise: number
  top_food_items: TopFoodItem[]
  wallet_balance_paise: number
  wallet_held_paise: number
  coins_balance: number
  total_xp: number
  member_tier: string | null
}

/** Fetch (and cache) a family's staff-facing summary. Keyed on familyId so
 *  every screen that shows a customer shares one cached result — tap it on
 *  the floor, at the counter, or in the kitchen and it's the same fetch. */
export function useCustomerSummary(familyId: string | null | undefined) {
  return useQuery({
    queryKey: ['customer-summary', familyId],
    enabled: !!familyId,
    staleTime: 30_000,
    queryFn: () =>
      rpc<CustomerSummary>('staff_customer_summary', { p_family_id: familyId }),
  })
}

/** A recent order/session and how much of it is still refundable. */
export interface RefundableCharge {
  type: 'order' | 'session'
  id: string
  label: string
  created_at: string
  paid_paise: number
  payment_method: string | null
  refunded_paise: number
}

/** A family's recent refundable charges (last 7 days), so staff can reverse
 *  any of them from the customer profile — not just a live kitchen ticket. */
export function useCustomerRefundables(familyId: string | null | undefined) {
  return useQuery({
    queryKey: ['customer-refundables', familyId],
    enabled: !!familyId,
    staleTime: 10_000,
    queryFn: () =>
      rpc<RefundableCharge[]>('staff_customer_refundables', {
        p_family_id: familyId,
      }),
  })
}

export type SignalTone = 'gold' | 'active' | 'primary' | 'dim'
export interface Regularity {
  label: string
  tone: SignalTone
  /** 0–3 filled strength dots. */
  dots: number
}

/** Derive a hospitality signal from visit history + lifetime spend, so staff
 *  instantly know whether they're greeting a VIP, a regular, or a newcomer. */
export function regularity(s: CustomerSummary): Regularity {
  const visits = s.visit_count ?? 0
  const spend = s.lifetime_spend_paise ?? 0
  if (visits >= 10 || spend >= 1_000_000)
    return { label: 'VIP regular', tone: 'gold', dots: 3 }
  if (visits >= 3) return { label: 'Regular', tone: 'active', dots: 2 }
  if (visits >= 1) return { label: 'Returning', tone: 'primary', dots: 1 }
  return { label: 'First visit', tone: 'dim', dots: 0 }
}

/** "1h 20m" / "45m" / "—" from a whole-minutes count. */
export function playLength(mins: number | null | undefined): string {
  const m = mins ?? 0
  if (m <= 0) return '—'
  const h = Math.floor(m / 60)
  const mm = m % 60
  if (!h) return `${mm}m`
  return mm ? `${h}h ${mm}m` : `${h}h`
}

/** Title-case a hero stage slug ("adventurer" → "Adventurer"). */
export function tierLabel(tier: string | null | undefined): string | null {
  if (!tier) return null
  return tier.charAt(0).toUpperCase() + tier.slice(1)
}
