import {
  createContext,
  useCallback,
  useContext,
  useState,
  type ButtonHTMLAttributes,
  type ReactNode,
} from 'react'

/* ── Button ─────────────────────────────────────────────────────────── */
type Variant = 'primary' | 'ghost' | 'surface' | 'danger' | 'gold'
const variants: Record<Variant, string> = {
  primary:
    'bg-primary text-white active:bg-primary-press shadow-[0_8px_24px_-8px_rgba(79,124,255,0.7)]',
  gold: 'bg-gold text-ink active:brightness-95',
  surface: 'bg-surface-2 text-text border border-line active:bg-line',
  ghost: 'bg-transparent text-dim active:bg-surface-2',
  danger: 'bg-danger/15 text-danger border border-danger/30 active:bg-danger/25',
}

export function Button({
  variant = 'primary',
  loading,
  icon,
  children,
  className = '',
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: Variant
  loading?: boolean
  icon?: ReactNode
}) {
  return (
    <button
      {...rest}
      disabled={rest.disabled || loading}
      className={`relative flex items-center justify-center gap-2 rounded-2xl px-5 py-4 text-[1.0625rem] font-bold leading-none transition-[transform,background] duration-100 active:scale-[0.98] disabled:opacity-40 disabled:active:scale-100 ${variants[variant]} ${className}`}
    >
      {loading ? <Spinner size={18} /> : icon}
      {children}
    </button>
  )
}

/* ── Spinner ────────────────────────────────────────────────────────── */
export function Spinner({ size = 22 }: { size?: number }) {
  return (
    <span
      className="spin inline-block rounded-full border-2 border-current border-t-transparent opacity-80"
      style={{ width: size, height: size }}
    />
  )
}

/* ── Card ───────────────────────────────────────────────────────────── */
export function Card({
  children,
  className = '',
  onClick,
}: {
  children: ReactNode
  className?: string
  onClick?: () => void
}) {
  return (
    <div
      onClick={onClick}
      className={`rounded-[1.25rem] border border-line bg-surface/80 backdrop-blur-sm ${
        onClick ? 'cursor-pointer active:scale-[0.99] transition-transform' : ''
      } ${className}`}
    >
      {children}
    </div>
  )
}

/* ── Badge / pill ───────────────────────────────────────────────────── */
export function Pill({
  children,
  tone = 'dim',
  className = '',
}: {
  children: ReactNode
  tone?: 'dim' | 'active' | 'grace' | 'primary' | 'gold' | 'danger'
  className?: string
}) {
  const tones: Record<string, string> = {
    dim: 'bg-surface-2 text-dim',
    active: 'bg-active/15 text-active',
    grace: 'bg-grace/15 text-grace',
    primary: 'bg-primary/15 text-primary',
    gold: 'bg-gold/15 text-gold',
    danger: 'bg-danger/15 text-danger',
  }
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-bold ${tones[tone]} ${className}`}
    >
      {children}
    </span>
  )
}

/* ── Empty state ────────────────────────────────────────────────────── */
export function Empty({
  icon,
  title,
  hint,
}: {
  icon?: ReactNode
  title: string
  hint?: string
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 px-8 py-16 text-center">
      {icon && <div className="text-faint">{icon}</div>}
      <p className="text-lg font-semibold text-dim">{title}</p>
      {hint && <p className="max-w-xs text-sm text-faint">{hint}</p>}
    </div>
  )
}

/* ── Toast ──────────────────────────────────────────────────────────── */
type Toast = { id: number; msg: string; tone: 'ok' | 'err' }
const ToastCtx = createContext<(msg: string, tone?: 'ok' | 'err') => void>(
  () => {},
)
export const useToast = () => useContext(ToastCtx)

export function ToastHost({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])
  const push = useCallback((msg: string, tone: 'ok' | 'err' = 'ok') => {
    const id = Date.now() + Math.floor(performance.now())
    setToasts((t) => [...t, { id, msg, tone }])
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 2600)
  }, [])
  return (
    <ToastCtx.Provider value={push}>
      {children}
      <div className="pointer-events-none fixed inset-x-0 top-0 z-50 flex flex-col items-center gap-2 px-4 pt-[max(env(safe-area-inset-top),0.75rem)]">
        {toasts.map((t) => (
          <div
            key={t.id}
            className={`animate-rise pointer-events-auto w-full max-w-sm rounded-2xl border px-4 py-3 text-center text-sm font-semibold shadow-2xl backdrop-blur-md ${
              t.tone === 'ok'
                ? 'border-active/30 bg-active/15 text-active'
                : 'border-danger/30 bg-danger/15 text-danger'
            }`}
          >
            {t.msg}
          </div>
        ))}
      </div>
    </ToastCtx.Provider>
  )
}
