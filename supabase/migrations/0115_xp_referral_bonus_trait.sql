-- 0115 — make the referral bonus trait admin-configurable.
-- Currently hardcoded in referral_convert to give the bonus to Rafi.
-- Add venue_config.xp_referral_bonus_trait so admin can route to any
-- of rafi/ellie/gerry/zena or split equally. Helper function
-- _xp_split_for_trait converts (amount, trait) → 4-tuple of XP per trait.

ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS xp_referral_bonus_trait TEXT
    NOT NULL DEFAULT 'rafi'
    CHECK (xp_referral_bonus_trait IN ('rafi','ellie','gerry','zena','split'));

CREATE OR REPLACE FUNCTION _xp_split_for_trait(
  p_amount INTEGER,
  p_trait  TEXT,
  OUT r_rafi  INTEGER,
  OUT r_ellie INTEGER,
  OUT r_gerry INTEGER,
  OUT r_zena  INTEGER
)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_per INTEGER;
BEGIN
  r_rafi := 0; r_ellie := 0; r_gerry := 0; r_zena := 0;
  CASE p_trait
    WHEN 'rafi'  THEN r_rafi  := p_amount;
    WHEN 'ellie' THEN r_ellie := p_amount;
    WHEN 'gerry' THEN r_gerry := p_amount;
    WHEN 'zena'  THEN r_zena  := p_amount;
    WHEN 'split' THEN
      v_per := p_amount / 4;
      r_rafi  := v_per;
      r_ellie := v_per;
      r_gerry := v_per;
      r_zena  := p_amount - (v_per * 3);
    ELSE
      r_rafi := p_amount;
  END CASE;
END $$;

CREATE OR REPLACE FUNCTION public.referral_convert(
  p_referrer_family_id    UUID,
  p_new_family_id         UUID,
  p_triggering_session_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_config venue_config%ROWTYPE;
  v_venue_id UUID;
  v_month_start DATE;
  v_month_total INTEGER;
  v_is_first BOOLEAN;
  v_referrer_wallet wallets%ROWTYPE;
  v_new_wallet wallets%ROWTYPE;
  v_first_child UUID;
  v_gifter_credit INTEGER;
  v_new_credit INTEGER;
  v_split RECORD;
BEGIN
  IF p_referrer_family_id = p_new_family_id THEN
    RAISE EXCEPTION 'invalid_referral';
  END IF;

  SELECT venue_id INTO v_venue_id FROM sessions WHERE id = p_triggering_session_id;
  IF v_venue_id IS NULL THEN RAISE EXCEPTION 'session_not_found'; END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_venue_id;
  v_gifter_credit := v_config.referral_gifter_credit_paise;
  v_new_credit    := v_config.referral_new_family_credit_paise;

  v_month_start := date_trunc('month', (now() AT TIME ZONE 'Asia/Kolkata'))::DATE;

  SELECT COALESCE(SUM(gifter_wallet_credit_paise), 0) INTO v_month_total
    FROM referral_conversions
    WHERE referrer_family_id = p_referrer_family_id
      AND conversion_month = v_month_start;
  IF (v_month_total + v_gifter_credit) > v_config.referral_monthly_cap_paise THEN
    RAISE EXCEPTION 'monthly_cap_exceeded';
  END IF;

  SELECT NOT EXISTS(
    SELECT 1 FROM referral_conversions WHERE referrer_family_id = p_referrer_family_id
  ) INTO v_is_first;

  SELECT * INTO v_referrer_wallet FROM wallets WHERE family_id = p_referrer_family_id FOR UPDATE;
  UPDATE wallets SET balance_paise = balance_paise + v_gifter_credit, updated_at = now()
    WHERE family_id = p_referrer_family_id RETURNING * INTO v_referrer_wallet;
  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise, payment_method
  ) VALUES (
    p_referrer_family_id, 'bonus', v_gifter_credit,
    v_referrer_wallet.balance_paise, 'system'
  );

  SELECT * INTO v_new_wallet FROM wallets WHERE family_id = p_new_family_id FOR UPDATE;
  UPDATE wallets SET balance_paise = balance_paise + v_new_credit, updated_at = now()
    WHERE family_id = p_new_family_id RETURNING * INTO v_new_wallet;
  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise, payment_method
  ) VALUES (
    p_new_family_id, 'bonus', v_new_credit, v_new_wallet.balance_paise, 'system'
  );

  -- First-referral XP boost — split per admin-configured trait.
  IF v_is_first AND v_config.xp_referral_bonus_rafi > 0 THEN
    SELECT id INTO v_first_child FROM children
      WHERE family_id = p_referrer_family_id ORDER BY created_at LIMIT 1;
    IF v_first_child IS NOT NULL THEN
      SELECT * INTO v_split FROM _xp_split_for_trait(
        v_config.xp_referral_bonus_rafi,
        v_config.xp_referral_bonus_trait
      );

      PERFORM xp_credit_with_split(
        v_first_child, p_referrer_family_id, v_venue_id,
        'referral_bonus',
        v_split.r_rafi, v_split.r_ellie, v_split.r_gerry, v_split.r_zena,
        NULL,
        jsonb_build_object(
          'reason', 'first_referral_xp_boost',
          'trait', v_config.xp_referral_bonus_trait
        )
      );
      INSERT INTO notifications(family_id, type, title, body, deep_link)
      VALUES (
        p_referrer_family_id, 'first_referral_brave_boost',
        'You unlocked an XP boost!',
        'Your first referral added +' || v_config.xp_referral_bonus_rafi
          || ' XP to your child''s adventure.',
        '/adventure'
      );
    END IF;
  ELSIF NOT v_is_first THEN
    INSERT INTO notifications(family_id, type, title, body, deep_link)
    VALUES (
      p_referrer_family_id, 'referral_reward',
      'Referral reward credited',
      'Welcome credit added for your friend, plus '
        || (v_gifter_credit / 100)::TEXT || ' for you.',
      '/wallet'
    );
  END IF;

  INSERT INTO referral_conversions(
    referrer_family_id, new_family_id, triggering_session_id, conversion_month,
    gifter_wallet_credit_paise, gifter_xp_bonus_rafi, new_family_wallet_credit_paise,
    is_first_referral
  ) VALUES (
    p_referrer_family_id, p_new_family_id, p_triggering_session_id, v_month_start,
    v_gifter_credit,
    CASE WHEN v_is_first THEN v_config.xp_referral_bonus_rafi ELSE 0 END,
    v_new_credit, v_is_first
  );

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value
  ) VALUES (
    NULL, 'system', 'referral.convert', 'family', p_referrer_family_id, v_venue_id,
    jsonb_build_object('new_family_id', p_new_family_id)
  );

  RETURN jsonb_build_object('success', true);
END $$;
