import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { BrowserQRCodeReader, type IScannerControls } from '@zxing/browser'
import { Header, Page } from '../components/Shell'
import { Button, Card, Spinner, useToast } from '../components/ui'
import { useActor } from '../components/Actor'
import { QrIcon, CheckInIcon } from '../components/icons'
import { rpc } from '../lib/supabase'

type Phase = 'starting' | 'scanning' | 'validating' | 'denied' | 'done'

/** Scan the QR a parent shows after tapping "start play session" in their
 *  app. Decodes with the camera, then validates server-side. */
export function ScanScreen() {
  const nav = useNavigate()
  const toast = useToast()
  const requireActor = useActor().requireActor

  const videoRef = useRef<HTMLVideoElement>(null)
  const controlsRef = useRef<IScannerControls | null>(null)
  const handledRef = useRef(false)
  const [phase, setPhase] = useState<Phase>('starting')
  const [result, setResult] = useState<string | null>(null)

  useEffect(() => {
    const reader = new BrowserQRCodeReader()
    let stopped = false

    reader
      .decodeFromVideoDevice(undefined, videoRef.current!, (res, _err, controls) => {
        controlsRef.current = controls
        if (stopped) {
          controls.stop()
          return
        }
        if (phase === 'starting') setPhase('scanning')
        if (res && !handledRef.current) {
          handledRef.current = true
          controls.stop()
          onCode(res.getText())
        }
      })
      .catch(() => setPhase('denied'))

    return () => {
      stopped = true
      controlsRef.current?.stop()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  async function onCode(payload: string) {
    setPhase('validating')
    // Attribute the scan to the operating staff account (no PIN).
    const staff = await requireActor()
    if (!staff) {
      // No staff resolved — allow another scan.
      handledRef.current = false
      setPhase('scanning')
      restart()
      return
    }
    try {
      await rpc('qr_scan_validate', {
        p_qr_payload: payload,
        p_staff_pin_id: staff.staffId,
      })
      setPhase('done')
      setResult('Checked in — session is now live.')
      toast('Checked in ✓', 'ok')
      setTimeout(() => nav('/live'), 1200)
    } catch (err: any) {
      const msg = String(err?.message ?? '')
      setResult(
        msg.includes('expired')
          ? 'That QR has expired — ask them to reopen it.'
          : msg.includes('not_found') || msg.includes('invalid')
            ? "That QR isn't valid. Try the manual check-in."
            : "Couldn't check in from that code.",
      )
      setPhase('done')
      toast('Scan failed', 'err')
    }
  }

  function restart() {
    handledRef.current = false
    setResult(null)
    setPhase('starting')
    const reader = new BrowserQRCodeReader()
    reader
      .decodeFromVideoDevice(undefined, videoRef.current!, (res, _e, controls) => {
        controlsRef.current = controls
        setPhase('scanning')
        if (res && !handledRef.current) {
          handledRef.current = true
          controls.stop()
          onCode(res.getText())
        }
      })
      .catch(() => setPhase('denied'))
  }

  return (
    <>
      <Header subtitle="Front desk" title="Scan QR" />
      <Page>
        {phase === 'denied' ? (
          <Card className="p-6 text-center">
            <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-danger/15 text-danger">
              <QrIcon size={28} />
            </div>
            <p className="text-lg font-bold">Camera not available</p>
            <p className="mt-1 text-sm text-dim">
              Allow camera access for this site, or use manual check-in instead.
            </p>
            <Button
              variant="surface"
              onClick={() => nav('/checkin')}
              icon={<CheckInIcon size={18} />}
              className="mt-4 w-full"
            >
              Manual check-in
            </Button>
          </Card>
        ) : (
          <>
            <div className="relative mx-auto aspect-square w-full max-w-sm overflow-hidden rounded-[1.5rem] border border-line bg-black">
              <video
                ref={videoRef}
                className="h-full w-full object-cover"
                muted
                playsInline
              />
              {/* Reticle */}
              <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
                <div className="h-56 w-56 rounded-3xl border-4 border-white/80 shadow-[0_0_0_2000px_rgba(0,0,0,0.45)]" />
              </div>
              {(phase === 'starting' || phase === 'validating') && (
                <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 bg-black/40 text-white">
                  <Spinner size={26} />
                  <p className="text-sm font-semibold">
                    {phase === 'validating' ? 'Checking in…' : 'Starting camera…'}
                  </p>
                </div>
              )}
            </div>

            {result ? (
              <Card className="mt-4 p-4 text-center">
                <p className="font-semibold">{result}</p>
                <Button
                  variant="surface"
                  onClick={restart}
                  className="mt-3 w-full"
                >
                  Scan another
                </Button>
              </Card>
            ) : (
              <p className="mt-4 text-center text-sm text-dim">
                Point at the QR the parent shows after starting a session.
              </p>
            )}

            <Button
              variant="ghost"
              onClick={() => nav('/checkin')}
              className="mx-auto mt-3"
            >
              Enter phone instead
            </Button>
          </>
        )}
      </Page>
    </>
  )
}
