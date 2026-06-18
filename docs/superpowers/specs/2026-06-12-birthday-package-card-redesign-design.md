# Birthday package card redesign — design spec

## Goal

Redesign the customer-facing birthday package discovery cards so the four finalized tiers (Little Joy, Happy Tales, Grand, Magical) feel like a clear upgrade ladder, even though there are no photos. The user selected the "thin accent bar" visual direction (option A) but also wants package details to be admin-configurable, so we combine option A's clean look with admin-editable accent color, badge and tagline.

## Visual direction (option A + editable data)

Each package card is a white rounded card with:

1. A 6 px top accent bar in the package's tier color.
2. A small rounded badge (optional) at the top-left of the content area if `badge_text` is set.
3. Package name in the standard heading style.
4. A one-line tagline in the accent color, font-weight 700.
5. Hall name and guest range on one line (`Pearl · 25–45 guests`).
6. Two pill-shaped price chips for Veg / Non-Veg, outlined and tinted with the accent color.
7. A caption line "per guest · 18% GST extra".
8. The first 3 inclusions as a compact icon+bullet grid.
9. A "Show all inclusions" expander that reveals the rest.
10. A full-width navy "Inquire" CTA.

No hero image is shown; the `cover_image_url` is ignored on the list card (it is already hidden when empty, and these packages have no cover).

## Finalized package data (source of truth)

| Package | Hall | Guests | Veg | Non-Veg | Badge | Tagline | Accent |
|---|---|---|---|---|---|---|---|
| Little Joy | Pearl | 25–45 | ₹1,099 | ₹1,249 | — | "Perfect for intimate celebrations" | Fit green |
| Happy Tales | Pearl | 25–45 | ₹1,299 | ₹1,399 | Most Booked | "Our most loved package" | Rafi coral |
| Grand | The Grand | 45–200 | ₹1,499 | ₹1,699 | Big celebration | "Grand scale, seamless fun" | Navy |
| Magical | The Grand | 45–200 | ₹1,799 | ₹1,899 | Premium | "The full enchanted experience" | Gold |

Inclusions are merged into a single list (food + experience + non-food) on the card.

## Data-model changes

Add three new columns to `public.birthday_packages`:

- `accent_color_hex TEXT` — hex color, e.g. `#4ADE80`. Null/empty falls back to the static tier map in Flutter.
- `badge_text TEXT` — optional badge copy. Null/empty hides the badge.
- `tagline TEXT` — one-line subtitle shown under the package name.

Also ensure the existing Slice 2 fields remain present: `hall_name`, `min_guests`, `max_guests`, `price_per_pax_veg_paise`, `price_per_pax_non_veg_paise`, `inclusions` (JSONB array of strings), `experience_inclusions` (text[]), `non_food_offerings` (JSONB).

Update `admin_package_create` and `admin_package_update` RPCs to accept `p_accent_color_hex`, `p_badge_text` and `p_tagline`. Existing calls continue to work because the new params have defaults.

## Admin package edit screen changes

Add a new "Card styling" section below the pricing row with:

- `Accent color` — text field accepting a hex code (e.g. `#FF7A6E`). No color picker in v1; validated to be a 3- or 6-digit hex string.
- `Badge text` — optional one-line text.
- `Tagline` — optional one-line text shown under the name.

Keep the existing fields editable: name, description, category, tier, hall, min/max guests, veg/non-veg prices, duration, sort order, active toggle, inclusions, experience inclusions, menu options, non-food offerings, available days, gallery URLs, cover photo.

## Customer UI changes

`lib/features/birthday/birthday_packages_screen.dart`:

- Replace the `_packageAccentColor` helper with one that reads `accent_color_hex` first, then falls back to the static name map.
- Replace `_packageBadge` with a function that returns a badge only when `badge_text` is non-empty; use the resolved accent color as the badge background.
- Use the package's `tagline` field under the name; if empty, fall back to a static per-name tagline.
- Keep the thin 6 px accent bar, white card, price chips, top-3 inclusions + expander, and navy inquire CTA.
- Remove the duplicate badge inside the hero area; show badge only in the content area top (because there is no hero image).

`lib/features/birthday/package_detail_screen.dart`:

- Use the resolved accent color for section headers and bullet icons.
- Keep the merged "What's included" list.

## Fallback behavior

If the new columns are null (e.g., during rollout before the admin form is populated), the customer app must render correctly using static defaults:

- `accent_color_hex` missing → use the existing `_packageAccentColor(name)` map.
- `badge_text` missing/empty → use the existing static badge map, otherwise none.
- `tagline` missing/empty → use a static tagline map for the four known names; custom packages show no tagline.

This keeps the app usable immediately after the migration and before the founder edits each package.

## Static fallback values

Until the founder fills the new admin fields, the customer app falls back to these hard-coded values for the four known package names:

| Package | Accent | Badge | Tagline |
|---|---|---|---|
| Little Joy | `AppColors.fitGreen` | — | "Perfect for intimate celebrations" |
| Happy Tales | `AppColors.rafiCoral` | "Most Booked" | "Our most loved package" |
| Grand | `AppColors.navy` | "Big celebration" | "Grand scale, seamless fun" |
| Magical | `AppColors.gold` | "Premium" | "The full enchanted experience" |

## Migration plan

1. Create migration `0152_birthday_packages_card_styling.sql` that adds `accent_color_hex`, `badge_text`, `tagline` to `birthday_packages`.
2. Replace `admin_package_create` and `admin_package_update` with new signatures including the three new params (defaults to NULL/empty) and update the `INSERT`/`UPDATE` statements to set the new columns.
3. Apply the migration to the linked Supabase project.

## Admin web deployment

The admin app is a Flutter web build deployed to Cloudflare Pages. After code changes:

1. Build the admin web app (`flutter build web -t lib/app_admin.dart`).
2. Deploy `build/web` to the `feature-safari-club-tab` Pages project.
3. Verify the new fields appear when editing a package.

## Customer app verification

1. Run `flutter analyze`.
2. Build/run on iOS in profile mode (debug crashes with `DartWorker` memory errors on this device).
3. Confirm all four packages render with correct colors, badges, taglines, prices, halls and inclusions.

## Out of scope

- Full photo/illustration headers (the founder does not want photos now).
- A visual color picker in the admin form (v1 uses hex text).
- Changing the inquiry form or PDF generation beyond using the same package fields.

## Open questions

None — the direction and fields are approved by the user (option A visual style with admin-configurable accent/badge/tagline).
