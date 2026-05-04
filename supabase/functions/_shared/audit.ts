// ===========================================================================
//  Audit log helpers. Edge Functions are `actor_type='system'`. Pass a
//  `slug` (e.g. 'razorpay.webhook.payment_captured', 'cron.birthday.run')
//  matching the project-wide convention.
// ===========================================================================

import { admin } from "./admin.ts";

export interface AuditOpts {
  action: string;
  entityType?: string;
  entityId?: string | null;
  venueId?: string | null;
  oldValue?: Record<string, unknown> | null;
  newValue?: Record<string, unknown> | null;
}

export async function audit(opts: AuditOpts): Promise<void> {
  try {
    await admin.from("audit_log").insert({
      actor_type: "system",
      actor_id: null,
      action: opts.action,
      entity_type: opts.entityType ?? "edge_function",
      entity_id: opts.entityId ?? null,
      venue_id: opts.venueId ?? null,
      old_value: opts.oldValue ?? null,
      new_value: opts.newValue ?? null,
    });
  } catch (e) {
    // Audit failure should never block the operation. Log + continue.
    console.error("audit_insert_failed", opts.action, e);
  }
}
