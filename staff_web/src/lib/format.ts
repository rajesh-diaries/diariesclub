// Money is stored in paise server-side. Display in ₹ with Indian grouping.
export function rupees(paise: number | null | undefined): string {
  const v = Math.round((paise ?? 0) / 100)
  return '₹' + v.toLocaleString('en-IN')
}

// Normalize a typed Indian number to E.164 (+91XXXXXXXXXX), or null.
export function toE164(raw: string): string | null {
  const digits = raw.replace(/\D/g, '')
  const ten = digits.length > 10 ? digits.slice(-10) : digits
  if (ten.length !== 10 || !/^[6-9]/.test(ten)) return null
  return '+91' + ten
}

// Remaining time until an ISO instant, in whole seconds (can go negative).
export function secondsUntil(iso: string, nowMs = Date.now()): number {
  return Math.round((new Date(iso).getTime() - nowMs) / 1000)
}

// Format a signed second count as M:SS or H:MM:SS, with an optional sign.
export function clock(totalSeconds: number, showSign = false): string {
  const sign = totalSeconds < 0 ? '+' : showSign ? '' : ''
  const s = Math.abs(totalSeconds)
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = s % 60
  const mm = String(m).padStart(2, '0')
  const ss = String(sec).padStart(2, '0')
  return h > 0 ? `${sign}${h}:${mm}:${ss}` : `${sign}${m}:${ss}`
}

// Human relative time for "last visit", order age, etc.
export function relativeFrom(iso: string | null | undefined): string {
  if (!iso) return '—'
  const diff = Date.now() - new Date(iso).getTime()
  const m = Math.floor(diff / 60000)
  if (m < 1) return 'just now'
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  const d = Math.floor(h / 24)
  if (d < 7) return `${d}d ago`
  if (d < 30) return `${Math.floor(d / 7)}w ago`
  if (d < 365) return `${Math.floor(d / 30)}mo ago`
  return `${Math.floor(d / 365)}y ago`
}

// Minutes elapsed since an ISO instant (for KDS order age).
export function minutesSince(iso: string): number {
  return Math.floor((Date.now() - new Date(iso).getTime()) / 60000)
}
