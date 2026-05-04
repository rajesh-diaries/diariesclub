-- ===========================================================================
--  Migration 0008 — Home views + Realtime publication
--
--  Adds:
--    1) home_recent_activity — UNION of wallet_transactions, completed
--       sessions, and xp_events (per child) for the "Recent activity" list
--       on the Home tab. Security-invoker view → RLS on the underlying
--       tables enforces family-scoping (auth.uid() = family_id).
--
--    2) supabase_realtime publication membership for the tables the Home
--       tab subscribes to (wallet, sessions, notifications, hero_recaps,
--       wallet_transactions, audit_log). Idempotent — safe to re-run.
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
--  1. home_recent_activity view
-- ---------------------------------------------------------------------------
-- Each branch returns the same shape so the client can render uniformly.
-- `kind` distinguishes the row type; `amount_paise` is signed (debit -ve);
-- `xp_total` is the sum of the four trait XPs for xp_events rows.
--
-- WHY security_invoker: we want RLS on wallet_transactions / sessions /
-- xp_events to apply per-caller. A SECURITY DEFINER view would bypass RLS
-- and leak cross-family rows.
CREATE OR REPLACE VIEW public.home_recent_activity
WITH (security_invoker = true) AS
  -- Wallet transactions (top-ups, debits, bonuses, refunds, etc.)
  SELECT
    'wallet_tx'                        AS kind,
    wt.id                              AS id,
    wt.family_id                       AS family_id,
    NULL::UUID                         AS child_id,
    wt.type                            AS subtype,
    wt.amount_paise                    AS amount_paise,
    NULL::INTEGER                      AS duration_minutes,
    0                                  AS xp_total,
    wt.metadata                        AS metadata,
    wt.created_at                      AS created_at
  FROM wallet_transactions wt

  UNION ALL

  -- Completed play sessions
  SELECT
    'session'                          AS kind,
    s.id                               AS id,
    s.family_id                        AS family_id,
    s.child_id                         AS child_id,
    s.status                           AS subtype,
    -s.amount_paise                    AS amount_paise, -- shown as outflow
    s.duration_minutes                 AS duration_minutes,
    s.total_xp_earned                  AS xp_total,
    '{}'::JSONB                        AS metadata,
    COALESCE(s.completed_at, s.created_at) AS created_at
  FROM sessions s
  WHERE s.status IN ('completed', 'auto_closed')

  UNION ALL

  -- XP events (per child)
  SELECT
    'xp'                               AS kind,
    xe.id                              AS id,
    xe.family_id                       AS family_id,
    xe.child_id                        AS child_id,
    xe.event_type                      AS subtype,
    0                                  AS amount_paise,
    NULL::INTEGER                      AS duration_minutes,
    (xe.xp_rafi + xe.xp_ellie + xe.xp_gerry + xe.xp_zena) AS xp_total,
    xe.metadata                        AS metadata,
    xe.created_at                      AS created_at
  FROM xp_events xe;

COMMENT ON VIEW public.home_recent_activity IS
  'Unified activity feed for Home tab. Security-invoker: RLS on underlying '
  'tables enforces family-scoping. Client should still .eq("family_id", ...) '
  'and .order("created_at", desc).limit(N).';

GRANT SELECT ON public.home_recent_activity TO authenticated;

-- ---------------------------------------------------------------------------
--  2. Realtime publication membership
-- ---------------------------------------------------------------------------
-- Supabase ships a publication called `supabase_realtime`. Adding a table
-- to it lets clients subscribe via `.stream()` / channel events. RLS still
-- applies — clients only see rows they're already entitled to read.
--
-- DO block: ALTER PUBLICATION ADD TABLE errors if the table is already in
-- the publication, so we check pg_publication_tables first.
DO $$
DECLARE
  v_table TEXT;
  v_tables TEXT[] := ARRAY[
    'sessions',
    'wallets',
    'wallet_transactions',
    'notifications',
    'hero_recaps',
    'audit_log'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = v_table
    ) THEN
      EXECUTE format(
        'ALTER PUBLICATION supabase_realtime ADD TABLE public.%I',
        v_table
      );
    END IF;
  END LOOP;
END $$;

COMMIT;
