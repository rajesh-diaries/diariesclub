import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Header, Page } from '../components/Shell'
import { Button, Card, Spinner, useToast } from '../components/ui'
import { useActor } from '../components/Actor'
import { SearchIcon, SparkIcon, CheckIcon } from '../components/icons'
import { supabase, rpc } from '../lib/supabase'
import { toE164 } from '../lib/format'

type Tab = 'perk' | 'card'

export function RewardsScreen() {
  const [tab, setTab] = useState<Tab>('perk')
  return (
    <>
      <Header subtitle="At the counter" title="Rewards" />
      <Page>
        <div className="mb-4 flex gap-1 rounded-2xl border border-line bg-surface p-1">
          {(['perk', 'card'] as Tab[]).map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={`flex-1 rounded-xl py-2.5 text-sm font-bold transition-colors ${
                tab === t ? 'bg-primary text-white' : 'text-dim'
              }`}
            >
              {t === 'perk' ? 'Redeem perk' : 'Surprise card'}
            </button>
          ))}
        </div>
        {tab === 'perk' ? <PerkRedeem /> : <SurpriseCard />}
      </Page>
    </>
  )
}

function PerkRedeem() {
  const toast = useToast()
  const requireActor = useActor().requireActor
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [done, setDone] = useState<string | null>(null)

  async function redeem() {
    const staff = await requireActor()
    if (!staff) return
    setBusy(true)
    setDone(null)
    try {
      const res = await rpc<any>('stage_perk_redeem', {
        p_code: code.trim().toUpperCase(),
        p_staff_pin_id: staff.staffId,
      })
      setDone(res?.perk_name ? `Redeemed: ${res.perk_name}` : 'Perk redeemed ✓')
      toast('Perk redeemed ✓', 'ok')
      setCode('')
    } catch (err: any) {
      const msg = String(err?.message ?? '')
      toast(
        msg.includes('already') ? 'Already redeemed.' : 'Invalid or expired code.',
        'err',
      )
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card className="p-4">
      <p className="mb-3 text-sm text-dim">
        Enter the perk code the child unlocked at a hero stage.
      </p>
      <input
        value={code}
        onChange={(e) => setCode(e.target.value.toUpperCase())}
        placeholder="PERK CODE"
        autoCapitalize="characters"
        className="mb-3 w-full rounded-2xl border border-line bg-surface-2 px-4 py-4 text-center text-xl font-black tracking-[0.2em] uppercase placeholder:tracking-normal placeholder:text-faint focus:border-primary focus:outline-none"
      />
      <Button
        onClick={redeem}
        loading={busy}
        disabled={code.trim().length < 3}
        className="w-full"
      >
        Redeem perk
      </Button>
      {done && (
        <p className="mt-3 text-center text-sm font-semibold text-active">{done}</p>
      )}
    </Card>
  )
}

interface Child {
  id: string
  name: string
}
interface CardDef {
  id: string
  name: string
  hero: string
  is_rare: boolean
  image_url: string | null
}

function SurpriseCard() {
  const toast = useToast()
  const requireActor = useActor().requireActor
  const [phone, setPhone] = useState('')
  const [looking, setLooking] = useState(false)
  const [children, setChildren] = useState<Child[] | null>(null)
  const [childId, setChildId] = useState<string | null>(null)
  const [cardId, setCardId] = useState<string | null>(null)
  const [granting, setGranting] = useState(false)

  const cards = useQuery({
    queryKey: ['card-defs'],
    queryFn: async (): Promise<CardDef[]> => {
      const { data } = await supabase
        .from('hero_card_definitions')
        .select('id, name, hero, is_rare, image_url, is_birthday_exclusive, is_active')
        .eq('is_active', true)
        .eq('is_birthday_exclusive', false)
        .order('name')
      return (data ?? []) as CardDef[]
    },
  })

  async function lookup() {
    const e164 = toE164(phone)
    if (!e164) {
      toast('Enter a valid 10-digit number.', 'err')
      return
    }
    setLooking(true)
    setChildren(null)
    setChildId(null)
    try {
      const res = await rpc<any>('staff_lookup_family', { p_phone: e164 })
      const kids: Child[] = (res.children ?? []).map((c: any) => ({
        id: c.id,
        name: c.name,
      }))
      setChildren(kids)
      setChildId(kids.length === 1 ? kids[0].id : null)
      if (kids.length === 0) toast('No children on this family.', 'err')
    } catch {
      toast('No family found.', 'err')
    } finally {
      setLooking(false)
    }
  }

  async function grant() {
    if (!childId || !cardId) return
    const staff = await requireActor()
    if (!staff) return
    setGranting(true)
    try {
      await rpc('card_grant_surprise', {
        p_child_id: childId,
        p_card_id: cardId,
        p_staff_pin_id: staff.staffId,
      })
      toast('Surprise card granted 🎁', 'ok')
      setCardId(null)
    } catch (err: any) {
      const msg = String(err?.message ?? '')
      toast(msg.includes('already') ? 'Child already has that card.' : "Couldn't grant.", 'err')
    } finally {
      setGranting(false)
    }
  }

  return (
    <div>
      <Card className="mb-4 p-4">
        <label className="mb-2 block px-1 text-xs font-bold uppercase tracking-wider text-faint">
          Find the child by phone
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
              className="w-full bg-transparent px-2 py-4 placeholder:text-faint focus:outline-none"
            />
          </div>
          <Button onClick={lookup} loading={looking} disabled={phone.length !== 10} className="px-4">
            {!looking && <SearchIcon size={20} />}
          </Button>
        </div>
      </Card>

      {children && children.length > 0 && (
        <div className="animate-rise">
          <p className="mb-2 px-1 text-xs font-bold uppercase tracking-wider text-faint">
            Whose card?
          </p>
          <div className="mb-4 flex flex-wrap gap-2">
            {children.map((c) => (
              <button
                key={c.id}
                onClick={() => setChildId(c.id)}
                className={`rounded-full border-2 px-4 py-2.5 text-sm font-bold ${
                  childId === c.id
                    ? 'border-primary bg-primary/10 text-text'
                    : 'border-line bg-surface-2 text-dim'
                }`}
              >
                {c.name}
              </button>
            ))}
          </div>

          <p className="mb-2 px-1 text-xs font-bold uppercase tracking-wider text-faint">
            Pick a card
          </p>
          {cards.isLoading ? (
            <div className="flex justify-center py-8 text-primary">
              <Spinner size={24} />
            </div>
          ) : (
            <div className="grid grid-cols-3 gap-2">
              {(cards.data ?? []).map((c) => (
                <button
                  key={c.id}
                  onClick={() => setCardId(c.id)}
                  className={`relative overflow-hidden rounded-2xl border-2 p-2 text-center ${
                    cardId === c.id ? 'border-primary' : 'border-line'
                  }`}
                >
                  <div className="mb-1 flex aspect-square items-center justify-center rounded-xl bg-surface-2">
                    {c.image_url ? (
                      <img src={c.image_url} alt="" className="h-full w-full rounded-xl object-cover" />
                    ) : (
                      <SparkIcon size={26} />
                    )}
                  </div>
                  <p className="truncate text-xs font-bold">{c.name}</p>
                  {c.is_rare && (
                    <span className="absolute right-1 top-1 rounded-full bg-gold px-1.5 text-[9px] font-black text-ink">
                      RARE
                    </span>
                  )}
                  {cardId === c.id && (
                    <span className="absolute left-1 top-1 flex h-5 w-5 items-center justify-center rounded-full bg-primary text-white">
                      <CheckIcon size={12} />
                    </span>
                  )}
                </button>
              ))}
            </div>
          )}

          <Button
            onClick={grant}
            loading={granting}
            disabled={!childId || !cardId}
            variant="gold"
            className="mt-4 w-full"
          >
            Grant surprise card
          </Button>
        </div>
      )}
    </div>
  )
}
