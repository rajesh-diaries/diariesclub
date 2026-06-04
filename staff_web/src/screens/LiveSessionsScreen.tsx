import { useState } from 'react'
import { Header, Page } from '../components/Shell'
import { Button, Card, Empty, Pill, useToast } from '../components/ui'
import { Sheet } from '../components/Sheet'
import { useActor } from '../components/Actor'
import { SessionsIcon, RefreshIcon, ClockIcon } from '../components/icons'
import { rpc } from '../lib/supabase'
import { clock, secondsUntil } from '../lib/format'
import { useNow } from '../hooks/useNow'
import {
  useActiveSessions,
  embedName,
  type SessionRow,
} from '../hooks/useVenueData'

export function LiveSessionsScreen() {
  const sessions = useActiveSessions()
  const now = useNow()
  const [extend, setExtend] = useState<SessionRow | null>(null)
  const [close, setClose] = useState<SessionRow | null>(null)

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
        ) : sorted.length === 0 ? (
          <Empty
            icon={<SessionsIcon size={48} />}
            title="No one playing right now"
            hint="Check a child in from the front desk and they'll show up here, live."
          />
        ) : (
          sorted.map((s) => (
            <SessionCard
              key={s.id}
              s={s}
              now={now}
              onExtend={() => setExtend(s)}
              onClose={() => setClose(s)}
            />
          ))
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
    </>
  )
}

function SessionCard({
  s,
  now,
  onExtend,
  onClose,
}: {
  s: SessionRow
  now: number
  onExtend: () => void
  onClose: () => void
}) {
  const grace = s.status === 'grace'
  const remaining = secondsUntil(s.expires_at, now)
  const child = embedName(s.children) || 'Guest'
  const guardian = embedName(s.families)

  return (
    <Card
      className={`animate-rise mb-3 overflow-hidden p-4 ${
        grace ? 'border-grace/40 bg-grace/5' : ''
      }`}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-lg font-extrabold">{child}</p>
          {guardian && (
            <p className="truncate text-sm text-dim">{guardian}</p>
          )}
        </div>
        {grace ? (
          <Pill tone="grace">Grace</Pill>
        ) : (
          <Pill tone="active">
            <span className="live-dot mr-1 inline-block h-1.5 w-1.5 rounded-full bg-active" />
            Active
          </Pill>
        )}
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
  const [busy, setBusy] = useState<number | null>(null)

  async function extend(mins: number) {
    if (!session) return
    setBusy(mins)
    try {
      await rpc('session_extend', {
        p_session_id: session.id,
        p_duration_minutes: mins,
        p_payment_method: 'cash',
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
