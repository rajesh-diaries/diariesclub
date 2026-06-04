import { useState } from 'react'
import { Button } from '../components/ui'
import { useAuth } from '../state/auth'

/** Venue sign-in on a staff phone. Each phone signs in once to its venue;
 *  individual staff then identify themselves per-action with their PIN. */
export function LoginScreen() {
  const { signIn, deviceError, signOut } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      await signIn(email, password)
    } catch {
      setError('Wrong email or password.')
      setBusy(false)
    }
  }

  // Signed in, but the device row is inactive/missing → revoked from admin.
  if (deviceError === 'revoked') {
    return (
      <div className="flex min-h-full flex-col items-center justify-center gap-4 px-8 text-center">
        <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-danger/15 text-danger text-3xl font-black">
          !
        </div>
        <h1 className="text-2xl font-black">This phone is deactivated</h1>
        <p className="max-w-xs text-dim">
          Its access was turned off from the admin console. Ask a manager to
          re-activate this phone, then sign in again.
        </p>
        <Button variant="surface" onClick={signOut} className="mt-2">
          Sign out
        </Button>
      </div>
    )
  }

  return (
    <div className="flex min-h-full flex-col justify-center px-6 pb-12">
      <div className="mx-auto w-full max-w-sm">
        {/* Brand mark */}
        <div className="mb-8 flex flex-col items-center gap-3">
          <div className="flex h-20 w-20 items-center justify-center rounded-[1.5rem] bg-gradient-to-br from-[#1B2A6B] via-[#2C3FA0] to-primary text-3xl font-black tracking-tight text-white shadow-2xl">
            PD
          </div>
          <div className="text-center">
            <h1 className="text-2xl font-black tracking-tight">
              Play Diaries
            </h1>
            <p className="text-sm font-semibold text-faint">
              Staff console
            </p>
          </div>
        </div>

        <form onSubmit={submit} className="flex flex-col gap-3">
          <Field
            label="Venue email"
            value={email}
            onChange={setEmail}
            type="email"
            placeholder="you@venue.email"
            autoComplete="username"
          />
          <Field
            label="Password"
            value={password}
            onChange={setPassword}
            type="password"
            placeholder="••••••••"
            autoComplete="current-password"
          />
          {error && (
            <p className="text-center text-sm font-semibold text-danger">
              {error}
            </p>
          )}
          <Button
            type="submit"
            loading={busy}
            disabled={!email || !password}
            className="mt-2"
          >
            Sign in
          </Button>
        </form>

        <p className="mt-8 text-center text-xs text-faint">
          Sign in once on this phone. Each staff verifies with their own PIN
          per action.
        </p>
      </div>
    </div>
  )
}

function Field({
  label,
  value,
  onChange,
  type,
  placeholder,
  autoComplete,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  type: string
  placeholder?: string
  autoComplete?: string
}) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="px-1 text-xs font-bold uppercase tracking-wider text-faint">
        {label}
      </span>
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        type={type}
        placeholder={placeholder}
        autoComplete={autoComplete}
        autoCapitalize="none"
        className="rounded-2xl border border-line bg-surface-2 px-4 py-4 text-[1.0625rem] text-text placeholder:text-faint focus:border-primary focus:outline-none"
      />
    </label>
  )
}
