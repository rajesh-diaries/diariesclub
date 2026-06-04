import { useEffect, type ReactNode } from 'react'
import { CloseIcon } from './icons'

/** A bottom sheet modal: rises from the bottom, dims the backdrop, taps
 *  outside to dismiss. The workhorse container for staff actions. */
export function Sheet({
  open,
  onClose,
  title,
  children,
}: {
  open: boolean
  onClose: () => void
  title?: string
  children: ReactNode
}) {
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])

  if (!open) return null
  return (
    <div className="fixed inset-0 z-40 flex flex-col justify-end">
      <div
        className="absolute inset-0 bg-black/60 backdrop-blur-[2px]"
        onClick={onClose}
      />
      <div className="animate-sheet relative max-h-[92vh] overflow-y-auto rounded-t-[1.75rem] border-t border-line bg-surface pb-[max(env(safe-area-inset-bottom),1.25rem)] shadow-2xl">
        <div className="sticky top-0 z-10 flex items-center justify-between rounded-t-[1.75rem] bg-surface/95 px-5 pb-3 pt-4 backdrop-blur">
          <div className="absolute left-1/2 top-2 h-1 w-10 -translate-x-1/2 rounded-full bg-line" />
          <h2 className="text-lg font-extrabold tracking-tight">{title}</h2>
          <button
            onClick={onClose}
            className="rounded-full p-1.5 text-faint active:bg-surface-2"
          >
            <CloseIcon size={22} />
          </button>
        </div>
        <div className="px-5 pt-1">{children}</div>
      </div>
    </div>
  )
}
