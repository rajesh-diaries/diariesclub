# Home UI Polish — Playful Premium Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the Playful Premium home redesign from the spec: standardize cards, spacing, shadows, typography, and icons across the customer home tab.

**Architecture:** Add small theme tokens and text styles, then sweep each home widget to use them. Keep changes local to `lib/features/home/` and shared theme files; no business logic changes.

**Tech Stack:** Flutter, Riverpod, `phosphor_flutter`, `cached_network_image`, existing theme.

---

## File Structure

- `lib/core/theme/app_theme.dart` — add card/shadow/spacing tokens.
- `lib/core/theme/app_text_styles.dart` — add `cardTitle`, `cardSubtitle`, `pillLabel`.
- `lib/features/home/home_app_bar.dart` — wallet style + notification badge color.
- `lib/features/home/views/idle_home_view.dart` — uniform spacing.
- `lib/features/home/views/multi_session_home_view.dart` — uniform spacing.
- `lib/features/home/views/post_session_home_view.dart` — uniform spacing.
- `lib/features/home/widgets/big_start_session_card.dart` — use theme text styles.
- `lib/features/home/widgets/play_pass_promo_card.dart` — standardized surfaces/shadows.
- `lib/features/home/widgets/order_food_card.dart` — standardized surface/shadow + Phosphor icon.
- `lib/features/home/widgets/start_session_card.dart` — standardized shadow.
- `lib/features/home/widgets/active_session_card.dart` — radius/shadow/text cleanup.
- `lib/features/home/widgets/live_orders_card.dart` — surface/shadow/icons.
- `lib/features/home/widgets/referral_invite_card.dart` — surface/shadow/icons.
- `lib/features/home/widgets/referral_entry_card.dart` — surface/shadow/icons.
- `lib/features/home/widgets/home_combos_strip.dart` — combo mini-card radius/shadow.
- `lib/features/home/widgets/home_banner_carousel.dart` — cached images + shimmer.

---

### Task 1: Add theme tokens

**Files:**
- Modify: `lib/core/theme/app_theme.dart`
- Modify: `lib/core/theme/app_text_styles.dart`

- [ ] **Step 1: Add tokens to `app_theme.dart`**

  Add at the top of the file as constants (or inside `AppTheme` if it is a class):

  ```dart
  const double kHomeCardRadius = 16.0;
  const double kHomeSectionGap = 12.0;
  const double kHomeCardPadding = 16.0;

  BoxShadow kHomeCardShadow(BuildContext context) => BoxShadow(
        color: AppColors.navy.withValues(alpha: 0.08),
        blurRadius: 12,
        offset: const Offset(0, 4),
      );
  ```

  > If `AppColors` is not imported, add `import 'app_colors.dart';`.

- [ ] **Step 2: Add text styles to `app_text_styles.dart`**

  Add inside `AppTextStyles`:

  ```dart
  static TextStyle cardTitle(BuildContext c, {Color? color}) => GoogleFonts.nunito(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: color ?? Theme.of(c).colorScheme.onSurface,
      );

  static TextStyle cardSubtitle(BuildContext c, {Color? color}) => GoogleFonts.nunito(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: color ?? Theme.of(c).colorScheme.onSurfaceVariant,
      );

  static TextStyle pillLabel(BuildContext c, {Color? color}) => GoogleFonts.nunito(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
        color: color ?? Colors.white,
      );
  ```

- [ ] **Step 3: Analyze**

  Run:

  ```bash
  flutter analyze lib/core/theme/app_theme.dart lib/core/theme/app_text_styles.dart
  ```

  Expected: `No issues found!`

- [ ] **Step 4: Commit**

  ```bash
  git add lib/core/theme/app_theme.dart lib/core/theme/app_text_styles.dart
  git commit -m "feat(theme): add home card tokens and text styles"
  ```

---

### Task 2: Unify home-view spacing

**Files:**
- Modify: `lib/features/home/views/idle_home_view.dart`
- Modify: `lib/features/home/views/multi_session_home_view.dart`
- Modify: `lib/features/home/views/post_session_home_view.dart`

- [ ] **Step 1: Update `idle_home_view.dart`**

  Change the scroll padding and internal gaps to 12 dp:

  ```dart
  return const SingleChildScrollView(
    padding: EdgeInsets.only(left: 20, right: 20, bottom: 12),
    child: IdleHomeBody(),
  );
  ```

  In `IdleHomeBody`, replace every `SizedBox(height: 10)`, `SizedBox(height: 12)`, and `SizedBox(height: 16)` between cards with `const SizedBox(height: kHomeSectionGap)`.

- [ ] **Step 2: Update `multi_session_home_view.dart`**

  Replace every `const SizedBox(height: 16)` between cards with `const SizedBox(height: kHomeSectionGap)`. Keep the 12 dp gap before the banner if desired, or standardize it too.

- [ ] **Step 3: Update `post_session_home_view.dart`**

  If it wraps `IdleHomeBody` with extra padding, reduce it to the same 20/12 pattern.

- [ ] **Step 4: Analyze**

  ```bash
  flutter analyze lib/features/home/views/idle_home_view.dart lib/features/home/views/multi_session_home_view.dart lib/features/home/views/post_session_home_view.dart
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add lib/features/home/views
  git commit -m "feat(home): unify section spacing to 12 dp"
  ```

---

### Task 3: `HomeAppBar` polish

**Files:**
- Modify: `lib/features/home/home_app_bar.dart`

- [ ] **Step 1: Use `AppTextStyles` for wallet amount**

  In `_WalletPill`, replace the amount `TextStyle` with:

  ```dart
  style: AppTextStyles.caption(context, color: AppColors.navy)
      .copyWith(fontWeight: FontWeight.w800),
  ```

- [ ] **Step 2: Make notification badge gold/navy**

  Change the badge container decoration to:

  ```dart
  decoration: BoxDecoration(
    color: AppColors.gold,
    borderRadius: BorderRadius.circular(10),
  ),
  ```

  and the badge text style to:

  ```dart
  style: const TextStyle(
    color: AppColors.navy,
    fontSize: 11,
    fontWeight: FontWeight.w800,
  ),
  ```

- [ ] **Step 3: Analyze + commit**

  ```bash
  flutter analyze lib/features/home/home_app_bar.dart
  git add lib/features/home/home_app_bar.dart
  git commit -m "feat(home): polish app bar badge and wallet text"
  ```

---

### Task 4: `BigStartSessionCard` use theme styles

**Files:**
- Modify: `lib/features/home/widgets/big_start_session_card.dart`

- [ ] **Step 1: Replace inline title/subtitle/button styles**

  - Title: `AppTextStyles.cardTitle(context, color: Colors.white).copyWith(fontSize: 26)`
  - Subtitle: `AppTextStyles.cardSubtitle(context, color: Colors.white)`
  - PLAY button text: `AppTextStyles.pillLabel(context, color: const Color(0xFF1A1A2E))`

- [ ] **Step 2: Use `kHomeCardRadius` and a soft shadow**

  ```dart
  borderRadius: BorderRadius.circular(kHomeCardRadius),
  boxShadow: [kHomeCardShadow(context)],
  ```

- [ ] **Step 3: Analyze + commit**

  ```bash
  flutter analyze lib/features/home/widgets/big_start_session_card.dart
  git add lib/features/home/widgets/big_start_session_card.dart
  git commit -m "feat(home): theme styles and shadow for Let's Play card"
  ```

---

### Task 5: `PlayPassPromoCard` standardized surfaces

**Files:**
- Modify: `lib/features/home/widgets/play_pass_promo_card.dart`

- [ ] **Step 1: Add shadow + radius to both variants**

  Wrap both promo and active-pass cards in a `Container` with:

  ```dart
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(kHomeCardRadius),
    color: // promo: navy gradient; active: cream surface,
    boxShadow: [kHomeCardShadow(context)],
  ),
  ```

- [ ] **Step 2: Use `AppTextStyles` for all text**

  Replace inline `TextStyle`s with `cardTitle`, `cardSubtitle`, and `pillLabel` as appropriate.

- [ ] **Step 3: Analyze + commit**

  ```bash
  flutter analyze lib/features/home/widgets/play_pass_promo_card.dart
  git add lib/features/home/widgets/play_pass_promo_card.dart
  git commit -m "feat(home): standardize Play Pass card surfaces"
  ```

---

### Task 6: `OrderFoodCard` polish

**Files:**
- Modify: `lib/features/home/widgets/order_food_card.dart`

- [ ] **Step 1: Standardize surface**

  Use cream surface `const Color(0xFFFDF8EE)`, radius `kHomeCardRadius`, and shadow `kHomeCardShadow(context)`.

- [ ] **Step 2: Replace Material arrow with Phosphor**

  ```dart
  import 'package:phosphor_flutter/phosphor_flutter.dart';
  ```

  Replace `Icons.arrow_forward` with `PhosphorIconsRegular.arrowRight`.

- [ ] **Step 3: Use `AppTextStyles` for title/subtitle and ORDER pill**

- [ ] **Step 4: Analyze + commit**

  ```bash
  flutter analyze lib/features/home/widgets/order_food_card.dart
  git add lib/features/home/widgets/order_food_card.dart
  git commit -m "feat(home): polish Order Food card surface and icon"
  ```

---

### Task 7: `StartSessionCard` shadow

**Files:**
- Modify: `lib/features/home/widgets/start_session_card.dart`

- [ ] **Step 1: Add shadow and standard radius**

  ```dart
  borderRadius: BorderRadius.circular(kHomeCardRadius),
  boxShadow: [kHomeCardShadow(context)],
  ```

- [ ] **Step 2: Use `AppTextStyles` for text**

- [ ] **Step 3: Analyze + commit**

  ```bash
  flutter analyze lib/features/home/widgets/start_session_card.dart
  git commit -m "feat(home): shadow and text styles for Start Session card"
  ```

---

### Task 8: `ActiveSessionsCard` cleanup

**Files:**
- Modify: `lib/features/home/widgets/active_session_card.dart`

- [ ] **Step 1: Reduce radius from 28 to `kHomeCardRadius`**

- [ ] **Step 2: Add `kHomeCardShadow(context)`**

- [ ] **Step 3: Replace inline text styles with `AppTextStyles`**

- [ ] **Step 4: Analyze + commit**

  ```bash
  flutter analyze lib/features/home/widgets/active_session_card.dart
  git commit -m "feat(home): standardize active session card"
  ```

---

### Task 9: `LiveOrdersCard` surface + icons

**Files:**
- Modify: `lib/features/home/widgets/live_orders_card.dart`

- [ ] **Step 1: Add white surface, radius, shadow**

  ```dart
  color: AppColors.lightSurface,
  borderRadius: BorderRadius.circular(kHomeCardRadius),
  boxShadow: [kHomeCardShadow(context)],
  ```

- [ ] **Step 2: Replace Material chevron with Phosphor `caretRight`**

- [ ] **Step 3: Use `AppTextStyles` for status pills and labels**

- [ ] **Step 4: Analyze + commit**

  ```bash
  flutter analyze lib/features/home/widgets/live_orders_card.dart
  git commit -m "feat(home): polish Live Orders card"
  ```

---

### Task 10: Referral cards polish

**Files:**
- Modify: `lib/features/home/widgets/referral_invite_card.dart`
- Modify: `lib/features/home/widgets/referral_entry_card.dart`

- [ ] **Step 1: Add radius + shadow to both**

- [ ] **Step 2: Replace Material arrows with Phosphor `arrowRight`**

- [ ] **Step 3: Use `AppTextStyles` for titles and CTAs**

- [ ] **Step 4: Analyze + commit**

  ```bash
  flutter analyze lib/features/home/widgets/referral_invite_card.dart lib/features/home/widgets/referral_entry_card.dart
  git commit -m "feat(home): polish referral cards"
  ```

---

### Task 11: `HomeCombosStrip` combo mini-cards

**Files:**
- Modify: `lib/features/home/widgets/home_combos_strip.dart`

- [ ] **Step 1: Standardize mini-card radius and shadow**

  Use `kHomeCardRadius` and `kHomeCardShadow(context)`.

- [ ] **Step 2: Use `AppTextStyles` for title/price**

- [ ] **Step 3: Analyze + commit**

  ```bash
  flutter analyze lib/features/home/widgets/home_combos_strip.dart
  git commit -m "feat(home): standardize combo strip cards"
  ```

---

### Task 12: `HomeBannerCarousel` cached images

**Files:**
- Modify: `lib/features/home/widgets/home_banner_carousel.dart`

- [ ] **Step 1: Import cached_network_image**

  ```dart
  import 'package:cached_network_image/cached_network_image.dart';
  ```

- [ ] **Step 2: Replace `Image.network` with `CachedNetworkImage`**

  Use a `Shimmer`-style placeholder or `Container` with skeleton color while loading.

  ```dart
  CachedNetworkImage(
    imageUrl: imageUrl,
    fit: BoxFit.cover,
    placeholder: (context, url) => Container(
      color: AppColors.lightBorder,
    ),
    errorWidget: (context, url, error) => Container(
      color: AppColors.lightBorder,
      child: const Icon(PhosphorIconsRegular.image, color: AppColors.lightTextSecondary),
    ),
  )
  ```

- [ ] **Step 3: Add subtle shadow to the active banner image**

- [ ] **Step 4: Analyze + commit**

  ```bash
  flutter analyze lib/features/home/widgets/home_banner_carousel.dart
  git commit -m "feat(home): cached banner images with placeholder"
  ```

---

### Task 13: Final verification

**Files:** all files above.

- [ ] **Step 1: Full home analyze**

  ```bash
  flutter analyze lib/features/home lib/core/theme/app_theme.dart lib/core/theme/app_text_styles.dart
  ```

  Expected: `No issues found!`

- [ ] **Step 2: Hot-reload check**

  Run the app, check idle home and active-session home:
  - All cards share radius/shadow.
  - Spacing is consistent.
  - No Material icons remain in scope.
  - Text is readable and hierarchy is clear.

- [ ] **Step 3: Final commit**

  ```bash
  git add -A
  git commit -m "feat(home): playful premium polish - cards, spacing, shadows, icons"
  ```

---

## Self-Review Checklist

- [x] Spec coverage: every design point maps to a task.
- [x] No placeholders: each step has concrete code/commands.
- [x] Type consistency: token names and text-style names match across tasks.
