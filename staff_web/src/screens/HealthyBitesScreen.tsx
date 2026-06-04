import { useState } from 'react'
import { Header, Page } from '../components/Shell'
import { Button, Card, Empty, Pill, useToast } from '../components/ui'
import { useActor } from '../components/Actor'
import { SparkIcon, RefreshIcon, CheckIcon } from '../components/icons'
import { rpc } from '../lib/supabase'
import { relativeFrom } from '../lib/format'
import {
  useHealthyBites,
  biteStatus,
  embedName,
  type BiteRow,
  type BiteStatus,
} from '../hooks/useVenueData'

/** Complimentary healthy snack — staff hand it out (or decline) per child
 *  after they've played. Distribution can surprise the child with a hero
 *  card, so it's a small delight moment, not just a checkbox. The screen
 *  lists every child with a snack today and where each one stands, so it
 *  stays a record after handing out rather than emptying to nothing. */
export function HealthyBitesScreen() {
  const bites = useHealthyBites()
  const rows = bites.data ?? []

  // Actionable (to-give / still-playing) first, settled (given / skipped) below.
  const ORDER: Record<BiteStatus, number> = {
    pending: 0,
    playing: 1,
    given: 2,
    skipped: 3,
  }
  const sorted = [...rows].sort(
    (a, b) => ORDER[biteStatus(a)] - ORDER[biteStatus(b)],
  )
  const toGive = rows.filter((b) => biteStatus(b) === 'pending').length

  return (
    <>
      <Header
        subtitle="Complimentary snack"
        title="Healthy bites"
        right={
          <button
            onClick={() => bites.refetch()}
            className="rounded-full border border-line bg-surface p-2.5 text-dim active:bg-surface-2"
            aria-label="Refresh"
          >
            <RefreshIcon size={20} />
          </button>
        }
      />
      <Page>
        {bites.isLoading ? (
          <Skeleton />
        ) : rows.length === 0 ? (
          <Empty
            icon={<SparkIcon size={48} />}
            title="No snacks yet today"
            hint="When a child finishes playing, their healthy bite shows up here to give out."
          />
        ) : (
          <>
            <p className="mb-3 px-1 text-sm text-dim">
              {toGive > 0 ? (
                <>
                  <span className="font-bold text-gold">{toGive}</span>{' '}
                  {toGive === 1 ? 'snack' : 'snacks'} to give ·{' '}
                </>
              ) : null}
              {rows.length} {rows.length === 1 ? 'child' : 'children'} today
            </p>
            {sorted.map((b) => (
              <BiteCard key={b.id} bite={b} onDone={() => bites.refetch()} />
            ))}
          </>
        )}
      </Page>
    </>
  )
}

function BiteCard({ bite, onDone }: { bite: BiteRow; onDone: () => void }) {
  const toast = useToast()
  const requireActor = useActor().requireActor
  const [busy, setBusy] = useState<'give' | 'skip' | null>(null)
  const child = embedName(bite.children) || 'Guest'
  const status = biteStatus(bite)
  const settled = status === 'given' || status === 'skipped'

  async function give() {
    const staff = await requireActor()
    if (!staff) return
    setBusy('give')
    try {
      await rpc('healthy_bite_distribute', {
        p_session_id: bite.id,
        p_child_id: bite.child_id,
        p_staff_pin_id: staff.staffId,
      })
      toast(`Snack given to ${child} 🌟`, 'ok')
      onDone()
    } catch {
      toast("Couldn't record that.", 'err')
      setBusy(null)
    }
  }

  async function skip() {
    const staff = await requireActor()
    if (!staff) return
    setBusy('skip')
    try {
      await rpc('healthy_bite_decline', {
        p_session_id: bite.id,
        p_staff_pin_id: staff.staffId,
      })
      toast(`Skipped for ${child}`, 'ok')
      onDone()
    } catch {
      toast("Couldn't record that.", 'err')
      setBusy(null)
    }
  }

  return (
    <Card className={`animate-rise mb-3 p-4 ${settled ? 'opacity-70' : ''}`}>
      <div className="flex items-center gap-3">
        <span
          className={`flex h-11 w-11 items-center justify-center rounded-2xl ${
            status === 'given'
              ? 'bg-active/15 text-active'
              : status === 'skipped'
                ? 'bg-surface-2 text-faint'
                : 'bg-gold/15 text-gold'
          }`}
        >
          {status === 'given' ? <CheckIcon size={24} /> : <SparkIcon size={24} />}
        </span>
        <div className="min-w-0 flex-1">
          <p className="truncate text-lg font-extrabold">{child}</p>
          <p className="text-sm text-dim">
            Played {relativeFrom(bite.completed_at ?? bite.started_at)}
          </p>
        </div>
        <StatusPill status={status} />
      </div>
      {!settled && (
        <div className="mt-4 flex gap-2">
          <Button
            variant="gold"
            loading={busy === 'give'}
            disabled={busy !== null}
            onClick={give}
            icon={busy !== 'give' && <CheckIcon size={18} />}
            className="flex-1 py-3"
          >
            Give snack
          </Button>
          <Button
            variant="surface"
            loading={busy === 'skip'}
            disabled={busy !== null}
            onClick={skip}
            className="px-5 py-3"
          >
            Skip
          </Button>
        </div>
      )}
    </Card>
  )
}

function StatusPill({ status }: { status: BiteStatus }) {
  switch (status) {
    case 'given':
      return <Pill tone="active">Given</Pill>
    case 'skipped':
      return <Pill tone="dim">Skipped</Pill>
    case 'playing':
      return <Pill tone="primary">Still playing</Pill>
    default:
      return <Pill tone="gold">To give</Pill>
  }
}

function Skeleton() {
  return (
    <div className="space-y-3">
      {[0, 1].map((i) => (
        <div
          key={i}
          className="h-32 animate-pulse rounded-[1.25rem] border border-line bg-surface/60"
        />
      ))}
    </div>
  )
}
