// Crisp line icons as inline SVG — no icon-library dependency, so the PWA
// stays tiny and icons inherit currentColor.
import type { SVGProps } from 'react'

type P = SVGProps<SVGSVGElement> & { size?: number }
function I({ size = 24, children, ...rest }: P & { children: React.ReactNode }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      {...rest}
    >
      {children}
    </svg>
  )
}

export const HomeIcon = (p: P) => (
  <I {...p}>
    <path d="M3 10.5 12 3l9 7.5" />
    <path d="M5 9.5V21h14V9.5" />
  </I>
)
export const CheckInIcon = (p: P) => (
  <I {...p}>
    <circle cx="9" cy="8" r="3.2" />
    <path d="M3.5 20c0-3.3 2.5-5.5 5.5-5.5 1.2 0 2.3.35 3.2.95" />
    <path d="M17 14v6M14 17h6" />
  </I>
)
export const SessionsIcon = (p: P) => (
  <I {...p}>
    <circle cx="12" cy="13" r="8" />
    <path d="M12 13V9" />
    <path d="M9 2h6" />
  </I>
)
export const KitchenIcon = (p: P) => (
  <I {...p}>
    <path d="M6 3v7a2 2 0 0 0 4 0V3M8 10v11" />
    <path d="M16 3c-1.7 0-3 2-3 4.5S14.3 12 16 12v9" />
  </I>
)
export const PlusIcon = (p: P) => (
  <I {...p}>
    <path d="M12 5v14M5 12h14" />
  </I>
)
export const SearchIcon = (p: P) => (
  <I {...p}>
    <circle cx="11" cy="11" r="7" />
    <path d="m20 20-3.2-3.2" />
  </I>
)
export const ChevronRight = (p: P) => (
  <I {...p}>
    <path d="m9 6 6 6-6 6" />
  </I>
)
export const ClockIcon = (p: P) => (
  <I {...p}>
    <circle cx="12" cy="12" r="9" />
    <path d="M12 7v5l3.5 2" />
  </I>
)
export const WalletIcon = (p: P) => (
  <I {...p}>
    <path d="M3 7.5A2.5 2.5 0 0 1 5.5 5H18a2 2 0 0 1 2 2v1" />
    <path d="M3 7.5V18a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-3" />
    <path d="M21 11h-4a2 2 0 0 0 0 4h4z" />
  </I>
)
export const CoinsIcon = (p: P) => (
  <I {...p}>
    <ellipse cx="9" cy="7" rx="6" ry="3" />
    <path d="M3 7v5c0 1.7 2.7 3 6 3" />
    <path d="M3 12v5c0 1.7 2.7 3 6 3 .7 0 1.4-.06 2-.17" />
    <circle cx="16.5" cy="14.5" r="4.5" />
  </I>
)
export const UsersIcon = (p: P) => (
  <I {...p}>
    <circle cx="9" cy="8" r="3.2" />
    <path d="M3.5 20c0-3.3 2.5-5.5 5.5-5.5s5.5 2.2 5.5 5.5" />
    <path d="M16 5.2A3.2 3.2 0 0 1 16 11M18 20c0-2.4-1-4.2-2.6-5.1" />
  </I>
)
export const SparkIcon = (p: P) => (
  <I {...p}>
    <path d="M12 3l1.8 4.7L18.5 9.5 13.8 11.3 12 16l-1.8-4.7L5.5 9.5l4.7-1.8z" />
  </I>
)
export const CloseIcon = (p: P) => (
  <I {...p}>
    <path d="M6 6l12 12M18 6 6 18" />
  </I>
)
export const CheckIcon = (p: P) => (
  <I {...p}>
    <path d="m5 12.5 4.5 4.5L19 6.5" />
  </I>
)
export const ArrowRight = (p: P) => (
  <I {...p}>
    <path d="M4 12h15M13 6l6 6-6 6" />
  </I>
)
export const RefreshIcon = (p: P) => (
  <I {...p}>
    <path d="M4 12a8 8 0 0 1 13.5-5.8L21 9" />
    <path d="M21 4v5h-5" />
    <path d="M20 12a8 8 0 0 1-13.5 5.8L3 15" />
    <path d="M3 20v-5h5" />
  </I>
)
export const SignOutIcon = (p: P) => (
  <I {...p}>
    <path d="M14 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h8" />
    <path d="M17 8l4 4-4 4M21 12H9" />
  </I>
)
export const LockIcon = (p: P) => (
  <I {...p}>
    <rect x="5" y="10" width="14" height="10" rx="2" />
    <path d="M8 10V7a4 4 0 0 1 8 0v3" />
  </I>
)
export const FlameIcon = (p: P) => (
  <I {...p}>
    <path d="M12 3c1 3-2 4-2 7a2 2 0 0 0 4 0c0-.7-.2-1.3-.5-1.8C15.5 10 17 12 17 14.5a5 5 0 1 1-10 0C7 10.5 10.5 8 12 3z" />
  </I>
)
export const CakeIcon = (p: P) => (
  <I {...p}>
    <path d="M4 21h16v-7a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2z" />
    <path d="M4 16c2 0 2 1.4 4 1.4S10 16 12 16s2 1.4 4 1.4 2-1.4 4-1.4" />
    <path d="M12 8V5M8.5 8V6M15.5 8V6" />
  </I>
)
export const CashIcon = (p: P) => (
  <I {...p}>
    <rect x="2" y="6" width="20" height="12" rx="2" />
    <circle cx="12" cy="12" r="2.6" />
    <path d="M6 9v6M18 9v6" />
  </I>
)
export const MoreIcon = (p: P) => (
  <I {...p}>
    <circle cx="5" cy="12" r="1.4" />
    <circle cx="12" cy="12" r="1.4" />
    <circle cx="19" cy="12" r="1.4" />
  </I>
)
export const TagIcon = (p: P) => (
  <I {...p}>
    <path d="M3 11.5V4a1 1 0 0 1 1-1h7.5a2 2 0 0 1 1.4.6l7 7a2 2 0 0 1 0 2.8l-6.5 6.5a2 2 0 0 1-2.8 0l-7-7a2 2 0 0 1-.6-1.4Z" />
    <circle cx="7.5" cy="7.5" r="1.4" />
  </I>
)
export const QrIcon = (p: P) => (
  <I {...p}>
    <rect x="3" y="3" width="7" height="7" rx="1" />
    <rect x="14" y="3" width="7" height="7" rx="1" />
    <rect x="3" y="14" width="7" height="7" rx="1" />
    <path d="M14 14h3v3M21 14v7h-7v-3" />
  </I>
)
export const BellIcon = (p: P) => (
  <I {...p}>
    <path d="M6 9a6 6 0 1 1 12 0c0 5 2 6 2 6H4s2-1 2-6Z" />
    <path d="M10.5 19a2 2 0 0 0 3 0" />
  </I>
)
