import { useState, type ReactNode } from 'react'
import { Sheet } from './Sheet'
import { Button, Pill, Spinner, Empty, useToast } from './ui'
import { useActor } from './Actor'
import { useAuth } from '../state/auth'
import { rpc } from '../lib/supabase'
import {
  WalletIcon,
  CoinsIcon,
  ClockIcon,
  SessionsIcon,
  UsersIcon,
  SparkIcon,
  TrophyIcon,
} from './icons'
import { rupees, relativeFrom } from '../lib/format'
import {
  useCustomerSummary,
  useCustomerRefundables,
  regularity,
  playLength,
  tierLabel,
  type CustomerSummary,
  type RefundableCharge,
} from '../hooks/useCustomerSummary'

/** Reusable customer-insight bottom sheet. Pass a familyId to open it; pass
 *  null to close. Renders the full staff_customer_summary payload — visit
 *  history, wallet, honest spend breakdown, favourite items and hero tier —
 *  so staff can greet and upsell with real context. */
export function CustomerSheet({
  familyId,
  onClose,
}: {
  familyId: string | null
  onClose: () => void
}) {
  const q = useCustomerSummary(familyId)
  const s = q.data

  return (
    <Sheet open={!!familyId} onClose={onClose} title="Customer">
      {q.isLoading && (
        <div className="flex items-center justify-center py-14 text-primary">
          <Spinner size={28} />
        </div>
      )}

      {q.isError && (
        <Empty
          title="Couldn't load this customer"
          hint={
            String((q.error as Error)?.message ?? '').includes('family_deleted')
              ? 'This profile has been closed for privacy.'
              : 'Check the connection and try again.'
          }
        />
      )}

      {s && <Body s={s} />}
    </Sheet>
  )
}

function Body({ s }: { s: CustomerSummary }) {
  const sig = regularity(s)
  const tier = tierLabel(s.member_tier)
  const name = s.guardian_name?.trim() || (s.is_walk_in ? 'Walk-in guest' : 'Customer')

  return (
    <div className="pb-3">
      {/* ── Hero ─────────────────────────────────────────────────────── */}
      <div className="flex items-center gap-3">
        <Avatar name={name} tone={sig.tone} />
        <div className="min-w-0 flex-1">
          <p className="truncate text-xl font-black leading-tight">{name}</p>
          {s.guardian_phone && (
            <p className="truncate text-sm text-dim">{s.guardian_phone}</p>
          )}
        </div>
        <SignalDots dots={sig.dots} tone={sig.tone} />
      </div>

      {/* ── Signal + quick facts ─────────────────────────────────────── */}
      <div className="mt-3 flex flex-wrap gap-2">
        <Pill tone={sig.tone === 'dim' ? 'dim' : sig.tone}>{sig.label}</Pill>
        {tier && (
          <Pill tone="gold" className="gap-1">
            <TrophyIcon size={13} /> {tier}
          </Pill>
        )}
        <Fact icon={<SessionsIcon size={13} />}>
          {s.visit_count} {s.visit_count === 1 ? 'visit' : 'visits'}
        </Fact>
        {s.last_visit_at && (
          <Fact icon={<ClockIcon size={13} />}>
            Last {relativeFrom(s.last_visit_at)}
          </Fact>
        )}
        {s.avg_session_length_minutes > 0 && (
          <Fact icon={<ClockIcon size={13} />}>
            {playLength(s.avg_session_length_minutes)} avg
          </Fact>
        )}
      </div>

      {/* ── Kids ─────────────────────────────────────────────────────── */}
      {s.child_names.length > 0 && (
        <div className="mt-4 flex flex-wrap items-center gap-2">
          <span className="text-faint">
            <UsersIcon size={15} />
          </span>
          {s.child_names.map((n, i) => (
            <span
              key={i}
              className="rounded-full border border-line bg-surface-2 px-3 py-1 text-sm font-bold"
            >
              {n}
            </span>
          ))}
          {s.total_xp > 0 && (
            <Pill tone="primary" className="gap-1">
              <SparkIcon size={12} /> {s.total_xp.toLocaleString('en-IN')} XP
            </Pill>
          )}
        </div>
      )}

      {/* ── Wallet ───────────────────────────────────────────────────── */}
      <div className="mt-4 rounded-2xl border border-gold/25 bg-gold/[0.07] p-4">
        <div className="flex items-center justify-between">
          <span className="flex items-center gap-2 text-sm font-bold text-gold">
            <WalletIcon size={17} /> Wallet
          </span>
          {s.coins_balance > 0 && (
            <span className="flex items-center gap-1 text-sm font-bold text-gold">
              <CoinsIcon size={15} /> {s.coins_balance.toLocaleString('en-IN')}
            </span>
          )}
        </div>
        <p className="mt-1 text-3xl font-black tracking-tight">
          {rupees(s.wallet_balance_paise)}
        </p>
        {s.wallet_held_paise > 0 && (
          <p className="mt-0.5 text-xs font-semibold text-faint">
            {rupees(s.wallet_held_paise)} on hold
          </p>
        )}
      </div>

      {/* ── Lifetime spend ───────────────────────────────────────────── */}
      <SpendBreakdown s={s} />

      {/* ── Favourite items ──────────────────────────────────────────── */}
      {s.top_food_items.length > 0 && (
        <div className="mt-4">
          <Label>Usual order</Label>
          <div className="flex flex-wrap gap-2">
            {s.top_food_items.map((it, i) => (
              <span
                key={i}
                className="flex items-center gap-1.5 rounded-full border border-line bg-surface-2 px-3 py-1.5 text-sm font-bold"
              >
                {it.name}
                <span className="text-gold">×{it.count}</span>
              </span>
            ))}
          </div>
        </div>
      )}

      {/* ── Refunds ─────────────────────────────────────────────────── */}
      <RefundsSection familyId={s.family_id} />
    </div>
  )
}

/* ── Refunds: reverse a recent order/session to the wallet ──────────── */
function RefundsSection({ familyId }: { familyId: string }) {
  const q = useCustomerRefundables(familyId)
  const items = q.data ?? []
  if (items.length === 0) return null
  return (
    <div className="mt-4">
      <Label>Recent charges · refund</Label>
      <div className="space-y-2">
        {items.map((it) => (
          <RefundRow
            key={`${it.type}:${it.id}`}
            item={it}
            familyId={familyId}
            onDone={() => q.refetch()}
          />
        ))}
      </div>
    </div>
  )
}

function RefundRow({
  item,
  familyId,
  onDone,
}: {
  item: RefundableCharge
  familyId: string
  onDone: () => void
}) {
  const toast = useToast()
  const requireActor = useActor().requireActor
  const { venueId } = useAuth()
  const remaining = item.paid_paise - item.refunded_paise
  const [open, setOpen] = useState(false)
  const [amountPaise, setAmountPaise] = useState(remaining)
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)

  async function submit() {
    if (busy) return
    if (amountPaise <= 0 || amountPaise > remaining) {
      toast('Enter an amount up to what’s left.', 'err')
      return
    }
    const staff = await requireActor()
    if (!staff || !venueId) return
    setBusy(true)
    try {
      await rpc('refund_issue', {
        p_family_id: familyId,
        p_reference_id: item.id,
        p_reference_type: item.type,
        p_amount_paise: amountPaise,
        p_destination: 'wallet',
        p_reason: reason.trim() || 'Refund at counter',
        p_staff_pin_id: staff.staffId,
        p_venue_id: venueId,
        p_idempotency_key: `refund:${item.id}:${amountPaise}`,
      })
      toast(`Refunded ${rupees(amountPaise)} to wallet`, 'ok')
      setOpen(false)
      onDone()
    } catch (e) {
      const msg = String((e as Error)?.message ?? '')
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
    <div className="rounded-2xl border border-line bg-surface-2/60 p-3">
      <div className="flex items-center gap-2">
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-bold">{item.label}</p>
          <p className="text-xs text-faint">
            {item.type === 'session' ? 'Play' : 'Food'} · {rupees(item.paid_paise)}
            {item.payment_method ? ` · ${item.payment_method}` : ''}
          </p>
        </div>
        {remaining > 0 ? (
          <button
            onClick={() => setOpen((o) => !o)}
            className="shrink-0 rounded-full border border-danger/40 px-3 py-1.5 text-xs font-bold text-danger active:bg-danger/10"
          >
            Refund
          </button>
        ) : (
          <Pill tone="dim">Refunded</Pill>
        )}
      </div>

      {open && remaining > 0 && (
        <div className="mt-3 space-y-2">
          <input
            type="number"
            inputMode="decimal"
            value={amountPaise / 100}
            onChange={(e) =>
              setAmountPaise(Math.round((parseFloat(e.target.value) || 0) * 100))
            }
            className="w-full rounded-xl border border-line bg-surface px-3 py-2 text-base font-bold focus:border-primary focus:outline-none"
          />
          <input
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Reason (optional)"
            className="w-full rounded-xl border border-line bg-surface px-3 py-2 text-sm placeholder:text-faint focus:border-primary focus:outline-none"
          />
          <Button
            variant="primary"
            loading={busy}
            onClick={submit}
            className="w-full py-2.5 text-sm"
          >
            Refund {rupees(amountPaise)} to wallet
          </Button>
        </div>
      )}
    </div>
  )
}

/* ── Spend breakdown with an honest segmented bar ───────────────────── */
function SpendBreakdown({ s }: { s: CustomerSummary }) {
  const segs = [
    { key: 'Play', v: s.session_spend_paise, color: 'var(--color-primary)' },
    { key: 'Food', v: s.food_spend_paise, color: 'var(--color-gold)' },
    { key: 'Workshops', v: s.workshop_spend_paise, color: 'var(--color-zena)' },
    { key: 'Birthday', v: s.birthday_spend_paise, color: 'var(--color-rafi)' },
  ].filter((x) => x.v > 0)
  const total =
    s.lifetime_spend_paise || segs.reduce((a, b) => a + b.v, 0)

  return (
    <div className="mt-4 rounded-2xl border border-line bg-surface-2/60 p-4">
      <div className="flex items-baseline justify-between">
        <Label className="mb-0">Lifetime spend</Label>
        <span className="text-2xl font-black tracking-tight">
          {rupees(total)}
        </span>
      </div>

      {total > 0 ? (
        <>
          <div className="mt-3 flex h-2.5 w-full overflow-hidden rounded-full bg-ink">
            {segs.map((seg) => (
              <div
                key={seg.key}
                style={{
                  width: `${(seg.v / total) * 100}%`,
                  background: seg.color,
                }}
              />
            ))}
          </div>
          <div className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2">
            {segs.map((seg) => (
              <div key={seg.key} className="flex items-center gap-2">
                <span
                  className="h-2.5 w-2.5 shrink-0 rounded-full"
                  style={{ background: seg.color }}
                />
                <span className="text-sm text-dim">{seg.key}</span>
                <span className="ml-auto text-sm font-bold">
                  {rupees(seg.v)}
                </span>
              </div>
            ))}
          </div>
        </>
      ) : (
        <p className="mt-2 text-sm text-faint">No spend recorded yet.</p>
      )}
    </div>
  )
}

/* ── Small building blocks ──────────────────────────────────────────── */
function Avatar({ name, tone }: { name: string; tone: string }) {
  const initials = name
    .split(/\s+/)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase() ?? '')
    .join('')
  const ring =
    tone === 'gold'
      ? 'bg-gold/15 text-gold'
      : tone === 'active'
        ? 'bg-active/15 text-active'
        : tone === 'primary'
          ? 'bg-primary/15 text-primary'
          : 'bg-surface-2 text-dim'
  return (
    <span
      className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl text-lg font-black ${ring}`}
    >
      {initials || '·'}
    </span>
  )
}

function SignalDots({ dots, tone }: { dots: number; tone: string }) {
  const on =
    tone === 'gold'
      ? 'bg-gold'
      : tone === 'active'
        ? 'bg-active'
        : tone === 'primary'
          ? 'bg-primary'
          : 'bg-faint'
  return (
    <span className="flex shrink-0 items-center gap-1">
      {[0, 1, 2].map((i) => (
        <span
          key={i}
          className={`h-2 w-2 rounded-full ${i < dots ? on : 'bg-line'}`}
        />
      ))}
    </span>
  )
}

function Fact({ icon, children }: { icon: ReactNode; children: ReactNode }) {
  return (
    <Pill tone="dim" className="gap-1.5">
      <span className="text-faint">{icon}</span>
      {children}
    </Pill>
  )
}

function Label({
  children,
  className = '',
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <p
      className={`mb-2 text-xs font-bold uppercase tracking-wider text-faint ${className}`}
    >
      {children}
    </p>
  )
}
