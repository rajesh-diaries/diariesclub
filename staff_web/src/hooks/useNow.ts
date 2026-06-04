import { useEffect, useState } from 'react'

/** A ticking clock (ms). Drives live countdowns without per-component timers
 *  drifting apart. Default cadence 1s. */
export function useNow(intervalMs = 1000): number {
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), intervalMs)
    return () => clearInterval(t)
  }, [intervalMs])
  return now
}
