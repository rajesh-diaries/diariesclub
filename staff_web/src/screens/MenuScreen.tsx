import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Header, Page } from '../components/Shell'
import { Card, Empty, Spinner, useToast } from '../components/ui'
import { useActor } from '../components/Actor'
import { TagIcon } from '../components/icons'
import { supabase } from '../lib/supabase'
import { useAuth } from '../state/auth'

interface Item {
  id: string
  name: string
  category: string | null
  is_available: boolean
  brand: string
}

function useMenu() {
  const { venueId } = useAuth()
  return useQuery({
    queryKey: ['menu', venueId],
    enabled: !!venueId,
    queryFn: async (): Promise<Item[]> => {
      const { data, error } = await supabase
        .from('menu_items')
        .select('id, name, category, is_available, menus!inner(brand, venue_id)')
        .eq('menus.venue_id', venueId!)
        .eq('is_published', true)
        .order('sort_order', { ascending: true })
      if (error) throw error
      return (data ?? []).map((r: any) => ({
        id: r.id,
        name: r.name,
        category: r.category,
        is_available: r.is_available,
        brand: r.menus?.brand ?? 'other',
      }))
    },
  })
}

const BRAND_LABEL: Record<string, string> = {
  coffee: 'Coffee Diaries',
  fit: 'FIT Diaries',
  other: 'Menu',
}

export function MenuScreen() {
  const menu = useMenu()
  const items = menu.data ?? []
  const brands = [...new Set(items.map((i) => i.brand))]

  return (
    <>
      <Header subtitle="Availability" title="Sold out" />
      <Page>
        {menu.isLoading ? (
          <div className="flex justify-center py-16 text-primary">
            <Spinner size={28} />
          </div>
        ) : items.length === 0 ? (
          <Empty icon={<TagIcon size={48} />} title="No menu items" />
        ) : (
          <>
            <p className="mb-3 px-1 text-sm text-dim">
              Turn an item off and it instantly disappears from customer
              ordering. Turn it back on when it’s available again.
            </p>
            {brands.map((b) => (
              <div key={b} className="mb-5">
                <p className="mb-2 px-1 text-xs font-bold uppercase tracking-wider text-faint">
                  {BRAND_LABEL[b] ?? b}
                </p>
                {items
                  .filter((i) => i.brand === b)
                  .map((i) => (
                    <ItemRow key={i.id} item={i} onDone={() => menu.refetch()} />
                  ))}
              </div>
            ))}
          </>
        )}
      </Page>
    </>
  )
}

function ItemRow({ item, onDone }: { item: Item; onDone: () => void }) {
  const toast = useToast()
  const requireActor = useActor().requireActor
  const { venueId } = useAuth()
  const [busy, setBusy] = useState(false)
  const [available, setAvailable] = useState(item.is_available)

  async function toggle() {
    const next = !available
    const staff = await requireActor()
    if (!staff) return
    setBusy(true)
    setAvailable(next) // optimistic
    try {
      const { error } = await supabase
        .from('menu_items')
        .update({ is_available: next })
        .eq('id', item.id)
      if (error) throw error
      await supabase.from('audit_log').insert({
        actor_id: staff.staffId,
        actor_type: 'staff',
        action: next ? 'menu.enable' : 'menu.disable',
        entity_type: 'menu_item',
        entity_id: item.id,
        venue_id: venueId,
        new_value: { is_available: next },
      })
      toast(next ? `${item.name} is back on` : `${item.name} marked sold out`, 'ok')
      onDone()
    } catch {
      setAvailable(!next) // revert
      toast("Couldn't update.", 'err')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card className="mb-2 flex items-center gap-3 p-3.5">
      <div className="min-w-0 flex-1">
        <p
          className={`truncate font-bold ${available ? '' : 'text-faint line-through'}`}
        >
          {item.name}
        </p>
        {item.category && (
          <p className="text-xs uppercase tracking-wide text-faint">
            {item.category}
          </p>
        )}
      </div>
      {busy ? (
        <Spinner size={20} />
      ) : (
        <button
          onClick={toggle}
          aria-label={available ? 'Mark sold out' : 'Mark available'}
          className={`relative h-8 w-14 rounded-full transition-colors ${
            available ? 'bg-active' : 'bg-surface-2 border border-line'
          }`}
        >
          <span
            className={`absolute top-1 h-6 w-6 rounded-full bg-white shadow transition-all ${
              available ? 'left-7' : 'left-1'
            }`}
          />
        </button>
      )}
    </Card>
  )
}
