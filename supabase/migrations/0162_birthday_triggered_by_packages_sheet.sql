-- 0162 — Allow 'packages_sheet' as a valid birthday_reservations.triggered_by
-- value. The customer app's inquiry bottom sheet (lib/features/birthday/
-- widgets/inquiry_bottom_sheet.dart:140) passes 'packages_sheet' to
-- preserve provenance — it was never added to the CHECK constraint, so
-- every submit failed with "violates check constraint
-- birthday_reservations_triggered_by_check".
ALTER TABLE birthday_reservations
  DROP CONSTRAINT IF EXISTS birthday_reservations_triggered_by_check;
ALTER TABLE birthday_reservations
  ADD CONSTRAINT birthday_reservations_triggered_by_check CHECK (
    triggered_by = ANY (ARRAY[
      'home_card',
      'day_minus_90','day_minus_60','day_minus_30','day_minus_14',
      'day_minus_7','day_minus_3',
      'hero_progression',
      'manual','manual_admin',
      'packages_sheet'
    ])
  );
