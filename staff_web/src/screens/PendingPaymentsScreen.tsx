import { useState } from 'react'
import { Header, Page } from '../components/Shell'
import { Button, Card, Empty, Pill, useToast } from '../components/ui'
import { useActor } from '../components/Actor'
import { CashIcon, RefreshIcon, CheckIcon, SessionsIcon } from '../components/icons'
import { rpc } from '../lib/supabase'
import { rupees, relativeFrom } from '../lib/format'
import {
  usePendingCounterPayments,
  type PendingPayment,
} from '../hooks/useVenueData'

/** "Pay at counter" collections. The deliberate exception to the no-money
 *  rule: staff must see the amount to collect, then tap Received. */
export function PendingPaymentsScreen() {
  const pending = usePendingCounterPayments()
  const rows = pending.data ?? []
  const total = rows.reduce((s, r) => s + r.amountPaise, 0)

  return (
    <>
      <Header
        subtitle="Pay at counter"
        title="Collect payment"
        right={
          <button
            onClick={() => pending.refetch()}
            className="rounded-full border border-line bg-surface p-2.5 text-dim active:bg-surface-2"
            aria-label="Refresh"
          >
            <RefreshIcon size={20} />
          </button>
        }
      />
      <Page>
        {pending.isLoading ? (
          <Skeleton />
        ) : rows.length === 0 ? (
          <Empty
            icon={<CashIcon size={48} />}
            title="Nothing to collect"
            hint="When a customer chooses ‘pay at counter’, it shows up here until you mark it received."
          />
        ) : (
          <>
            <Card className="mb-4 flex items-center justify-between p-4">
              <div>
                <p className="text-xs font-bold uppercase tracking-wider text-faint">
                  To collect
                </p>
                <p className="text-3xl font-black text-gold">{rupees(total)}</p>
              </div>
              <Pill tone="gold">
                {rows.length} {rows.length === 1 ? 'payment' : 'payments'}
              </Pill>
            </Card>
            {rows.map((p) => (
              <PaymentCard key={`${p.refType}-${p.id}`} p={p} onDone={() => pending.refetch()} />
            ))}
          </>
        )}
      </Page>
    </>
  )
}

function PaymentCard({ p, onDone }: { p: PendingPayment; onDone: () => void }) {
  const toast = useToast()
  const requireActor = useActor().requireActor
  const [busy, setBusy] = useState(false)

  async function received() {
    const staff = await requireActor()
    if (!staff) return
    setBusy(true)
    try {
      await rpc('mark_counter_payment', {
        p_ref_type: p.refType,
        p_ref_id: p.id,
        p_staff_pin_id: staff.staffId,
      })
      toast(`${rupees(p.amountPaise)} collected from ${p.name} ✓`, 'ok')
      onDone()
    } catch (err: any) {
      const msg = String(err?.message ?? '')
      toast(
        msg.includes('already_collected')
          ? 'Already marked collected.'
          : "Couldn't update.",
        'err',
      )
      setBusy(false)
    }
  }

  return (
    <Card className="animate-rise mb-3 p-4">
      <div className="flex items-center gap-3">
        <span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-surface-2 text-gold">
          {p.refType === 'session' ? <SessionsIcon size={22} /> : <CashIcon size={22} />}
        </span>
        <div className="min-w-0 flex-1">
          <p className="truncate text-lg font-extrabold">{p.name}</p>
          <p className="text-sm text-dim">
            {p.label} · {relativeFrom(p.createdAt)}
          </p>
        </div>
        <p className="text-xl font-black text-gold">{rupees(p.amountPaise)}</p>
      </div>
      <Button
        variant="gold"
        loading={busy}
        onClick={received}
        icon={!busy && <CheckIcon size={18} />}
        className="mt-4 w-full py-3"
      >
        Mark received
      </Button>
    </Card>
  )
}

function Skeleton() {
  return (
    <div className="space-y-3">
      {[0, 1, 2].map((i) => (
        <div
          key={i}
          className="h-28 animate-pulse rounded-[1.25rem] border border-line bg-surface/60"
        />
      ))}
    </div>
  )
}
