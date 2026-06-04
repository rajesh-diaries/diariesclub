import { useNavigate } from 'react-router-dom'
import { Header, Page } from '../components/Shell'
import { Card, Pill } from '../components/ui'
import {
  SessionsIcon,
  KitchenIcon,
  UsersIcon,
  CheckInIcon,
  ChevronRight,
  SignOutIcon,
  RefreshIcon,
  SparkIcon,
  CashIcon,
} from '../components/icons'
import { useAuth } from '../state/auth'
import {
  useActiveSessions,
  useOrders,
  useTodayStats,
  usePendingHealthyBites,
  usePendingCounterPayments,
} from '../hooks/useVenueData'

export function HomeScreen() {
  const nav = useNavigate()
  const { venueLabel, signOut } = useAuth()
  const sessions = useActiveSessions()
  const orders = useOrders()
  const stats = useTodayStats()
  const bites = usePendingHealthyBites()
  const payments = usePendingCounterPayments()

  const activeCount = sessions.data?.length ?? 0
  const graceCount =
    sessions.data?.filter((s) => s.status === 'grace').length ?? 0
  const pendingOrders = orders?.filter((o) => o.status !== 'ready').length ?? 0
  const readyOrders = orders?.filter((o) => o.status === 'ready').length ?? 0
  const bitesPending = bites.data?.length ?? 0
  const paymentsPending = payments.data?.length ?? 0

  const greeting = (() => {
    const h = new Date().getHours()
    if (h < 12) return 'Good morning'
    if (h < 17) return 'Good afternoon'
    return 'Good evening'
  })()

  return (
    <>
      <Header
        subtitle={greeting}
        title={venueLabel}
        right={
          <button
            onClick={() => {
              sessions.refetch()
              stats.refetch()
            }}
            className="rounded-full border border-line bg-surface p-2.5 text-dim active:bg-surface-2"
            aria-label="Refresh"
          >
            <RefreshIcon size={20} />
          </button>
        }
      />

      <Page>
        {/* Hero: live activity at a glance */}
        <Card className="animate-rise mb-4 overflow-hidden p-5">
          <div className="flex items-center justify-between">
            <div>
              <div className="flex items-center gap-2">
                <span className="live-dot inline-block h-2.5 w-2.5 rounded-full bg-active" />
                <span className="text-xs font-bold uppercase tracking-wider text-active">
                  Live now
                </span>
              </div>
              <p className="mt-2 text-5xl font-black tracking-tight">
                {activeCount}
                <span className="ml-2 text-lg font-semibold text-dim">
                  {activeCount === 1 ? 'kid playing' : 'kids playing'}
                </span>
              </p>
            </div>
            <div className="text-primary/30">
              <SessionsIcon size={56} />
            </div>
          </div>
          {graceCount > 0 && (
            <div className="mt-3">
              <Pill tone="grace">
                {graceCount} in grace · check time
              </Pill>
            </div>
          )}
        </Card>

        {/* Today stat tiles */}
        <div className="mb-5 grid grid-cols-2 gap-3">
          <Stat
            icon={<SessionsIcon size={20} />}
            value={stats.data?.sessionsToday ?? '—'}
            label="Sessions today"
          />
          <Stat
            icon={<UsersIcon size={20} />}
            value={stats.data?.kidsToday ?? '—'}
            label="Kids today"
          />
        </div>

        {/* Primary action */}
        <button
          onClick={() => nav('/checkin')}
          className="animate-rise mb-3 flex w-full items-center gap-4 rounded-[1.25rem] bg-primary px-5 py-5 text-left text-white shadow-[0_12px_30px_-10px_rgba(79,124,255,0.8)] transition-transform active:scale-[0.99]"
        >
          <span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-white/15">
            <CheckInIcon size={26} />
          </span>
          <span className="flex-1">
            <span className="block text-lg font-extrabold">Check in a child</span>
            <span className="block text-sm text-white/80">
              Look up by phone · start a session
            </span>
          </span>
          <ChevronRight size={22} />
        </button>

        {/* Pay-at-counter dues — surfaced only when there are any */}
        {paymentsPending > 0 && (
          <ActionRow
            icon={<CashIcon size={24} />}
            title="Pending payments"
            sub={`${paymentsPending} ‘pay at counter’ to collect`}
            badge={<Pill tone="gold">{paymentsPending}</Pill>}
            onClick={() => nav('/pay')}
          />
        )}

        {/* Navigation cards */}
        <ActionRow
          icon={<SessionsIcon size={24} />}
          title="Live sessions"
          sub={
            activeCount === 0
              ? 'No one playing right now'
              : `${activeCount} active${graceCount ? ` · ${graceCount} in grace` : ''}`
          }
          badge={graceCount > 0 ? <Pill tone="grace">{graceCount}</Pill> : undefined}
          onClick={() => nav('/live')}
        />
        <ActionRow
          icon={<KitchenIcon size={24} />}
          title="Kitchen — food"
          sub={
            (orders?.length ?? 0) === 0
              ? 'No food orders pending'
              : `${pendingOrders} cooking · ${readyOrders} ready`
          }
          badge={
            readyOrders > 0 ? (
              <Pill tone="active">{readyOrders} ready</Pill>
            ) : pendingOrders > 0 ? (
              <Pill tone="primary">{pendingOrders} pending</Pill>
            ) : undefined
          }
          onClick={() => nav('/kitchen')}
        />
        <ActionRow
          icon={<SparkIcon size={24} />}
          title="Healthy bites"
          sub={
            bitesPending === 0
              ? 'No snacks waiting'
              : `${bitesPending} complimentary ${
                  bitesPending === 1 ? 'snack' : 'snacks'
                } to hand out`
          }
          badge={
            bitesPending > 0 ? (
              <Pill tone="gold">{bitesPending} pending</Pill>
            ) : undefined
          }
          onClick={() => nav('/bites')}
        />

        <button
          onClick={signOut}
          className="mx-auto mt-6 flex items-center gap-2 rounded-full px-4 py-2 text-sm font-semibold text-faint active:bg-surface-2"
        >
          <SignOutIcon size={16} /> Sign out this phone
        </button>
      </Page>
    </>
  )
}

function Stat({
  icon,
  value,
  label,
  gold,
}: {
  icon: React.ReactNode
  value: React.ReactNode
  label: string
  gold?: boolean
}) {
  return (
    <Card className="flex flex-col gap-1.5 p-3.5">
      <span className={gold ? 'text-gold' : 'text-primary'}>{icon}</span>
      <span className="text-xl font-black leading-none">{value}</span>
      <span className="text-[11px] font-semibold text-faint">{label}</span>
    </Card>
  )
}

function ActionRow({
  icon,
  title,
  sub,
  badge,
  onClick,
}: {
  icon: React.ReactNode
  title: string
  sub: string
  badge?: React.ReactNode
  onClick: () => void
}) {
  return (
    <Card onClick={onClick} className="mb-3 flex items-center gap-4 p-4">
      <span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-surface-2 text-primary">
        {icon}
      </span>
      <span className="flex-1">
        <span className="block font-bold">{title}</span>
        <span className="block text-sm text-dim">{sub}</span>
      </span>
      {badge}
      <span className="text-faint">
        <ChevronRight size={20} />
      </span>
    </Card>
  )
}
