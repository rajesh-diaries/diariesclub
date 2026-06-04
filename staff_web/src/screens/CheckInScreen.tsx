import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Header, Page } from '../components/Shell'
import { Button, Card, Pill, useToast } from '../components/ui'
import { useActor, type Actor } from '../components/Actor'
import {
  SearchIcon,
  CheckIcon,
  ClockIcon,
  UsersIcon,
  QrIcon,
  ChevronRight,
} from '../components/icons'
import { rpc } from '../lib/supabase'
import { toE164, relativeFrom } from '../lib/format'
import { useAuth } from '../state/auth'

interface Family {
  id: string
  name: string
  phone: string
}
interface Child {
  id: string
  name: string
}

const DURATIONS = [
  { mins: 60, label: '1 hour', sub: 'Standard play' },
  { mins: 120, label: '2 hours', sub: 'Extended play' },
]
// Sessions are paid by wallet (prepaid) or cash at counter only — the
// backend rejects anything else.
const PAYMENTS = [
  { key: 'wallet', label: 'Wallet' },
  { key: 'cash', label: 'Cash' },
]

export function CheckInScreen() {
  const nav = useNavigate()
  const toast = useToast()
  const { venueId } = useAuth()
  const requireActor = useActor().requireActor

  const [phone, setPhone] = useState('')
  const [looking, setLooking] = useState(false)
  const [lookupError, setLookupError] = useState<string | null>(null)

  const [family, setFamily] = useState<Family | null>(null)
  const [children, setChildren] = useState<Child[]>([])
  const [summary, setSummary] = useState<{
    visit_count?: number
    last_visit_at?: string | null
  } | null>(null)

  const [childId, setChildId] = useState<string | null>(null)
  const [duration, setDuration] = useState<number | null>(null)
  const [payment, setPayment] = useState('wallet')
  const [starting, setStarting] = useState(false)

  const canStart = !!family && (childId !== null || children.length === 0) && !!duration

  function reset() {
    setFamily(null)
    setChildren([])
    setSummary(null)
    setChildId(null)
    setDuration(null)
    setPayment('wallet')
  }

  async function lookup() {
    const e164 = toE164(phone)
    if (!e164) {
      setLookupError('Enter a valid 10-digit number.')
      return
    }
    setLooking(true)
    setLookupError(null)
    reset()
    try {
      const res = await rpc<any>('staff_lookup_family', { p_phone: e164 })
      const fam = res.family as Family
      const kids: Child[] = (res.children ?? []).map((c: any) => ({
        id: c.id,
        name: c.name,
      }))
      setFamily(fam)
      setChildren(kids)
      setChildId(kids.length === 1 ? kids[0].id : null)
      // Fire-and-forget richer stats.
      rpc<any>('staff_customer_summary', { p_family_id: fam.id })
        .then(setSummary)
        .catch(() => {})
    } catch (err: any) {
      const msg = String(err?.message ?? '')
      setLookupError(
        msg.includes('family_not_found')
          ? 'No family found with that number.'
          : "Couldn't look up. Try again.",
      )
    } finally {
      setLooking(false)
    }
  }

  async function startSession(staff: Actor) {
    if (!family || !duration || !venueId) return
    setStarting(true)
    try {
      await rpc('session_create', {
        p_venue_id: venueId,
        p_family_id: family.id,
        p_child_id: childId,
        p_duration_minutes: duration,
        p_payment_method: payment,
        p_staff_pin_id: staff.staffId,
        p_idempotency_key: crypto.randomUUID(),
      })
      const who = children.find((c) => c.id === childId)?.name ?? family.name
      toast(`Session started for ${who} 🎉`, 'ok')
      nav('/live')
    } catch (err: any) {
      const msg = String(err?.message ?? '')
      toast(
        msg.includes('insufficient_balance')
          ? 'Wallet balance too low — switch to cash.'
          : "Couldn't start session.",
        'err',
      )
      setStarting(false)
    }
  }

  return (
    <>
      <Header subtitle="Front desk" title="Check in" />
      <Page>
        {/* Fast path: scan the QR the parent shows after starting a session */}
        <button
          onClick={() => nav('/scan')}
          className="mb-3 flex w-full items-center gap-3 rounded-2xl border border-line bg-surface-2 px-4 py-3.5 text-left active:scale-[0.99]"
        >
          <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/15 text-primary">
            <QrIcon size={22} />
          </span>
          <span className="flex-1">
            <span className="block font-bold">Scan QR</span>
            <span className="block text-xs text-dim">
              Fastest — scan the parent's session code
            </span>
          </span>
          <ChevronRight size={18} className="text-faint" />
        </button>

        <div className="mb-3 flex items-center gap-3 px-1">
          <div className="h-px flex-1 bg-line" />
          <span className="text-xs font-semibold text-faint">or look up by phone</span>
          <div className="h-px flex-1 bg-line" />
        </div>

        {/* Phone lookup */}
        <Card className="mb-4 p-4">
          <label className="mb-2 block px-1 text-xs font-bold uppercase tracking-wider text-faint">
            Parent's phone
          </label>
          <div className="flex gap-2">
            <div className="flex flex-1 items-center rounded-2xl border border-line bg-surface-2 px-3 focus-within:border-primary">
              <span className="font-semibold text-dim">+91</span>
              <input
                value={phone}
                onChange={(e) => setPhone(e.target.value.replace(/\D/g, '').slice(0, 10))}
                onKeyDown={(e) => e.key === 'Enter' && lookup()}
                inputMode="numeric"
                placeholder="98765 43210"
                className="w-full bg-transparent px-2 py-4 text-[1.0625rem] tracking-wide placeholder:text-faint focus:outline-none"
              />
            </div>
            <Button
              onClick={lookup}
              loading={looking}
              disabled={phone.length !== 10}
              icon={!looking && <SearchIcon size={20} />}
              className="px-4"
            >
              {''}
            </Button>
          </div>
          {lookupError && (
            <div className="mt-3">
              <p className="px-1 text-sm font-semibold text-danger">
                {lookupError}
              </p>
              {lookupError.includes('No family') && (
                <Button
                  variant="surface"
                  onClick={() =>
                    nav('/walkin', { state: { phone } })
                  }
                  className="mt-3 w-full"
                >
                  Register as walk-in (no app)
                </Button>
              )}
            </div>
          )}
        </Card>

        {/* Always-available walk-in path for app-less customers */}
        {!family && (
          <button
            onClick={() => nav('/walkin', { state: { phone } })}
            className="mb-4 flex w-full items-center gap-3 rounded-2xl border border-line bg-surface-2 px-4 py-3.5 text-left active:scale-[0.99]"
          >
            <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-gold/15 text-gold">
              <UsersIcon size={22} />
            </span>
            <span className="flex-1">
              <span className="block font-bold">No app? New walk-in</span>
              <span className="block text-xs text-dim">
                Enter details from the paper form
              </span>
            </span>
            <ChevronRight size={18} className="text-faint" />
          </button>
        )}

        {/* Family found */}
        {family && (
          <div className="animate-rise">
            <Card className="mb-4 border-active/30 bg-active/5 p-4">
              <div className="flex items-center gap-3">
                <span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-active/15 text-active">
                  <CheckIcon size={24} />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-lg font-extrabold">{family.name}</p>
                  <p className="text-sm text-dim">{family.phone}</p>
                </div>
              </div>
              <div className="mt-3 flex flex-wrap gap-2">
                <MetaPill icon={<UsersIcon size={14} />}
                  text={`${summary?.visit_count ?? 0} ${
                    (summary?.visit_count ?? 0) === 1 ? 'visit' : 'visits'
                  }`}
                />
                {summary?.last_visit_at && (
                  <MetaPill
                    icon={<ClockIcon size={14} />}
                    text={`Last visit ${relativeFrom(summary.last_visit_at)}`}
                  />
                )}
              </div>
            </Card>

            {/* Child */}
            <Section title="Who's playing?">
              {children.length === 0 ? (
                <p className="px-1 text-sm text-dim">
                  No children on this family — you can still start a session.
                </p>
              ) : (
                <div className="flex flex-wrap gap-2">
                  {children.map((c) => (
                    <Chip
                      key={c.id}
                      active={childId === c.id}
                      onClick={() => setChildId(c.id)}
                    >
                      {c.name}
                    </Chip>
                  ))}
                </div>
              )}
            </Section>

            {/* Duration */}
            <Section title="How long?">
              <div className="grid grid-cols-2 gap-3">
                {DURATIONS.map((d) => (
                  <button
                    key={d.mins}
                    onClick={() => setDuration(d.mins)}
                    className={`rounded-2xl border-2 p-4 text-center transition-colors ${
                      duration === d.mins
                        ? 'border-primary bg-primary/10'
                        : 'border-line bg-surface-2'
                    }`}
                  >
                    <span className="block text-lg font-black">{d.label}</span>
                    <span
                      className={`text-sm font-semibold ${
                        duration === d.mins ? 'text-primary' : 'text-dim'
                      }`}
                    >
                      {d.sub}
                    </span>
                  </button>
                ))}
              </div>
            </Section>

            {/* Payment */}
            <Section title="Payment">
              <div className="flex flex-wrap gap-2">
                {PAYMENTS.map((p) => (
                  <Chip
                    key={p.key}
                    active={payment === p.key}
                    onClick={() => setPayment(p.key)}
                  >
                    {p.label}
                  </Chip>
                ))}
              </div>
            </Section>

            {/* Start — inline so it's always reachable above the bottom nav */}
            <Button
              onClick={async () => {
                const staff = await requireActor()
                if (staff) startSession(staff)
              }}
              disabled={!canStart || starting}
              loading={starting}
              className="mt-2 w-full py-5 text-lg"
            >
              {starting
                ? ''
                : !childId && children.length > 0
                  ? 'Pick who’s playing'
                  : !duration
                    ? 'Pick a duration'
                    : 'Start session'}
            </Button>
          </div>
        )}
      </Page>
    </>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-4">
      <p className="mb-2 px-1 text-xs font-bold uppercase tracking-wider text-faint">
        {title}
      </p>
      {children}
    </div>
  )
}

function Chip({
  active,
  onClick,
  children,
}: {
  active: boolean
  onClick: () => void
  children: React.ReactNode
}) {
  return (
    <button
      onClick={onClick}
      className={`rounded-full border-2 px-4 py-2.5 text-[0.9375rem] font-bold transition-colors ${
        active
          ? 'border-primary bg-primary/10 text-text'
          : 'border-line bg-surface-2 text-dim'
      }`}
    >
      {children}
    </button>
  )
}

function MetaPill({ icon, text }: { icon: React.ReactNode; text: string }) {
  return (
    <Pill tone="dim" className="gap-1.5">
      <span className="text-faint">{icon}</span>
      {text}
    </Pill>
  )
}
