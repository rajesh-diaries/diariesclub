import { useState } from 'react'
import { Header, Page } from '../components/Shell'
import { Button, Card, Empty, Pill, useToast } from '../components/ui'
import { Sheet } from '../components/Sheet'
import { useActor } from '../components/Actor'
import { KitchenIcon, InfoIcon } from '../components/icons'
import { rpc } from '../lib/supabase'
import { minutesSince, rupees } from '../lib/format'
import {
  useOrders,
  useFitLabels,
  embedName,
  type OrderRow,
} from '../hooks/useVenueData'
import { CustomerSheet } from '../components/CustomerSheet'

type Tab = 'pending' | 'preparing' | 'ready'
const TABS: { key: Tab; label: string }[] = [
  { key: 'pending', label: 'New' },
  { key: 'preparing', label: 'Cooking' },
  { key: 'ready', label: 'Ready' },
]
const NEXT: Record<Tab, { status: string; label: string }> = {
  pending: { status: 'preparing', label: 'Start cooking' },
  preparing: { status: 'ready', label: 'Mark ready' },
  ready: { status: 'served', label: 'Mark picked up' },
}

export function KitchenScreen() {
  const orders = useOrders()
  const [tab, setTab] = useState<Tab>('pending')
  const [profileId, setProfileId] = useState<string | null>(null)

  const counts: Record<Tab, number> = {
    pending: orders?.filter((o) => o.status === 'pending').length ?? 0,
    preparing: orders?.filter((o) => o.status === 'preparing').length ?? 0,
    ready: orders?.filter((o) => o.status === 'ready').length ?? 0,
  }
  const list = (orders ?? [])
    .filter((o) => o.status === tab)
    .sort(
      (a, b) =>
        new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
    )

  return (
    <>
      <Header subtitle="Kitchen" title="Orders" />

      {/* Segmented tabs */}
      <div className="sticky top-[3.5rem] z-10 mx-auto w-full max-w-md bg-ink/70 px-4 pb-2 backdrop-blur-md">
        <div className="flex gap-1 rounded-2xl border border-line bg-surface p-1">
          {TABS.map((t) => (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={`relative flex-1 rounded-xl py-2.5 text-sm font-bold transition-colors ${
                tab === t.key ? 'bg-primary text-white' : 'text-dim'
              }`}
            >
              {t.label}
              {counts[t.key] > 0 && (
                <span
                  className={`ml-1.5 rounded-full px-1.5 text-xs ${
                    tab === t.key ? 'bg-white/25' : 'bg-surface-2 text-faint'
                  }`}
                >
                  {counts[t.key]}
                </span>
              )}
            </button>
          ))}
        </div>
      </div>

      <Page>
        {orders === null ? (
          <SkeletonList />
        ) : list.length === 0 ? (
          <Empty
            icon={<KitchenIcon size={48} />}
            title={
              tab === 'ready'
                ? 'Nothing waiting for pickup'
                : tab === 'preparing'
                  ? 'Nothing cooking'
                  : 'No new orders'
            }
            hint="Orders placed in the customer app land here in real time."
          />
        ) : (
          list.map((o) => (
            <OrderCard
              key={o.id}
              order={o}
              tab={tab}
              onInfo={o.family_id ? () => setProfileId(o.family_id!) : undefined}
            />
          ))
        )}
      </Page>
      <CustomerSheet familyId={profileId} onClose={() => setProfileId(null)} />
    </>
  )
}

/** Turn a stored FIT selections map ({category: option_id}, or arrays for
 *  multi-select) into an ordered list of option names for the kitchen. */
function resolveFitBuild(
  selections: Record<string, unknown> | null | undefined,
  labels: Map<string, { name: string; order: number }> | undefined,
): string[] {
  if (!selections || !labels) return []
  const ids: string[] = []
  for (const v of Object.values(selections)) {
    if (typeof v === 'string') ids.push(v)
    else if (Array.isArray(v))
      v.forEach((x) => typeof x === 'string' && ids.push(x))
  }
  return ids
    .map((id) => labels.get(id))
    .filter((x): x is { name: string; order: number } => !!x)
    .sort((a, b) => a.order - b.order)
    .map((x) => x.name)
}

function OrderCard({
  order,
  tab,
  onInfo,
}: {
  order: OrderRow
  tab: Tab
  onInfo?: () => void
}) {
  const toast = useToast()
  const [busy, setBusy] = useState(false)
  const [refundOpen, setRefundOpen] = useState(false)
  const fitLabels = useFitLabels().data
  const age = minutesSince(order.created_at)
  const customer = embedName(order.families) || 'Walk-in'
  const next = NEXT[tab]
  const urgent = age >= 15

  async function advance() {
    setBusy(true)
    try {
      await rpc('staff_order_advance_status', {
        p_order_id: order.id,
        p_new_status: next.status,
      })
      toast(
        next.status === 'served' ? 'Order picked up ✓' : `Moved to ${next.status}`,
        'ok',
      )
      // Realtime refreshes the list; no manual refetch needed.
    } catch {
      toast("Couldn't update order.", 'err')
      setBusy(false)
    }
  }

  return (
    <Card
      className={`animate-rise mb-3 p-4 ${
        urgent && tab !== 'ready' ? 'border-danger/40' : ''
      }`}
    >
      <div className="flex items-center justify-between gap-2">
        {onInfo ? (
          <button
            onClick={onInfo}
            className="min-w-0 truncate text-left text-base font-extrabold active:opacity-70"
          >
            {customer}
          </button>
        ) : (
          <p className="min-w-0 truncate text-base font-extrabold">{customer}</p>
        )}
        <div className="flex shrink-0 items-center gap-2">
          <Pill tone={urgent && tab !== 'ready' ? 'danger' : 'dim'}>
            {age === 0 ? 'just now' : `${age}m`}
          </Pill>
          {onInfo && (
            <button
              onClick={onInfo}
              aria-label="Customer profile"
              className="rounded-full border border-line bg-surface-2 p-1.5 text-dim active:bg-line"
            >
              <InfoIcon size={16} />
            </button>
          )}
        </div>
      </div>

      <ul className="mt-3 space-y-1.5">
        {(order.order_items ?? []).map((it, i) => (
          <li key={i} className="flex items-start gap-2 text-[0.95rem]">
            <span className="font-black text-primary">{it.quantity}×</span>
            <span className="flex-1">
              <span className="font-semibold">{it.name_snapshot}</span>
              {it.brand && (
                <span className="ml-1.5 text-xs uppercase tracking-wide text-faint">
                  {it.brand}
                </span>
              )}
              {(() => {
                const build = resolveFitBuild(it.selections_jsonb, fitLabels)
                return build.length > 0 ? (
                  <span className="mt-0.5 block text-sm font-medium text-dim">
                    {build.join(' · ')}
                  </span>
                ) : null
              })()}
              {it.notes && (
                <span className="block text-sm italic text-grace">
                  “{it.notes}”
                </span>
              )}
            </span>
          </li>
        ))}
        {(order.order_items ?? []).length === 0 && (
          <li className="text-sm text-faint">No item details</li>
        )}
      </ul>

      <Button
        onClick={advance}
        loading={busy}
        variant={tab === 'ready' ? 'gold' : 'primary'}
        className="mt-4 w-full py-3"
      >
        {next.label}
      </Button>

      {order.family_id && (order.total_paise ?? 0) > 0 && (
        <button
          onClick={() => setRefundOpen(true)}
          className="mx-auto mt-3 block text-sm font-semibold text-danger active:opacity-70"
        >
          Cancel · refund to wallet
        </button>
      )}

      <RefundSheet
        order={order}
        open={refundOpen}
        onClose={() => setRefundOpen(false)}
      />
    </Card>
  )
}

/** Refund a cancelled / un-served order back to the customer's wallet. Uses
 *  refund_issue (staff-attributed, capped at what was paid, audited). */
function RefundSheet({
  order,
  open,
  onClose,
}: {
  order: OrderRow
  open: boolean
  onClose: () => void
}) {
  const toast = useToast()
  const requireActor = useActor().requireActor
  const total = order.total_paise ?? 0
  const [amountPaise, setAmountPaise] = useState<number>(total)
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)

  async function refund() {
    if (busy) return
    if (!order.family_id) {
      toast('Walk-in / guest order — no wallet. Return cash at the counter.', 'err')
      return
    }
    if (amountPaise <= 0 || amountPaise > total) {
      toast('Enter an amount up to what was paid.', 'err')
      return
    }
    const staff = await requireActor()
    if (!staff) return
    setBusy(true)
    try {
      await rpc('refund_issue', {
        p_family_id: order.family_id,
        p_reference_id: order.id,
        p_reference_type: 'order',
        p_amount_paise: amountPaise,
        p_destination: 'wallet',
        p_reason: reason.trim() || 'Order cancelled — not served',
        p_staff_pin_id: staff.staffId,
        p_venue_id: order.venue_id,
        p_idempotency_key: `refund:${order.id}:${amountPaise}`,
      })
      toast(`Refunded ${rupees(amountPaise)} to wallet`, 'ok')
      onClose()
    } catch (e: any) {
      const msg = String(e?.message ?? '')
      toast(
        msg.includes('refund_exceeds_charge')
          ? 'That is more than what was paid.'
          : "Couldn't process refund.",
        'err',
      )
    } finally {
      setBusy(false)
    }
  }

  return (
    <Sheet open={open} onClose={onClose} title="Refund to wallet">
      <p className="mb-3 text-sm text-dim">
        Credit the customer’s wallet for a cancelled / un-served order. Paid:{' '}
        <span className="font-semibold text-text">{rupees(total)}</span>
        {order.payment_method ? ` · ${order.payment_method}` : ''}
      </p>
      <label className="mb-1 block text-xs font-bold text-faint">Amount (₹)</label>
      <input
        type="number"
        inputMode="decimal"
        value={amountPaise / 100}
        onChange={(e) =>
          setAmountPaise(Math.round((parseFloat(e.target.value) || 0) * 100))
        }
        className="mb-3 w-full rounded-2xl border border-line bg-surface-2 px-4 py-3 text-lg font-bold focus:border-primary focus:outline-none"
      />
      <textarea
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        placeholder="Reason — e.g. customer cancelled, food not served"
        rows={2}
        className="mb-4 w-full resize-none rounded-2xl border border-line bg-surface-2 px-4 py-3 text-[1rem] placeholder:text-faint focus:border-primary focus:outline-none"
      />
      <Button variant="primary" loading={busy} onClick={refund} className="w-full">
        Refund {rupees(amountPaise)} to wallet
      </Button>
    </Sheet>
  )
}

function SkeletonList() {
  return (
    <div className="space-y-3">
      {[0, 1].map((i) => (
        <div
          key={i}
          className="h-44 animate-pulse rounded-[1.25rem] border border-line bg-surface/60"
        />
      ))}
    </div>
  )
}
