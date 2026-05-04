// ===========================================================================
//  Lightweight Sentry shim for Edge Functions.
//
//  Why not the real Sentry Deno SDK? Because import-mapping the SDK in a
//  function bundle adds ~300KB and a cold-start hit, and we only need
//  five capture sites. The shim POSTs directly to the Sentry envelope
//  endpoint — same wire format the real SDK uses, just minimal.
//
//  If SENTRY_DSN is unset the helpers no-op silently (dev / local).
//
//  Every event is auto-tagged:
//    flavor    = 'server'  (matches the customer/staff/admin tag scheme)
//    function  = the slug provided by the caller
//    runtime   = 'edge'
// ===========================================================================

const SENTRY_DSN = Deno.env.get("SENTRY_DSN") ?? "";
const ENV = Deno.env.get("ENV") ?? "unknown";

interface DsnParts {
  publicKey: string;
  host: string;
  projectId: string;
}

let parsed: DsnParts | null = null;
if (SENTRY_DSN) {
  try {
    const url = new URL(SENTRY_DSN);
    parsed = {
      publicKey: url.username,
      host: url.host,
      projectId: url.pathname.replace(/^\//, ""),
    };
  } catch (_) {
    console.warn("sentry: malformed SENTRY_DSN; disabling");
  }
}

function envelopeUrl(): string {
  if (!parsed) return "";
  return `https://${parsed.host}/api/${parsed.projectId}/envelope/`;
}

function authHeader(): string {
  if (!parsed) return "";
  return `Sentry sentry_version=7, sentry_key=${parsed.publicKey}, sentry_client=diariesclub-edge/1.0`;
}

interface SentryContext {
  function: string;
  level?: "fatal" | "error" | "warning" | "info" | "debug";
  extra?: Record<string, unknown>;
}

async function send(eventBody: Record<string, unknown>) {
  if (!parsed) return;
  const eventId = crypto.randomUUID().replaceAll("-", "");
  const url = envelopeUrl();
  const auth = authHeader();
  const header = JSON.stringify({ event_id: eventId, sent_at: new Date().toISOString() });
  const itemHeader = JSON.stringify({ type: "event" });
  const payload = JSON.stringify({ ...eventBody, event_id: eventId });
  const envelope = `${header}\n${itemHeader}\n${payload}`;
  try {
    await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/x-sentry-envelope", "X-Sentry-Auth": auth },
      body: envelope,
    });
  } catch (e) {
    console.error("sentry_send_failed", e);
  }
}

export async function captureException(
  err: unknown,
  ctx: SentryContext,
): Promise<void> {
  const e = err instanceof Error ? err : new Error(String(err));
  await send({
    level: ctx.level ?? "error",
    environment: ENV,
    tags: { flavor: "server", "function": ctx.function, runtime: "edge" },
    extra: ctx.extra,
    exception: {
      values: [{ type: e.name, value: e.message, stacktrace: { frames: parseStack(e.stack) } }],
    },
  });
}

export async function captureMessage(
  message: string,
  ctx: SentryContext,
): Promise<void> {
  await send({
    level: ctx.level ?? "info",
    environment: ENV,
    tags: { flavor: "server", "function": ctx.function, runtime: "edge" },
    extra: ctx.extra,
    message: { formatted: message },
  });
}

function parseStack(stack?: string): unknown[] {
  if (!stack) return [];
  return stack
    .split("\n")
    .slice(1, 11)
    .map((line) => ({ filename: line.trim(), in_app: true }));
}
