import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Header, Page } from '../components/Shell'
import { Button, Card, Empty, Pill, Spinner, useToast } from '../components/ui'
import { useActor } from '../components/Actor'
import { SparkIcon, ChevronRight, CheckIcon } from '../components/icons'
import { supabase, rpc } from '../lib/supabase'
import { useAuth } from '../state/auth'

interface Workshop {
  id: string
  title: string
  scheduled_at: string
  status: string
  primary_trait: string | null
}
interface Reg {
  id: string
  child_name?: string
  family_name?: string
  attended?: boolean
  attended_at?: string | null
}

function useWorkshops() {
  const { venueId } = useAuth()
  return useQuery({
    queryKey: ['workshops', venueId],
    enabled: !!venueId,
    queryFn: async (): Promise<Workshop[]> => {
      const since = new Date(Date.now() - 24 * 3600_000).toISOString()
      const { data, error } = await supabase
        .from('workshops')
        .select('id, title, scheduled_at, status, primary_trait')
        .eq('venue_id', venueId!)
        .eq('is_published', true)
        .gte('scheduled_at', since)
        .order('scheduled_at', { ascending: true })
      if (error) throw error
      return (data ?? []) as Workshop[]
    },
  })
}

export function WorkshopsScreen() {
  const list = useWorkshops()
  const [open, setOpen] = useState<Workshop | null>(null)

  if (open) {
    return <Registrations workshop={open} onBack={() => setOpen(null)} />
  }

  const rows = list.data ?? []
  return (
    <>
      <Header subtitle="Attendance" title="Workshops" />
      <Page>
        {list.isLoading ? (
          <div className="flex justify-center py-16 text-primary">
            <Spinner size={28} />
          </div>
        ) : rows.length === 0 ? (
          <Empty
            icon={<SparkIcon size={48} />}
            title="No workshops scheduled"
            hint="Published workshops for today and upcoming show up here."
          />
        ) : (
          rows.map((w) => (
            <Card
              key={w.id}
              onClick={() => setOpen(w)}
              className="mb-3 flex items-center gap-3 p-4"
            >
              <div className="min-w-0 flex-1">
                <p className="truncate font-bold">{w.title}</p>
                <p className="text-sm text-dim">{when(w.scheduled_at)}</p>
              </div>
              {w.status === 'completed' && <Pill tone="dim">Done</Pill>}
              <ChevronRight size={20} />
            </Card>
          ))
        )}
      </Page>
    </>
  )
}

function Registrations({
  workshop,
  onBack,
}: {
  workshop: Workshop
  onBack: () => void
}) {
  const toast = useToast()
  const requireActor = useActor().requireActor
  const regs = useQuery({
    queryKey: ['workshop-regs', workshop.id],
    queryFn: async (): Promise<Reg[]> => {
      const data = await rpc<any[]>('staff_workshop_list_registrations', {
        p_workshop_id: workshop.id,
      })
      return (data ?? []).map((r: any) => ({
        id: r.id ?? r.registration_id,
        child_name: r.child_name ?? r.child?.name,
        family_name: r.family_name ?? r.family?.name,
        attended: r.attended ?? !!r.attended_at,
        attended_at: r.attended_at,
      }))
    },
  })
  const [busy, setBusy] = useState<string | null>(null)

  async function mark(reg: Reg) {
    const staff = await requireActor()
    if (!staff) return
    setBusy(reg.id)
    try {
      await rpc('staff_workshop_mark_attended', {
        p_registration_id: reg.id,
        p_staff_pin_id: staff.staffId,
      })
      toast(`${reg.child_name ?? 'Child'} marked present ✓`, 'ok')
      regs.refetch()
    } catch {
      toast("Couldn't mark attendance.", 'err')
    } finally {
      setBusy(null)
    }
  }

  const rows = regs.data ?? []
  return (
    <>
      <Header subtitle={when(workshop.scheduled_at)} title={workshop.title} />
      <Page>
        <Button variant="ghost" onClick={onBack} className="mb-2 self-start px-1">
          ← All workshops
        </Button>
        {regs.isLoading ? (
          <div className="flex justify-center py-16 text-primary">
            <Spinner size={28} />
          </div>
        ) : rows.length === 0 ? (
          <Empty title="No registrations yet" />
        ) : (
          rows.map((r) => (
            <Card key={r.id} className="mb-2 flex items-center gap-3 p-3.5">
              <div className="min-w-0 flex-1">
                <p className="truncate font-bold">{r.child_name ?? 'Child'}</p>
                {r.family_name && (
                  <p className="truncate text-sm text-dim">{r.family_name}</p>
                )}
              </div>
              {r.attended ? (
                <Pill tone="active">
                  <CheckIcon size={14} /> Present
                </Pill>
              ) : (
                <Button
                  variant="surface"
                  loading={busy === r.id}
                  onClick={() => mark(r)}
                  className="px-4 py-2.5 text-sm"
                >
                  Mark present
                </Button>
              )}
            </Card>
          ))
        )}
      </Page>
    </>
  )
}

function when(iso: string): string {
  const d = new Date(iso)
  return d.toLocaleString('en-IN', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    hour: 'numeric',
    minute: '2-digit',
  })
}
