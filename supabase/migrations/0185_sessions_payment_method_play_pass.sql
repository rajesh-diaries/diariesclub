-- Fix: sessions.payment_method check constraint must include 'play_pass'
-- Previous migrations (0178, 0182, 0184) added play_pass support to session_create
-- but never updated the table-level check constraint. This caused INSERTs with
-- payment_method = 'play_pass' to fail with a generic check-violation error that
-- the Flutter app surfaces as "Couldn't start session. Please try again."

DO $$
DECLARE
  v_constraint_exists boolean;
BEGIN
  -- Check whether the current constraint already allows play_pass
  SELECT EXISTS (
    SELECT 1 FROM information_schema.check_constraints
    WHERE constraint_name = 'sessions_payment_method_check'
      AND check_clause LIKE '%play_pass%'
  ) INTO v_constraint_exists;

  IF v_constraint_exists THEN
    RAISE NOTICE 'sessions_payment_method_check already includes play_pass — skipping';
    RETURN;
  END IF;

  -- Drop the old constraint and recreate with play_pass included
  ALTER TABLE public.sessions
    DROP CONSTRAINT IF EXISTS sessions_payment_method_check;

  ALTER TABLE public.sessions
    ADD CONSTRAINT sessions_payment_method_check
    CHECK (payment_method IN ('wallet','cash','razorpay','cash_walkin','play_pass'));

  RAISE NOTICE 'sessions_payment_method_check recreated with play_pass';
END $$;
