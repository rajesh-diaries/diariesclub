import { useState } from 'react'
import { Header, Page } from '../components/Shell'
import { Button, Card, Empty, Pill, useToast } from '../components/ui'
import { Sheet } from '../components/Sheet'
import { useActor } from '../components/Actor'
import { SessionsIcon, RefreshIcon, ClockIcon, InfoIcon } from '../components/icons'
import { rpc } from '../lib/supabase'
import { clock, secondsUntil } from '../lib/format'
import { useNow } from '../hooks/useNow'
import {
  useActiveSessions,
  usePendingExits,
  embedName,
  type SessionRow,
} from '../hooks/useVenueData'
import { CustomerSheet } from '../components/CustomerSheet'

export function LiveSessionsScreen() {
  const sessions = useActiveSessions()
  const pendingExits = usePendingExits()
  const now = useNow()
  const [extend, setExtend] = useState<SessionRow | null>(null)
  const [close, setClose] = useState<SessionRow | null>(null)
  const [profileId, setProfileId] = useState<string | null>(null)

  const rows = sessions.data ?? []
  const sorted = [...rows].sort((a, b) => {
    // Grace first (needs attention), then by soonest expiry.
    if (a.status !== b.status) return a.status === 'grace' ? -1 : 1
    return new Date(a.expires_at).getTime() - new Date(b.expires_at).getTime()
  })

  return (
    <>
      <Header
        subtitle="On the floor"
        title="Live sessions"
        right={
          <button
            onClick={() => sessions.refetch()}
            className="rounded-full border border-line bg-surface p-2.5 text-dim active:bg-surface-2"
            aria-label="Refresh"
          >
            <RefreshIcon size={20} />
          </button>
        }
      />
      <Page>
        {sessions.isLoading ? (
          <SkeletonList />
        ) : sorted.length === 0 && (pendingExits.data?.length ?? 0) === 0 ? (
          <Empty
            icon={<SessionsIcon size={48} />}
            title="No one playing right now"
            hint="Check a child in from the front desk and they'll show up here, live."
          />
        ) : (
          <>
            {sorted.map((s) => (
              <SessionCard
                key={s.id}
                s={s}
                now={now}
                onExtend={() => setExtend(s)}
                onClose={() => setClose(s)}
                onInfo={s.family_id ? () => setProfileId(s.family_id) : undefined}
              />
            ))}
            <StillInsideSection
              rows={pendingExits.data ?? []}
              onDone={() => pendingExits.refetch()}
              onInfo={(familyId) => setProfileId(familyId)}
            />
          </>
        )}
      </Page>

      <ExtendSheet
        session={extend}
        onClose={() => setExtend(null)}
        onDone={() => {
          setExtend(null)
          sessions.refetch()
        }}
      />
      <CloseSheet
        session={close}
        onClose={() => setClose(null)}
        onDone={() => {
          setClose(null)
          sessions.refetch()
        }}
      />
      <CustomerSheet familyId={profileId} onClose={() => setProfileId(null)} />
    </>
  )
}

function SessionCard({
  s,
  now,
  onExtend,
  onClose,
  onInfo,
}: {
  s: SessionRow
  now: number
  onExtend: () => void
  onClose: () => void
  onInfo?: () => void
}) {
  const grace = s.status === 'grace'
  const remaining = secondsUntil(s.expires_at, now)
  const child = embedName(s.children) || 'Guest'
  const guardian = embedName(s.families)
  const startedAt = new Date(s.started_at).toLocaleTimeString('en-IN', {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  })

  const heading = (
    <>
      <p className="truncate text-lg font-extrabold">{child}</p>
      {guardian && <p className="truncate text-sm text-dim">{guardian}</p>}
      <p className="mt-0.5 text-xs text-faint">Started {startedAt}</p>
    </>
  )

  return (
    <Card
      className={`animate-rise mb-3 overflow-hidden p-4 ${
        grace ? 'border-grace/40 bg-grace/5' : ''
      }`}
    >
      <div className="flex items-start justify-between gap-3">
        {onInfo ? (
          <button onClick={onInfo} className="min-w-0 text-left active:opacity-70">
            {heading}
          </button>
        ) : (
          <div className="min-w-0">{heading}</div>
        )}
        <div className="flex shrink-0 flex-col items-end gap-1.5">
          <div className="flex items-center gap-2">
          {grace ? (
            <Pill tone="grace">Grace</Pill>
          ) : (
            <Pill tone="active">
              <span className="live-dot mr-1 inline-block h-1.5 w-1.5 rounded-full bg-active" />
              Active
            </Pill>
          )}
          {onInfo && (
            <button
              onClick={onInfo}
              aria-label="Customer profile"
              className="rounded-full border border-line bg-surface-2 p-1.5 text-dim active:bg-line"
            >
              <InfoIcon size={18} />
            </button>
          )}
          </div>
          <PaymentPill method={s.payment_method} />
        </div>
      </div>

      {/* Countdown */}
      <div className="mt-3 flex items-end justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-faint">
            {grace ? 'Over by' : 'Time left'}
          </p>
          <p
            className={`font-mono text-4xl font-black tabular-nums ${
              grace
                ? 'text-grace'
                : remaining < 300
                  ? 'text-grace'
                  : 'text-text'
            }`}
          >
            {clock(remaining)}
          </p>
        </div>
        <p className="pb-1 text-sm text-faint">{s.duration_minutes} min</p>
      </div>

      <div className="mt-4 flex gap-2">
        <Button variant="surface" onClick={onExtend} className="flex-1 py-3">
          <ClockIcon size={18} /> Extend
        </Button>
        <Button variant="danger" onClick={onClose} className="flex-1 py-3">
          Close
        </Button>
      </div>
    </Card>
  )
}

const EXTENSIONS = [
  { mins: 30, label: '+30 min' },
  { mins: 60, label: '+1 hour' },
]

function ExtendSheet({
  session,
  onClose,
  onDone,
}: {
  session: SessionRow | null
  onClose: () => void
  onDone: () => void
}) {
  const toast = useToast()
  const requireActor = useActor().requireActor
  const [busy, setBusy] = useState<number | null>(null)

  async function extend(mins: number) {
    if (!session) return
    // Must identify as staff: the server rejects parent-initiated cash extends
    // (they used to hand out free play time). staff_on_behalf + PIN is allowed.
    const staff = await requireActor()
    if (!staff) return
    setBusy(mins)
    try {
      await rpc('session_extend', {
        p_session_id: session.id,
        p_duration_minutes: mins,
        p_payment_method: 'cash',
        p_initiated_by: 'staff_on_behalf',
        p_staff_pin_id: staff.staffId,
      })
      toast(`Extended by ${mins} min`, 'ok')
      onDone()
    } catch {
      toast("Couldn't extend session.", 'err')
    } finally {
      setBusy(null)
    }
  }

  return (
    <Sheet open={!!session} onClose={onClose} title="Extend session">
      <p className="mb-4 text-sm text-dim">Add more play time to this session.</p>
      <div className="grid grid-cols-2 gap-3 pb-2">
        {EXTENSIONS.map((e) => (
          <Button
            key={e.mins}
            variant="surface"
            loading={busy === e.mins}
            disabled={busy !== null}
            onClick={() => extend(e.mins)}
            className="py-6 text-lg font-black"
          >
            {e.label}
          </Button>
        ))}
      </div>
    </Sheet>
  )
}

function CloseSheet({
  session,
  onClose,
  onDone,
}: {
  session: SessionRow | null
  onClose: () => void
  onDone: () => void
}) {
  const toast = useToast()
  const requireActor = useActor().requireActor
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)

  async function forceClose() {
    if (!session) return
    const staff = await requireActor()
    if (!staff) return
    setBusy(true)
    try {
      await rpc('session_force_close', {
        p_session_id: session.id,
        p_staff_pin_id: staff.staffId,
        p_reason: reason.trim() || 'Wrapped up at desk',
      })
      toast('Session closed', 'ok')
      setReason('')
      onDone()
    } catch {
      toast("Couldn't close session.", 'err')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Sheet open={!!session} onClose={onClose} title="Close session">
      <p className="mb-3 text-sm text-dim">
        End this session now. A short reason keeps the audit trail clean.
      </p>
      <textarea
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        placeholder="Reason (optional) — e.g. family left early"
        rows={3}
        className="mb-4 w-full resize-none rounded-2xl border border-line bg-surface-2 px-4 py-3 text-[1rem] placeholder:text-faint focus:border-primary focus:outline-none"
      />
      <Button
        variant="danger"
        loading={busy}
        onClick={forceClose}
        className="w-full"
      >
        Close session
      </Button>
    </Sheet>
  )
}

/** The "still inside" layer: sessions the customer wrapped up (or that
 *  auto-closed) but that staff hasn't confirmed have left the floor. */
function StillInsideSection({
  rows,
  onDone,
  onInfo,
}: {
  rows: SessionRow[]
  onDone: () => void
  onInfo: (familyId: string) => void
}) {
  if (rows.length === 0) return null
  return (
    <div className="mt-7">
      <div className="mb-1 flex items-center gap-2">
        <p className="text-sm font-bold text-dim">Still inside · wrapped up</p>
        <Pill tone="gold">{rows.length}</Pill>
      </div>
      <p className="mb-3 text-xs text-faint">
        Session ended but not yet off the floor. Tap “Left” once they walk out.
      </p>
      {rows.map((s) => (
        <ExitCard key={s.id} s={s} onDone={onDone} onInfo={onInfo} />
      ))}
    </div>
  )
}

function ExitCard({
  s,
  onDone,
  onInfo,
}: {
  s: SessionRow
  onDone: () => void
  onInfo: (familyId: string) => void
}) {
  const toast = useToast()
  const requireActor = useActor().requireActor
  const [busy, setBusy] = useState(false)
  const child = embedName(s.children) || 'Guest'
  const guardian = embedName(s.families)
  const startedAt = new Date(s.started_at).toLocaleTimeString('en-IN', {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  })

  async function confirmExit() {
    const staff = await requireActor()
    if (!staff) return
    setBusy(true)
    try {
      await rpc('staff_confirm_exit', {
        p_session_id: s.id,
        p_staff_pin_id: staff.staffId,
      })
      toast(`${child} marked as left`, 'ok')
      onDone()
    } catch {
      toast("Couldn't confirm exit.", 'err')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card className="mb-3 flex items-center gap-3 p-4">
      <button
        onClick={() => s.family_id && onInfo(s.family_id)}
        className="min-w-0 flex-1 text-left active:opacity-70"
      >
        <p className="truncate font-bold">{child}</p>
        {guardian && <p className="truncate text-sm text-dim">{guardian}</p>}
        <p className="mt-0.5 text-xs text-faint">Started {startedAt}</p>
      </button>
      <PaymentPill method={s.payment_method} />
      <Button
        variant="surface"
        loading={busy}
        onClick={confirmExit}
        className="shrink-0 px-4 py-2.5 text-sm"
      >
        Left ✓
      </Button>
    </Card>
  )
}

const PAYMENT_LABELS: Record<
  string,
  { label: string; tone: 'primary' | 'gold' | 'active' | 'dim' }
> = {
  wallet: { label: 'Wallet', tone: 'primary' },
  cash: { label: 'Cash', tone: 'gold' },
  play_pass: { label: 'Play Pass', tone: 'active' },
}

/** Wallet / Cash / Play Pass tag so staff see the mode at a glance. */
function PaymentPill({ method }: { method: string | null }) {
  const p = PAYMENT_LABELS[method ?? ''] ?? { label: method ?? '—', tone: 'dim' as const }
  return <Pill tone={p.tone}>{p.label}</Pill>
}

function SkeletonList() {
  return (
    <div className="space-y-3">
      {[0, 1, 2].map((i) => (
        <div
          key={i}
          className="h-40 animate-pulse rounded-[1.25rem] border border-line bg-surface/60"
        />
      ))}
    </div>
  )
}
