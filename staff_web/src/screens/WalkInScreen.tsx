import { useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { Header, Page } from '../components/Shell'
import { Button, Card, useToast } from '../components/ui'
import { useActor } from '../components/Actor'
import { CheckIcon } from '../components/icons'
import { supabase, rpc } from '../lib/supabase'
import { toE164 } from '../lib/format'
import { useAuth } from '../state/auth'

const DURATIONS = [
  { mins: 60, label: '1 hour', sub: 'Standard play' },
  { mins: 120, label: '2 hours', sub: 'Extended play' },
]

/** Manual walk-in registration for customers with no app. The paper consent
 *  form (signed waiver) stays the legal record; staff capture the details
 *  here so the visit is tracked (guest session) and on the books. */
export function WalkInScreen() {
  const nav = useNavigate()
  const toast = useToast()
  const { venueId } = useAuth()
  const requireActor = useActor().requireActor
  const prefill = (useLocation().state as { phone?: string } | null)?.phone ?? ''

  const [parentName, setParentName] = useState('')
  const [phone, setPhone] = useState(prefill)
  const [kidName, setKidName] = useState('')
  const [dob, setDob] = useState('')
  const [consent, setConsent] = useState(false)
  const [duration, setDuration] = useState<number | null>(60)
  const [busy, setBusy] = useState(false)

  const canStart = !!parentName.trim() && !!kidName.trim() && consent && !!duration

  async function start() {
    if (!venueId || !duration) return
    const e164 = toE164(phone) // null if blank/invalid — phone is optional
    const staff = await requireActor()
    if (!staff) return
    setBusy(true)
    try {
      // Guest session — no family/child (a family needs an app account).
      const res = await rpc<any>('session_create', {
        p_venue_id: venueId,
        p_family_id: null,
        p_child_id: null,
        p_duration_minutes: duration,
        p_payment_method: 'cash',
        p_staff_pin_id: staff.staffId,
        p_is_guest: true,
        p_guest_phone: e164,
        p_idempotency_key: crypto.randomUUID(),
      })

      // Record the walk-in's details for the books (paper form is the
      // signed consent; this is the digital trail).
      const sessionId = res?.session_id ?? null
      await supabase.from('audit_log').insert({
        actor_id: staff.staffId,
        actor_type: 'staff',
        action: 'walkin.register',
        entity_type: 'session',
        ...(sessionId ? { entity_id: sessionId } : {}),
        venue_id: venueId,
        new_value: {
          parent_name: parentName.trim(),
          kid_name: kidName.trim(),
          phone: e164,
          dob: dob || null,
          paper_consent_collected: true,
        },
      })

      toast(`Walk-in started for ${kidName.trim()} 🎉`, 'ok')
      nav('/live')
    } catch (err: any) {
      const msg = String(err?.message ?? '')
      toast(
        msg.includes('invalid_payment') ? 'Payment not allowed.' : "Couldn't start walk-in.",
        'err',
      )
      setBusy(false)
    }
  }

  return (
    <>
      <Header subtitle="No app needed" title="New walk-in" />
      <Page>
        <Card className="mb-4 p-4">
          <p className="mb-4 text-sm text-dim">
            Take the signed paper form first, then enter the details here to
            put the visit on the system.
          </p>

          <Field label="Parent's name" required>
            <input
              value={parentName}
              onChange={(e) => setParentName(e.target.value)}
              placeholder="e.g. Priya Sharma"
              className={inputCls}
            />
          </Field>

          <Field label="Phone" hint="optional but recommended">
            <div className="flex items-center rounded-2xl border border-line bg-surface-2 px-3 focus-within:border-primary">
              <span className="font-semibold text-dim">+91</span>
              <input
                value={phone}
                onChange={(e) => setPhone(e.target.value.replace(/\D/g, '').slice(0, 10))}
                inputMode="numeric"
                placeholder="98765 43210"
                className="w-full bg-transparent px-2 py-3.5 tracking-wide placeholder:text-faint focus:outline-none"
              />
            </div>
          </Field>

          <Field label="Child's name" required>
            <input
              value={kidName}
              onChange={(e) => setKidName(e.target.value)}
              placeholder="e.g. Aarav"
              className={inputCls}
            />
          </Field>

          <Field label="Child's date of birth" hint="optional">
            <input
              type="date"
              value={dob}
              max={new Date().toISOString().slice(0, 10)}
              onChange={(e) => setDob(e.target.value)}
              className={inputCls}
            />
          </Field>
        </Card>

        {/* Duration */}
        <p className="mb-2 px-1 text-xs font-bold uppercase tracking-wider text-faint">
          How long?
        </p>
        <div className="mb-4 grid grid-cols-2 gap-3">
          {DURATIONS.map((d) => (
            <button
              key={d.mins}
              onClick={() => setDuration(d.mins)}
              className={`rounded-2xl border-2 p-4 text-center transition-colors ${
                duration === d.mins ? 'border-primary bg-primary/10' : 'border-line bg-surface-2'
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

        <p className="mb-4 px-1 text-sm text-dim">
          Payment: <span className="font-bold text-text">Cash at counter</span>{' '}
          (walk-ins don’t have a wallet).
        </p>

        {/* Consent confirmation */}
        <button
          onClick={() => setConsent((v) => !v)}
          className={`mb-4 flex w-full items-center gap-3 rounded-2xl border-2 p-4 text-left transition-colors ${
            consent ? 'border-active bg-active/10' : 'border-line bg-surface-2'
          }`}
        >
          <span
            className={`flex h-7 w-7 items-center justify-center rounded-lg border-2 ${
              consent ? 'border-active bg-active text-ink' : 'border-faint'
            }`}
          >
            {consent && <CheckIcon size={18} />}
          </span>
          <span className="flex-1 text-sm font-semibold">
            Signed paper consent form collected
          </span>
        </button>

        <Button
          onClick={start}
          loading={busy}
          disabled={!canStart || busy}
          className="w-full py-5 text-lg"
        >
          {busy
            ? ''
            : !parentName.trim() || !kidName.trim()
              ? 'Enter parent & child name'
              : !consent
                ? 'Confirm consent form'
                : 'Start walk-in session'}
        </Button>
      </Page>
    </>
  )
}

const inputCls =
  'w-full rounded-2xl border border-line bg-surface-2 px-4 py-3.5 text-[1.0625rem] placeholder:text-faint focus:border-primary focus:outline-none'

function Field({
  label,
  hint,
  required,
  children,
}: {
  label: string
  hint?: string
  required?: boolean
  children: React.ReactNode
}) {
  return (
    <label className="mb-3 block">
      <span className="mb-1.5 flex items-baseline gap-1.5 px-1">
        <span className="text-xs font-bold uppercase tracking-wider text-faint">
          {label}
        </span>
        {required ? (
          <span className="text-xs font-bold text-danger">required</span>
        ) : hint ? (
          <span className="text-xs text-faint">· {hint}</span>
        ) : null}
      </span>
      {children}
    </label>
  )
}
