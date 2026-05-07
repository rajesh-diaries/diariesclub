-- ===========================================================================
--  Migration 0051 — Announcement FCM push + birthday_packages realtime
--
--  Two parity gaps caught during the workshop publish-chain audit:
--
--  1. admin_announcement_create wrote to announcements but never inserted
--     fanout rows into notifications. So announcements showed in the
--     in-app feed (announcements_feed.dart, realtime stream) but never
--     fired FCM push. Founder spec wants both. This migration mirrors
--     the workshop fanout pattern (_fanout_workshop_published →
--     notify_push_after_insert trigger → notify_push_dispatch →
--     send-push Edge Fn).
--
--  2. birthday_packages was not in the supabase_realtime publication, so
--     the customer-side birthday_packages_provider was a one-shot
--     FutureProvider — admin edits never reflected to active customer
--     sessions. Adding the table to the publication unlocks .stream()
--     for the Flutter provider switch (separate commit, same PR).
--
--  Reversibility:
--    ALTER PUBLICATION supabase_realtime DROP TABLE birthday_packages;
--    DROP FUNCTION _fanout_announcement_published(uuid,text,text,text);
--    -- restore the prior admin_announcement_create body from 0033.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Add 'announcement_published' to the notifications.type check constraint.
--    Postgres requires drop-and-recreate for ALTER on CHECK; mirror the
--    existing list verbatim and append the new value at the end.
-- ---------------------------------------------------------------------------
ALTER TABLE notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (type = ANY (ARRAY[
    'session_started','hydration_nudge','healthy_bite_earned',
    'grace_started','extend_nudge','session_closed','recap_ready',
    'reflection_prompt','reflection_auto_split',
    'order_confirmed','order_ready',
    'hero_card_received',
    'stage_transition_imminent','stage_transition_revealed','level_up',
    'birthday_d_minus_90','birthday_d_minus_60','birthday_d_minus_30',
    'birthday_d_minus_14','birthday_d_minus_7','birthday_d_minus_3',
    'birthday_d_minus_1','birthday_d_zero','birthday_d_plus_1',
    'birthday_album_ready','birthday_hero_progression_trigger',
    'birthday_wish',
    'referral_reward','first_referral_brave_boost',
    'wallet_topup','wallet_low_balance',
    'visit_milestone','streak_milestone',
    'refund_processed','reactivation_welcome',
    'workshop_reminder','workshop_cancelled',
    'pre_booking_reminder','pre_booking_expired',
    'while_you_wait_food',
    'announcement_published'   -- NEW
  ]::text[]));

-- ---------------------------------------------------------------------------
-- 2. _fanout_announcement_published — mirror of _fanout_workshop_published.
--    Inserts one notifications row per opted-in family. The
--    notify_push_after_insert trigger handles the FCM dispatch.
--
--    Family preferences key: 'announcements' (defaults to TRUE if unset,
--    same default-true pattern as 'workshop_reminders').
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._fanout_announcement_published(
  p_announcement_id UUID,
  p_title           TEXT,
  p_body            TEXT,
  p_cta_route       TEXT
) RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count INTEGER := 0;
  v_body  TEXT;
BEGIN
  -- Cap notification body at 120 chars; FCM payload limits + readability.
  v_body := COALESCE(LEFT(p_body, 120), '');
  IF length(COALESCE(p_body, '')) > 120 THEN
    v_body := v_body || '…';
  END IF;

  WITH inserted AS (
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    SELECT
      f.id,
      'announcement_published',
      p_title,
      v_body,
      COALESCE(p_cta_route, '/home'),
      p_announcement_id
    FROM families f
    WHERE f.deleted_at IS NULL
      AND f.is_anonymised = FALSE
      AND f.is_walk_in = FALSE
      AND COALESCE(
            (f.notification_preferences->>'announcements')::BOOLEAN,
            TRUE
          ) = TRUE
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_count FROM inserted;
  RETURN v_count;
END $$;

REVOKE ALL ON FUNCTION public._fanout_announcement_published(UUID,TEXT,TEXT,TEXT)
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. admin_announcement_create — call fanout when is_published=true.
--    Same shape as 0033 + the fanout call + an extra audit field.
--    Workshop announcements (auto-created by workshop trigger) skip the
--    fanout because the workshop's own _fanout_workshop_published already
--    pushed via the workshop_reminder type — double push would be spam.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_announcement_create(
  p_venue_id      UUID,
  p_title         TEXT,
  p_body          TEXT,
  p_type          TEXT,
  p_cta_label     TEXT,
  p_cta_route     TEXT,
  p_photo_url     TEXT,
  p_visible_from  TIMESTAMPTZ,
  p_visible_until TIMESTAMPTZ,
  p_is_published  BOOLEAN
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID;
  v_row      announcements%ROWTYPE;
  v_fanout   INTEGER := 0;
BEGIN
  v_admin_id := _assert_active_admin();

  IF p_type NOT IN ('workshop','general','event','promo','closure') THEN
    RAISE EXCEPTION 'invalid_type';
  END IF;
  IF p_visible_until IS NOT NULL AND p_visible_until <= COALESCE(p_visible_from, now()) THEN
    RAISE EXCEPTION 'visible_until_before_from';
  END IF;

  INSERT INTO announcements(
    venue_id, title, body, type,
    cta_label, cta_route, photo_url,
    visible_from, visible_until, is_published, created_by
  ) VALUES (
    p_venue_id, p_title, p_body, p_type,
    p_cta_label, p_cta_route, p_photo_url,
    COALESCE(p_visible_from, now()), p_visible_until,
    COALESCE(p_is_published, TRUE),
    auth.uid()
  ) RETURNING * INTO v_row;

  -- Fanout to FCM only when:
  --   * we're publishing immediately (not a draft), AND
  --   * type is not 'workshop' (workshop announcements are paired with
  --     a workshop row whose own fanout fires workshop_reminder push —
  --     don't double-push).
  IF v_row.is_published AND p_type <> 'workshop' THEN
    v_fanout := _fanout_announcement_published(
      v_row.id, v_row.title, v_row.body, v_row.cta_route
    );
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    v_admin_id, 'admin', 'announcement.create', 'announcement',
    v_row.id, p_venue_id,
    jsonb_build_object(
      'title', p_title,
      'type', p_type,
      'is_published', v_row.is_published,
      'notifications_fanned_out', v_fanout
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'announcement_id', v_row.id,
    'notifications_fanned_out', v_fanout
  );
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_announcement_create(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN
) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_announcement_create(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN
) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. birthday_packages → supabase_realtime publication
--    So the Flutter customer provider can switch from FutureProvider to
--    StreamProvider and reflect admin edits in active sessions.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND tablename = 'birthday_packages'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE birthday_packages';
  END IF;
END $$;
