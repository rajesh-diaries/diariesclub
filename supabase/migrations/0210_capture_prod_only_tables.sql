-- 0210_capture_prod_only_tables.sql
-- REPO/PROD CONVERGENCE — capture three tables that exist in prod but have no CREATE
-- statement anywhere in the migrations repo, so a from-scratch replay reproduces them.
--
-- These tables were created by migrations that were applied to prod but never committed
-- as files:
--     notification_templates    (prod ledger: 0142_notification_templates)
--     family_devices            (prod ledger: multi_device_push_family_devices)
--     saved_birthday_packages   (prod ledger: birthday_flow_v2_schema)
--
-- Definitions below were reconstructed from the LIVE prod schema (read-only) on
-- 2026-07-03: exact column types/defaults, constraints, indexes, RLS state and policies.
--
-- IDEMPOTENT: on prod (where these already exist) every statement is a no-op
-- (CREATE TABLE/INDEX IF NOT EXISTS; ENABLE RLS is a no-op when already on; policies are
-- dropped-if-exists then recreated identically inside the migration's transaction).
--
-- ORDERING NOTE: appended at 0210 rather than the original historical position. All FK
-- targets (families, admin_users, birthday_packages) are created much earlier, and the
-- plpgsql sender functions that read notification_templates resolve table references at
-- run time, not at CREATE FUNCTION time — so replay ordering is safe.
--
-- DATA NOTE: this migration captures STRUCTURE ONLY. notification_templates holds 47 rows
-- of app-critical config in prod that is NOT seeded here (see accompanying review note);
-- family_devices (25 rows) and saved_birthday_packages (0 rows) are runtime user data and
-- are intentionally not seeded.

-- ─────────────────────────────────────────────────────────────────────────────
-- notification_templates  (PK on `type`; admin-only SELECT; writes via SECURITY DEFINER RPCs)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.notification_templates (
  type                  text        NOT NULL,
  category              text        NOT NULL,
  enabled               boolean     NOT NULL DEFAULT true,
  title                 text        NOT NULL,
  body                  text        NOT NULL,
  deep_link_template    text,
  timing_offset_minutes integer,
  variables             jsonb       NOT NULL DEFAULT '[]'::jsonb,
  preference_key        text        NOT NULL,
  description           text,
  updated_at            timestamptz NOT NULL DEFAULT now(),
  updated_by            uuid,
  variants              jsonb,
  ttl_seconds           integer,
  CONSTRAINT notification_templates_pkey PRIMARY KEY (type),
  CONSTRAINT notification_templates_updated_by_fkey
    FOREIGN KEY (updated_by) REFERENCES public.admin_users(id)
);

ALTER TABLE public.notification_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notification_templates_admin_select ON public.notification_templates;
CREATE POLICY notification_templates_admin_select
  ON public.notification_templates
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.admin_users
     WHERE admin_users.auth_user_id = auth.uid()
       AND admin_users.is_active = true
  ));

-- ─────────────────────────────────────────────────────────────────────────────
-- family_devices  (one row per FCM token; owner-read RLS keyed on family_id = auth.uid())
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.family_devices (
  id           uuid        NOT NULL DEFAULT gen_random_uuid(),
  family_id    uuid        NOT NULL,
  fcm_token    text        NOT NULL,
  platform     text        NOT NULL,
  app_version  text,
  device_label text,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at   timestamptz NOT NULL DEFAULT now(),
  is_active    boolean     NOT NULL DEFAULT true,
  CONSTRAINT family_devices_pkey PRIMARY KEY (id),
  CONSTRAINT family_devices_fcm_token_key UNIQUE (fcm_token),
  CONSTRAINT family_devices_family_id_fkey
    FOREIGN KEY (family_id) REFERENCES public.families(id) ON DELETE CASCADE,
  CONSTRAINT family_devices_platform_check
    CHECK (platform = ANY (ARRAY['ios'::text, 'android'::text, 'web'::text]))
);

CREATE INDEX IF NOT EXISTS family_devices_family_active_idx
  ON public.family_devices USING btree (family_id) WHERE is_active;

ALTER TABLE public.family_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS family_devices_owner_read ON public.family_devices;
CREATE POLICY family_devices_owner_read
  ON public.family_devices
  FOR SELECT
  USING (family_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- saved_birthday_packages  (owner full-access RLS; unique per (family_id, package_id))
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.saved_birthday_packages (
  id          uuid        NOT NULL DEFAULT gen_random_uuid(),
  family_id   uuid        NOT NULL,
  package_id  uuid        NOT NULL,
  saved_at    timestamptz NOT NULL DEFAULT now(),
  reminded_at timestamptz,
  CONSTRAINT saved_birthday_packages_pkey PRIMARY KEY (id),
  CONSTRAINT saved_birthday_packages_family_id_package_id_key UNIQUE (family_id, package_id),
  CONSTRAINT saved_birthday_packages_family_id_fkey
    FOREIGN KEY (family_id) REFERENCES public.families(id) ON DELETE CASCADE,
  CONSTRAINT saved_birthday_packages_package_id_fkey
    FOREIGN KEY (package_id) REFERENCES public.birthday_packages(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS saved_birthday_packages_family_idx
  ON public.saved_birthday_packages USING btree (family_id);
CREATE INDEX IF NOT EXISTS saved_birthday_packages_reminder_idx
  ON public.saved_birthday_packages USING btree (saved_at) WHERE (reminded_at IS NULL);

ALTER TABLE public.saved_birthday_packages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS saved_birthday_packages_owner ON public.saved_birthday_packages;
CREATE POLICY saved_birthday_packages_owner
  ON public.saved_birthday_packages
  FOR ALL
  USING (family_id = auth.uid())
  WITH CHECK (family_id = auth.uid());
