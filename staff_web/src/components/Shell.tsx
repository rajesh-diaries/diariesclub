import type { ReactNode } from 'react'
import { NavLink, useLocation, useNavigate } from 'react-router-dom'
import {
  HomeIcon,
  SessionsIcon,
  KitchenIcon,
  CheckInIcon,
  MoreIcon,
} from './icons'

/** Page scroll area sized to sit above the bottom nav. */
export function Page({
  children,
  className = '',
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <div
      className={`mx-auto min-h-full w-full max-w-md flex-1 px-4 pb-28 ${className}`}
    >
      {children}
    </div>
  )
}

/** App header: venue name + an optional right slot (e.g. refresh). */
export function Header({
  title,
  subtitle,
  right,
}: {
  title: string
  subtitle?: string
  right?: ReactNode
}) {
  return (
    <header className="pt-safe sticky top-0 z-20 mx-auto flex w-full max-w-md items-end justify-between gap-3 bg-ink/70 px-4 pb-3 pt-2 backdrop-blur-md">
      <div className="min-w-0">
        {subtitle && (
          <p className="truncate text-xs font-semibold uppercase tracking-wider text-faint">
            {subtitle}
          </p>
        )}
        <h1 className="truncate text-2xl font-black tracking-tight">{title}</h1>
      </div>
      {right}
    </header>
  )
}

const leftTabs = [
  { to: '/', label: 'Home', icon: HomeIcon, end: true },
  { to: '/live', label: 'Live', icon: SessionsIcon, end: false },
]
const rightTabs = [
  { to: '/kitchen', label: 'Kitchen', icon: KitchenIcon, end: false },
  { to: '/more', label: 'More', icon: MoreIcon, end: false },
]

export function BottomNav() {
  const nav = useNavigate()
  const loc = useLocation()
  return (
    <nav className="pb-safe fixed inset-x-0 bottom-0 z-30 mx-auto w-full max-w-md">
      <div className="relative mx-3 mb-1 flex items-center justify-around rounded-[1.5rem] border border-line bg-surface/90 px-2 py-2 shadow-2xl backdrop-blur-xl">
        {leftTabs.map((t) => (
          <Tab key={t.to} {...t} />
        ))}

        {/* Raised primary action: the most-used flow lives dead-center. */}
        <button
          onClick={() => nav('/checkin')}
          className={`relative -mt-8 flex h-16 w-16 flex-col items-center justify-center rounded-2xl bg-primary text-white shadow-[0_10px_28px_-6px_rgba(79,124,255,0.8)] transition-transform active:scale-95 ${
            loc.pathname.startsWith('/checkin') ? 'ring-4 ring-primary/30' : ''
          }`}
          aria-label="Check in"
        >
          <CheckInIcon size={26} />
          <span className="mt-0.5 text-[10px] font-bold">Check-in</span>
        </button>

        {rightTabs.map((t) => (
          <Tab key={t.to} {...t} />
        ))}
      </div>
    </nav>
  )
}

function Tab({
  to,
  label,
  icon: Icon,
  end,
}: {
  to: string
  label: string
  icon: (p: { size?: number }) => ReactNode
  end: boolean
}) {
  return (
    <NavLink
      to={to}
      end={end}
      className="flex w-16 flex-col items-center gap-1 py-1.5"
    >
      {({ isActive }) => (
        <>
          <span className={isActive ? 'text-primary' : 'text-faint'}>
            <Icon size={24} />
          </span>
          <span
            className={`text-[10px] font-bold ${
              isActive ? 'text-primary' : 'text-faint'
            }`}
          >
            {label}
          </span>
        </>
      )}
    </NavLink>
  )
}
