# Bugfix Batch — Play Pass, Coupons, Home, Adventure, Safari Club

**Goal:** Fix all 7 issues reported from iPhone testing without regressions.

**Architecture:** Targeted fixes per screen/widget. Add one migration for Safari Club admin notice. Keep existing patterns (Riverpod, AppColors, AppTextStyles).

---

## Issue 1: Play Pass Purchase Sheet

**Problem:** Tap throws "Something went wrong" + transparent background shows home behind it.

**Root causes:**
- Sheet content has no opaque background (`showModalBottomSheet` uses `Colors.transparent`)
- `play_pass_purchase` RPC may fail if migration not applied; need better error handling + logging

**Files:**
- Modify: `lib/features/home/widgets/play_pass_purchase_sheet.dart`

**Changes:**
1. Wrap sheet content in `Container(color: Colors.white, borderRadius: ...)`
2. Add debug log around the RPC call
3. Surface specific error messages (insufficient_balance vs RPC not found vs generic)
4. Make profile empty state show a "Get Play Passes" CTA instead of error when table missing? No — keep error honest, but make empty state friendly.

---

## Issue 2: Remove Session Reflection from Home

**Problem:** Post-session reflection card appears on Home after session ends.

**Files:**
- Modify: `lib/features/home/views/post_session_home_view.dart` or wherever reflection UI is rendered

**Changes:**
- Remove reflection prompt/card from home post-session view
- Adventure tab already owns reflection — leave that untouched

---

## Issue 3: Sibling Coupons Manual + Friendly Names

**Problem:** Auto-applied SIBLING2/SIBLING3/SIBLING4 codes shown; should be manual with friendly names.

**Friendly mapping:**
- 2 kids → "Buddy Discount" → ₹150
- 3 kids → "Sibling Saver" → ₹250
- 4 kids → "Triple Fun" → ₹400
- 5+ kids → "Squad Deal" → ₹500

**Files:**
- Modify: `lib/features/sessions/session_start_screen.dart`
- Maybe update DB coupon codes? No — keep codes as SIBLING2-5 in DB for validation, show display names in UI only.

**Changes:**
1. Stop auto-applying on kid selection
2. Show available sibling coupons as tappable chips below coupon input when 2+ kids selected
3. Tapping applies coupon; show green "Buddy Discount applied — you save ₹150" banner
4. "Remove" clears it

---

## Issue 4: Active Session Home View Polish

**Problem:** Timer shows "mn left" not mm:ss; banners uneven; order food dull; admin banners need Swiggy-style small auto-swipe.

**Files:**
- Modify: active session home widgets (find timer, banner, order food, admin banner widgets)

**Changes:**
1. Timer format: `mm:ss` (e.g. "59:59")
2. "Add a friend to play" and "Refer friends" same height; reduce icon size
3. Order food card: more visual treatment (icon, subtle gradient, better typography)
4. Admin promo banners below active session: smaller height, auto-swipe PageView with dot indicator, Swiggy-style

---

## Issue 5: Adventure Tab Character Picker

**Problem:** Bottom overflow 8.9px; circular avatars with letters; should be rectangular with favorite character.

**Files:**
- Modify: Adventure tab character picker widget

**Changes:**
1. Increase card height / reduce padding to fix overflow
2. Rectangular character image instead of circle letter
3. Use `HeroAvatar` or `Image.asset('assets/hero/${favouriteHero}.png')` based on child's `favourite_hero`

---

## Issue 6: Safari Club Tab Rework

**Problem:** Complete rework requested.

**New migration:**
- Create: `supabase/migrations/0179_safari_notice_config.sql`
- Add columns to `venue_config`: `safari_notice_title`, `safari_notice_body`, `safari_notice_enabled`

**Content changes:**
1. Top: admin-configurable notice banner (when enabled)
2. Hero: rectangular animal icons (not circular), fix cut-off images
3. Remove "What makes Safari Club different?" OR rewrite to better copy
4. Update "What it is":
   - Age: 2–5 years
   - Don't mention outdoor
   - Meals: "Healthy snacks & meals (optional)"
5. FAQ rewrite (use better answers)

**Files:**
- Modify: `lib/features/safari/safari_club_screen.dart` (or relevant files)
- Create: migration `0179_safari_notice_config.sql`

---

## Issue 7: Profile Play Passes Empty State

**Problem:** Shows "Couldn't load passes" error. Should show "Get Play Passes / Membership" CTA.

**Files:**
- Modify: `lib/features/profile/profile_screen.dart` Play Passes section

**Changes:**
- Distinguish empty vs error:
  - Error → keep retry message
  - Empty → "No Play Passes yet" + "Get Membership" CTA
- Also make the section still functional if `play_passes` table doesn't exist (graceful degradation)

---

## Verification

- `flutter analyze` clean
- `flutter build ios --debug -t lib/main_prod.dart --dart-define-from-file=env/prod.json` succeeds
- No regressions in existing flows
