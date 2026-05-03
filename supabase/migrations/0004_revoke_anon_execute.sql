-- ===========================================================================
--  Diaries Club v1.5 — 0004_revoke_anon_execute.sql
--
--  Defense in depth: REVOKE EXECUTE on customer-facing RPCs from the `anon`
--  role. Postgres grants EXECUTE to PUBLIC by default on new functions, so
--  GRANT-ing to authenticated alone leaves anon implicitly able to call them.
--  Calls from anon would still be rejected inside the function body by the
--  auth.uid() = p_family_id guard, but revoking earlier closes the surface
--  and clears advisor lint 0028.
--
--  NOT touching: get_venue_config — intentionally callable by anon (catalog read).
--
--  Idempotent. REVOKE is safe to re-run.
-- ===========================================================================

REVOKE EXECUTE ON FUNCTION public.session_create(UUID,UUID,UUID,INTEGER,TEXT,UUID,BOOLEAN,TEXT,UUID,TEXT)            FROM anon;
REVOKE EXECUTE ON FUNCTION public.session_extend(UUID,INTEGER,TEXT,TEXT,UUID,TEXT)                                   FROM anon;
REVOKE EXECUTE ON FUNCTION public.session_complete(UUID,UUID)                                                        FROM anon;
REVOKE EXECUTE ON FUNCTION public.order_place(UUID,UUID,JSONB,TEXT,TEXT,UUID,UUID,TEXT)                              FROM anon;
REVOKE EXECUTE ON FUNCTION public.reflection_submit(UUID,TEXT[])                                                     FROM anon;
REVOKE EXECUTE ON FUNCTION public.workshop_register(UUID,UUID,UUID,TEXT,TEXT)                                        FROM anon;
REVOKE EXECUTE ON FUNCTION public.workshop_cancel(UUID,TEXT)                                                         FROM anon;
REVOKE EXECUTE ON FUNCTION public.birthday_reservation_create(UUID,UUID,UUID,UUID,DATE,TIME,INTEGER,INTEGER,TEXT,TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.pre_booking_create(UUID,UUID,UUID,TIMESTAMPTZ,INTEGER,TEXT)                        FROM anon;
REVOKE EXECUTE ON FUNCTION public.pre_booking_redeem(UUID,UUID,TEXT)                                                 FROM anon;
REVOKE EXECUTE ON FUNCTION public.pre_booking_cancel(UUID,TEXT)                                                      FROM anon;
REVOKE EXECUTE ON FUNCTION public.refund_issue(UUID,UUID,TEXT,INTEGER,TEXT,TEXT,UUID,UUID,TEXT)                      FROM anon;
REVOKE EXECUTE ON FUNCTION public.gift_redeem(UUID,UUID,UUID,UUID)                                                   FROM anon;
REVOKE EXECUTE ON FUNCTION public.reactivation_redeem(UUID,TEXT)                                                     FROM anon;
REVOKE EXECUTE ON FUNCTION public.family_anonymise(UUID,TEXT)                                                        FROM anon;

-- Also revoke from PUBLIC — Postgres' default EXECUTE grant on new functions
-- leaks via PUBLIC even after REVOKE FROM anon. Belt and braces.
REVOKE EXECUTE ON FUNCTION public.session_create(UUID,UUID,UUID,INTEGER,TEXT,UUID,BOOLEAN,TEXT,UUID,TEXT)            FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.session_extend(UUID,INTEGER,TEXT,TEXT,UUID,TEXT)                                   FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.session_complete(UUID,UUID)                                                        FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.order_place(UUID,UUID,JSONB,TEXT,TEXT,UUID,UUID,TEXT)                              FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reflection_submit(UUID,TEXT[])                                                     FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.workshop_register(UUID,UUID,UUID,TEXT,TEXT)                                        FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.workshop_cancel(UUID,TEXT)                                                         FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.birthday_reservation_create(UUID,UUID,UUID,UUID,DATE,TIME,INTEGER,INTEGER,TEXT,TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.pre_booking_create(UUID,UUID,UUID,TIMESTAMPTZ,INTEGER,TEXT)                        FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.pre_booking_redeem(UUID,UUID,TEXT)                                                 FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.pre_booking_cancel(UUID,TEXT)                                                      FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.refund_issue(UUID,UUID,TEXT,INTEGER,TEXT,TEXT,UUID,UUID,TEXT)                      FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.gift_redeem(UUID,UUID,UUID,UUID)                                                   FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reactivation_redeem(UUID,TEXT)                                                     FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.family_anonymise(UUID,TEXT)                                                        FROM PUBLIC;
