// ===========================================================================
//  Diaries Club — send-push Edge Function (Session 13)
//
//  FCM HTTP v1 API. Replaces the legacy server-key approach. Uses a
//  Firebase service account JSON (FCM_SERVICE_ACCOUNT_JSON secret) to
//  mint a short-lived OAuth2 access token, then POSTs to the v1 send
//  endpoint.
//
//  Called by the notify_push_dispatch trigger (pg_net.http_post) on
//  every notifications.INSERT. Trigger lives in migration 0017 and is
//  enabled in 0018 once this function is deployed.
//
//  Wire format
//  -----------
//    POST {
//      notification_id, family_id, type, title, body,
//      deep_link?, reference_id?, metadata?
//    }
//      → { ok: true, dispatched: true|false, reason? }
//
//  Auth: service-role bearer (the trigger sets it from app.service_role_key
//  GUC).
//
//  Behaviour:
//    - Resolves family.fcm_token + notification_preferences
//    - Checks per-category preference (returns push_status='skipped'
//      with reason='preference_disabled' if blocked)
//    - Sends via FCM v1
//    - On NotRegistered / InvalidArgument with token error → clears
//      families.fcm_token so we stop sending stale-token pushes
//    - Updates notifications.push_status to dispatched / failed / skipped
//    - Audit log per send (dispatched + failed paths)
// ===========================================================================

import { admin } from "./_shared/admin.ts";
import { requireServiceRole } from "./_shared/auth.ts";
import { audit } from "./_shared/audit.ts";
import {
  corsPreflight,
  errorResponse,
  jsonResponse,
} from "./_shared/response.ts";
import { captureException, captureMessage } from "./_shared/sentry.ts";

const FCM_SERVICE_ACCOUNT_JSON = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "";

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
  token_uri: string;
}

let cachedServiceAccount: ServiceAccount | null = null;
function loadServiceAccount(): ServiceAccount {
  if (cachedServiceAccount) return cachedServiceAccount;
  if (!FCM_SERVICE_ACCOUNT_JSON) {
    throw new Error("FCM_SERVICE_ACCOUNT_JSON not configured");
  }
  try {
    cachedServiceAccount = JSON.parse(FCM_SERVICE_ACCOUNT_JSON) as ServiceAccount;
    if (!cachedServiceAccount.client_email || !cachedServiceAccount.private_key) {
      throw new Error("incomplete service account JSON");
    }
    return cachedServiceAccount;
  } catch (e) {
    throw new Error(`bad FCM_SERVICE_ACCOUNT_JSON: ${(e as Error).message}`);
  }
}

// ── OAuth access-token cache ─────────────────────────────────────────────
// Google grants ~3600s access tokens. We re-use until 5 min before expiry.
let cachedAccessToken: { token: string; expiresAt: number } | null = null;

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && cachedAccessToken.expiresAt > now + 300) {
    return cachedAccessToken.token;
  }

  const sa = loadServiceAccount();
  const jwt = await signJwt(sa);

  const tokenRes = await fetch(sa.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!tokenRes.ok) {
    const detail = await tokenRes.text();
    throw new Error(`oauth_token_exchange_failed: ${detail}`);
  }

  const body = await tokenRes.json() as { access_token: string; expires_in: number };
  cachedAccessToken = {
    token: body.access_token,
    expiresAt: now + body.expires_in,
  };
  return body.access_token;
}

async function signJwt(sa: ServiceAccount): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: sa.token_uri,
    iat: now,
    exp: now + 3600,
  };

  const encode = (obj: Record<string, unknown>) =>
    base64UrlEncode(new TextEncoder().encode(JSON.stringify(obj)));

  const unsigned = `${encode(header)}.${encode(claims)}`;
  const key = await importPrivateKey(sa.private_key);
  const sig = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    key,
    new TextEncoder().encode(unsigned),
  );
  return `${unsigned}.${base64UrlEncode(new Uint8Array(sig))}`;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(cleaned), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

function base64UrlEncode(input: Uint8Array): string {
  let binary = "";
  for (const byte of input) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

// ── Notification-preference gate ─────────────────────────────────────────
function isAllowedByPreferences(
  type: string,
  prefs: Record<string, boolean> | null,
): boolean {
  if (!prefs) return true;
  if (
    type.startsWith("session_") ||
    type === "grace_started" ||
    type === "extend_nudge" ||
    type === "hydration_nudge" ||
    type === "session_closed" ||
    type === "recap_ready" ||
    type === "reflection_prompt" ||
    type === "reflection_auto_split"
  ) {
    return prefs.session_reminders ?? true;
  }
  if (
    type === "stage_transition_revealed" ||
    type === "stage_transition_imminent" ||
    type === "level_up" ||
    type === "hero_card_received"
  ) {
    return prefs.hero_progression ?? true;
  }
  if (type.startsWith("birthday_")) {
    return prefs.birthday_reminders ?? true;
  }
  if (type === "order_confirmed" || type === "order_ready") {
    return prefs.order_status ?? true;
  }
  if (type === "wallet_topup" || type === "wallet_low_balance" || type === "refund_processed") {
    return prefs.wallet_alerts ?? true;
  }
  return prefs.marketing ?? true;
}

// ── push_status updates ──────────────────────────────────────────────────
async function markStatus(
  notificationId: string,
  status: "dispatched" | "failed" | "skipped",
  reason?: string,
) {
  const update: Record<string, unknown> = {
    push_status: status,
  };
  if (status === "dispatched") {
    update.push_sent_at = new Date().toISOString();
  }
  if (reason) {
    update.push_failure_reason = reason;
  }
  await admin.from("notifications").update(update).eq("id", notificationId);
}

interface PushRequest {
  notification_id: string;
  family_id: string;
  type: string;
  title: string;
  body: string;
  deep_link?: string;
  reference_id?: string;
  metadata?: Record<string, unknown>;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "method_not_allowed" });
  }

  let payload: PushRequest;
  try {
    requireServiceRole(req);
    payload = await req.json() as PushRequest;
  } catch (e) {
    return errorResponse(e);
  }

  try {
    const { data: family } = await admin
      .from("families")
      .select("fcm_token, fcm_platform, notification_preferences, is_anonymised, deleted_at")
      .eq("id", payload.family_id)
      .single();

    if (!family || family.is_anonymised || family.deleted_at) {
      await markStatus(payload.notification_id, "skipped", "family_inactive");
      return jsonResponse(200, { ok: true, dispatched: false, reason: "family_inactive" });
    }

    if (!family.fcm_token) {
      await markStatus(payload.notification_id, "skipped", "no_token");
      return jsonResponse(200, { ok: true, dispatched: false, reason: "no_token" });
    }

    if (!isAllowedByPreferences(
      payload.type,
      family.notification_preferences as Record<string, boolean> | null,
    )) {
      await markStatus(payload.notification_id, "skipped", "preference_disabled");
      return jsonResponse(200, {
        ok: true,
        dispatched: false,
        reason: "preference_disabled",
      });
    }

    // Per-type TTL — drives FCM's android.ttl + apns-expiration so a
    // session_started undelivered for 30 min is dropped rather than
    // popping up much later. NULL → carrier default (~4 weeks).
    const { data: tmpl } = await admin
      .from("notification_templates")
      .select("ttl_seconds")
      .eq("type", payload.type)
      .maybeSingle();
    const ttlSeconds = (tmpl as { ttl_seconds?: number | null } | null)
      ?.ttl_seconds ?? null;

    const accessToken = await getAccessToken();
    const sa = loadServiceAccount();

    // The customer app's foreground handler reads suppress_foreground from
    // data; we set it for in-context types so the app doesn't show a
    // banner when the user is already on the relevant screen.
    // session_started is intentionally NOT suppressed — parents often hand
    // the kid to staff and walk away during scan, so the banner serves as
    // a receipt confirming the session is officially running.
    const suppressForeground =
      payload.type === "grace_started" ||
      payload.type === "session_closed" ||
      payload.type === "extend_nudge" ||
      payload.type === "hydration_nudge";

    // Note: the previous version slept 3.5s for session_started to dodge
    // the QR→home transition swallowing the banner on iOS. That delay
    // turned out to be the only thing different about session_started
    // (which kept landing as 'dispatched' but never showed on device)
    // while other types worked. We rely on the foreground-message
    // handler in fcm_setup.dart (`_onForegroundMessage`) +
    // `setForegroundNotificationPresentationOptions` to render the
    // banner regardless of UI state — no server-side delay needed.

    const fcmBody = {
      message: {
        token: family.fcm_token,
        notification: {
          title: payload.title,
          body: payload.body,
        },
        data: {
          type: payload.type,
          deep_link: payload.deep_link ?? "",
          reference_id: payload.reference_id ?? "",
          notification_id: payload.notification_id,
          suppress_foreground: suppressForeground ? "true" : "false",
        },
        android: {
          priority: "HIGH",
          // android.ttl format: "<seconds>s" string. Omitted → ~4 weeks.
          ...(ttlSeconds != null ? { ttl: `${ttlSeconds}s` } : {}),
          notification: {
            channel_id: channelForType(payload.type),
            sound: "default",
          },
        },
        apns: {
          // Explicit headers so APNs (a) treats this as an alert push,
          // not background/silent, and (b) delivers immediately at the
          // highest priority. apns-expiration is the absolute Unix
          // timestamp after which APNs stops trying — 0 means "no store".
          headers: {
            "apns-priority": "10",
            "apns-push-type": "alert",
            ...(ttlSeconds != null
              ? { "apns-expiration":
                    Math.floor(Date.now() / 1000 + ttlSeconds).toString() }
              : {}),
          },
          payload: {
            aps: {
              // Explicit alert block so iOS 26 treats willPresent with
              // a populated UNNotificationContent.title/body even when
              // app is foregrounded. v12 omitted this and relied on FCM
              // to merge `notification` → `aps.alert`; on iOS 26 that
              // merge was inconsistent and the banner failed to show
              // in foreground.
              alert: { title: payload.title, body: payload.body },
              sound: "default",
              badge: 1,
              // Time-sensitive bypasses Focus/Do-Not-Disturb on iOS 15+
              // for the events parents really care about (kid checked
              // in / out, healthy bite ready, grace, hydration). Other
              // types stay at the default level so they don't override
              // user-chosen Focus.
              "interruption-level": [
                "session_started",
                "session_closed",
                "grace_started",
                "extend_nudge",
                "healthy_bite_earned",
                "hydration_nudge",
                "workshop_starting_soon",
                "workshop_attended",
              ].includes(payload.type)
                ? "time-sensitive"
                : "active",
            },
          },
        },
      },
    };

    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(fcmBody),
      },
    );

    if (fcmRes.ok) {
      await markStatus(payload.notification_id, "dispatched");
      await audit({
        action: `fcm.send.${payload.type}`,
        entityType: "notification",
        entityId: payload.notification_id,
      });
      return jsonResponse(200, { ok: true, dispatched: true });
    }

    const errBody = await fcmRes.text();
    let errCode = "unknown";
    try {
      const parsed = JSON.parse(errBody) as { error?: { details?: Array<{ errorCode?: string }> } };
      errCode = parsed.error?.details?.[0]?.errorCode ?? errCode;
    } catch (_) {
      // ignore JSON parse failure; fall through with errCode='unknown'
    }

    // Stale token → clear it so we don't keep sending.
    if (errCode === "UNREGISTERED" || errCode === "INVALID_ARGUMENT") {
      await admin.from("families").update({ fcm_token: null }).eq("id", payload.family_id);
    }

    await markStatus(payload.notification_id, "failed", errCode);
    await captureMessage(`FCM send failed: ${errCode}`, {
      function: "send-push",
      level: "warning",
      extra: {
        notification_id: payload.notification_id,
        type: payload.type,
        body_excerpt: errBody.slice(0, 200),
      },
    });

    // 200 to caller — we've recorded the failure; no point asking pg_net to retry.
    return jsonResponse(200, { ok: true, dispatched: false, reason: errCode });
  } catch (e) {
    await markStatus(payload.notification_id, "failed", "exception").catch(() => {});
    await captureException(e, {
      function: "send-push",
      extra: { notification_id: payload.notification_id },
    });
    return errorResponse(e);
  }
});

function channelForType(type: string): string {
  if (
    type.startsWith("session_") ||
    type === "grace_started" ||
    type === "extend_nudge" ||
    type === "hydration_nudge" ||
    type === "recap_ready" ||
    type === "reflection_prompt" ||
    type === "reflection_auto_split"
  ) {
    return "session";
  }
  if (type.startsWith("birthday_")) return "birthday";
  if (type === "marketing" || type === "topup_offer" || type === "gift_unlocked") {
    return "marketing";
  }
  return "default";
}
