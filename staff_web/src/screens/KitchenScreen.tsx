import { useState } from 'react'
import { Header, Page } from '../components/Shell'
import { Button, Card, Empty, Pill, useToast } from '../components/ui'
import { KitchenIcon } from '../components/icons'
import { rpc } from '../lib/supabase'
import { minutesSince } from '../lib/format'
import { useOrders, embedName, type OrderRow } from '../hooks/useVenueData'

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
          list.map((o) => <OrderCard key={o.id} order={o} tab={tab} />)
        )}
      </Page>
    </>
  )
}

function OrderCard({ order, tab }: { order: OrderRow; tab: Tab }) {
  const toast = useToast()
  const [busy, setBusy] = useState(false)
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
      <div className="flex items-center justify-between">
        <p className="truncate text-base font-extrabold">{customer}</p>
        <Pill tone={urgent && tab !== 'ready' ? 'danger' : 'dim'}>
          {age === 0 ? 'just now' : `${age}m`}
        </Pill>
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
    </Card>
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
