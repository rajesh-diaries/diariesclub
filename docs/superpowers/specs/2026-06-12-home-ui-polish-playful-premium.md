# Home UI Polish — Playful Premium Sprint

## Goal
Make the idle and active-session home screens feel polished, consistent, and on-brand by standardizing cards, spacing, shadows, typography, and icons. Scope is limited to the customer home tab and its immediately reused widgets.

## Scope

### In scope
- `lib/features/home/home_app_bar.dart`
- `lib/features/home/views/idle_home_view.dart`
- `lib/features/home/views/multi_session_home_view.dart`
- `lib/features/home/views/post_session_home_view.dart`
- `lib/features/home/widgets/big_start_session_card.dart`
- `lib/features/home/widgets/play_pass_promo_card.dart`
- `lib/features/home/widgets/order_food_card.dart`
- `lib/features/home/widgets/start_session_card.dart`
- `lib/features/home/widgets/active_session_card.dart`
- `lib/features/home/widgets/live_orders_card.dart`
- `lib/features/home/widgets/referral_invite_card.dart`
- `lib/features/home/widgets/referral_entry_card.dart`
- `lib/features/home/widgets/home_combos_strip.dart`
- `lib/features/home/widgets/home_banner_carousel.dart`
- `lib/core/theme/app_theme.dart` (spacing/shadow tokens only)
- `lib/core/theme/app_text_styles.dart` (add small label/caption styles if missing)

### Out of scope
- Club, Adventure, Safari, Profile tabs.
- Empty-state illustrations.
- Skeleton loading screens.
- Admin/staff apps.

## Design Principles

1. **One card language:** every card in the home feed uses the same radius, surface color, and shadow.
2. **Breathing room:** consistent 12 dp gaps between major cards, 8 dp inside grouped rows.
3. **Hero colors only on the primary CTA:** the “Let’s Play” gradient keeps the four hero colors; everything else uses navy/gold/surface tones.
4. **Readable hierarchy:** headline → subtitle → action, left-aligned.
5. **No hardcoded styles:** high-impact inline `TextStyle`s move to `AppTextStyles`.

## Tokens

Add to `AppTheme` or as constants in `lib/core/theme/app_theme.dart`:

| Token | Value |
|---|---|
| `homeCardRadius` | 16.0 |
| `homeCardPadding` | 16.0 |
| `homeCardShadow` | `BoxShadow(color: AppColors.navy.withValues(alpha: 0.08), blurRadius: 12, offset: Offset(0, 4))` |
| `homeSectionGap` | 12.0 |
| `homeCardSurface` | `AppColors.lightSurface` |

## Component Changes

### HomeAppBar
- Keep greeting + tagline on the left.
- Wallet pill: keep gold tint, but use `AppTextStyles.caption` for the amount.
- Notification bell: keep, but replace `adminRed` badge with `AppColors.gold` background and `AppColors.navy` text to stay on-brand.

### IdleHomeView / MultiSessionHomeView / PostSessionHomeView
- Unify vertical spacing to `homeSectionGap` (12 dp).
- Idle view top padding: 12 dp (matches active view).
- Active view: keep banner below the timer as already implemented; apply the same 12 dp gap.

### BigStartSessionCard
- Keep the four-hero-color moving gradient.
- Keep text-left / hero-centre / button-right layout.
- Use the same outer `homeCardRadius` and a soft matching shadow.
- Move title/subtitle/button text styles to `AppTextStyles`.

### PlayPassPromoCard
- Promo state: navy gradient surface with white text, radius 16, soft shadow.
- Active-pass state: cream/gold-tinted surface, radius 16, soft shadow, navy text.
- Replace any hardcoded styles with `AppTextStyles`.

### OrderFoodCard
- Surface: cream (`Color(0xFFFDF8EE)`), radius 16, shadow.
- “ORDER” pill: navy background, white text, radius 999.
- Replace Material arrow icon with Phosphor `arrowRight`.

### StartSessionCard
- Navy surface, radius 16, shadow, white text.
- Keep rocket icon.

### ActiveSessionsCard
- Radius 16 (down from 28), softer shadow.
- Timer ring and labels use `AppTextStyles`.
- Reduce visual weight of status pills.

### LiveOrdersCard
- White surface, radius 16, shadow.
- Timeline pills use a consistent navy/gray color pair.
- Replace Material chevron with Phosphor `caretRight`.

### ReferralInviteCard / ReferralEntryCard
- Radius 16, shadow, consistent navy surface.
- Replace Material arrows with Phosphor icons.

### HomeCombosStrip
- Combo mini-cards: radius 16, shadow.
- Title/price text through `AppTextStyles`.

### HomeBannerCarousel
- Switch from `Image.network` to `CachedNetworkImage` with a shimmer placeholder.
- Keep peek effect; add subtle shadow to the active image.

## Typography Additions

Add to `AppTextStyles`:

- `cardTitle(BuildContext)` — 18 / w800 / onSurface
- `cardSubtitle(BuildContext)` — 13 / w500 / onSurfaceVariant
- `pillLabel(BuildContext)` — 13 / w900 / white (or inverse)

## Icon Cleanup

- Replace all `Icons.*` in the in-scope files with Phosphor equivalents:
  - `Icons.arrow_forward` → `PhosphorIconsRegular.arrowRight`
  - `Icons.arrow_forward_ios` / `Icons.chevron_right` → `PhosphorIconsRegular.caretRight`
  - `Icons.add_shopping_cart` → `PhosphorIconsRegular.shoppingCart`
  - `Icons.check` → `PhosphorIconsRegular.check`
  - `Icons.close` → `PhosphorIconsRegular.x`
  - `Icons.remove_circle_outline` / `Icons.add_circle_outline` → `PhosphorIconsRegular.minusCircle` / `PhosphorIconsRegular.plusCircle`

## Active Play Pass Card Redesign

The active-pass state of `PlayPassPromoCard` should feel clean and avoid a wall of text.

- **Title:** `{remaining} Play Pass{es}` (e.g. “3 Play Passes”).
- **Subtitle:** Validity of the soonest-expiring active pass.
  - If expiry is within 7 days: “Expires in {n} days”.
  - Otherwise: “Valid until {d MMM}”.
- **Surface:** Keep the existing cream/gold-bordered card.
- **Leading:** Keep the gold ticket icon in a soft gold-tinted rounded square.
- **No usage hint:** Do not show “1 pass = 1 hour”.
- **No CTA:** The card is informational; no action button needed.

## Acceptance Criteria
- [ ] All home cards use radius 16 and the same shadow token.
- [ ] No hardcoded `TextStyle` in `BigStartSessionCard`, `OrderFoodCard`, `PlayPassPromoCard`, `ActiveSessionsCard`.
- [ ] No Material icons in any in-scope file.
- [ ] `flutter analyze` passes.
- [ ] Home screens (idle / active / post-session) have consistent 12 dp vertical gaps.
- [ ] Visual appearance matches the “Playful Premium” direction (Option A).
- [ ] Active Play Pass card shows only pass count + validity.
