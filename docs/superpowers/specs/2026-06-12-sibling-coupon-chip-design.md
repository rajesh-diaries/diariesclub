# Sibling Coupon Chip — Direct Code Display

## Goal
Replace the generic "Buddy Discount" / "Sibling Saver" chip labels on the session start screen with the actual coupon code (e.g. `2KIDS` when 2 kids are selected) and make the mapping admin-configurable.

## Background
The session start screen currently shows a chip that says *Tap to apply Buddy Discount*. The underlying coupon code is hardcoded as `SIBLING2`, `SIBLING3`, etc. The admin has already created coupon codes like `2KIDS` and `4KIDS` in the dashboard, so the UI should expose those exact codes instead of a generic name.

## Design

### Data model
Add a new JSONB column `sibling_coupon_codes` to `venue_config`. It stores a map from kid count to coupon code:

```json
{
  "2": "2KIDS",
  "3": "3KIDS",
  "4": "4KIDS",
  "5": "5KIDS"
}
```

- Keys are stringified kid counts (`"2"` … `"5"`).
- Values are coupon `code` values from the `coupons` table.
- Only one code is shown at a time, for the current selection.

### Migration / backfill
1. Add `sibling_coupon_codes JSONB` to `venue_config`.
2. Backfill the default map above for the current venue.
3. Rename existing `SIBLING3` → `3KIDS` and `SIBLING5` → `5KIDS` so all sibling coupons follow the same naming convention.
4. Set `2KIDS.max_per_family = 1` to match the others.

### Flutter changes
1. Read `sibling_coupon_codes` from `venueConfigProvider`.
2. Replace `_siblingCouponFor()` with a config-driven lookup:
   - If the map contains a code for the current kid count, return it.
   - Otherwise fall back to the legacy hardcoded map (using the new codes) so the feature still works if the config row is ever missing.
3. Update `_SiblingCouponChips`:
   - Label is the code itself: `Apply 2KIDS` / `2KIDS applied`.
   - Keep the existing tap-to-apply behavior.
4. Keep the existing `_applySiblingCoupon()` path, but use the code returned by the lookup instead of a hardcoded value.
5. Update the kid-count-change cleanup logic that checks `_couponBackendCode!.startsWith('SIBLING')` so it invalidates any sibling coupon that is no longer valid for the new kid count, regardless of prefix.

### Edge cases
- If no sibling coupon is configured for the selected kid count, hide the chip.
- If the user already applied a sibling coupon and then changes kid count, clear it if it no longer matches.
- Coupon validation still goes through the backend `coupon_validate` RPC, so invalid/expired codes won’t actually discount.

## Success criteria
- With 2 kids selected, the chip shows `Apply 2KIDS`.
- With 3 kids selected, the chip shows `Apply 3KIDS`.
- Tapping the chip applies the code and the tally shows the discount.
- Admin can change the mapped codes in `venue_config` without an app update.
