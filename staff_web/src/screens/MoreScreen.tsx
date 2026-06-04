import { useNavigate } from 'react-router-dom'
import { Header, Page } from '../components/Shell'
import { Card, Pill } from '../components/ui'
import {
  CashIcon,
  QrIcon,
  TagIcon,
  SparkIcon,
  CoinsIcon,
  UsersIcon,
  ChevronRight,
  SignOutIcon,
} from '../components/icons'
import { useAuth } from '../state/auth'
import {
  usePendingCounterPayments,
  usePendingHealthyBites,
} from '../hooks/useVenueData'

export function MoreScreen() {
  const nav = useNavigate()
  const { venueLabel, signOut } = useAuth()
  const pay = usePendingCounterPayments()
  const bites = usePendingHealthyBites()
  const payCount = pay.data?.length ?? 0
  const biteCount = bites.data?.length ?? 0

  const items = [
    {
      icon: <CashIcon size={24} />,
      title: 'Pending payments',
      sub: 'Collect ‘pay at counter’ dues',
      to: '/pay',
      badge: payCount > 0 ? <Pill tone="gold">{payCount}</Pill> : undefined,
    },
    {
      icon: <QrIcon size={24} />,
      title: 'Scan QR',
      sub: 'Check a child in by scanning',
      to: '/scan',
    },
    {
      icon: <UsersIcon size={24} />,
      title: 'New walk-in',
      sub: 'Register an app-less customer',
      to: '/walkin',
    },
    {
      icon: <SparkIcon size={24} />,
      title: 'Healthy bites',
      sub: 'Hand out complimentary snacks',
      to: '/bites',
      badge: biteCount > 0 ? <Pill tone="gold">{biteCount}</Pill> : undefined,
    },
    {
      icon: <TagIcon size={24} />,
      title: 'Sold out',
      sub: 'Turn menu items on / off',
      to: '/menu',
    },
    {
      icon: <SparkIcon size={24} />,
      title: 'Workshops',
      sub: 'Mark attendance',
      to: '/workshops',
    },
    {
      icon: <CoinsIcon size={24} />,
      title: 'Rewards',
      sub: 'Redeem perks · surprise cards',
      to: '/rewards',
    },
  ]

  return (
    <>
      <Header subtitle={venueLabel} title="More tools" />
      <Page>
        {items.map((it) => (
          <Card
            key={it.to}
            onClick={() => nav(it.to)}
            className="mb-3 flex items-center gap-4 p-4"
          >
            <span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-surface-2 text-primary">
              {it.icon}
            </span>
            <span className="flex-1">
              <span className="block font-bold">{it.title}</span>
              <span className="block text-sm text-dim">{it.sub}</span>
            </span>
            {it.badge}
            <span className="text-faint">
              <ChevronRight size={20} />
            </span>
          </Card>
        ))}

        <button
          onClick={signOut}
          className="mx-auto mt-4 flex items-center gap-2 rounded-full px-4 py-2 text-sm font-semibold text-faint active:bg-surface-2"
        >
          <SignOutIcon size={16} /> Sign out this phone
        </button>
      </Page>
    </>
  )
}
