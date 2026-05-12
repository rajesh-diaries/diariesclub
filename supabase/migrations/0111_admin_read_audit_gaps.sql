-- 0111 — admin read policies for every table the admin app touches.
--
-- Same root-cause as 0106/0110 (birthday_reservations /
-- birthday_party_photos): the admin app reads these via PostgREST
-- .select()/.stream(), but RLS only had family-scoped policies — admins
-- saw zero rows. Repeat audit across the whole table set.

DO $$
DECLARE
  v_table TEXT;
BEGIN
  FOR v_table IN
    SELECT unnest(ARRAY[
      'audit_log',
      'staff',
      'refunds',
      'order_items',
      'workshop_registrations',
      'fit_meal_orders',
      'session_extensions',
      'session_pre_bookings',
      'notifications',
      'hero_recaps',
      'xp_events',
      'referral_conversions',
      'hero_card_collection',
      'visit_milestones',
      'streak_records',
      'parent_logged_moments',
      'brand_badges',
      'gift_redemptions',
      'birthday_journey_state'
    ])
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS %I_admin_read ON %I',
      v_table, v_table
    );
    EXECUTE format(
      'CREATE POLICY %I_admin_read ON %I FOR SELECT USING (is_active_admin())',
      v_table, v_table
    );
  END LOOP;
END $$;
