# Big Start Session Card Redesign

## Goal
Make the idle-home “Let’s Play!” card feel more premium, on-brand, and readable while fixing the hero character clipping.

## Current Problems
- The hero character sits above the card (`top: -34`) and is clipped by the app bar / safe area.
- The card uses only a warm coral-to-amber gradient; it doesn’t reflect the four hero/trait brand colors.
- “Let’s Play!” text is relatively small (18 sp) for the primary CTA.
- The card is short, so the hero and the action button compete for the same vertical space.

## Final Design

### Layout
- **Card height:** increase to ~120 dp (from roughly 80 dp).
- **Hero placement:** move the hero image fully inside the card, on the right side.
- **PLAY button:** keep as a white pill, aligned to the bottom-right of the card.
- **Text block:** left-aligned, vertically centered.
- **Card position on screen:** remains just below the app-bar greeting; no extra top spacer is needed because the hero is internal.

### Colors
- Replace the coral-amber gradient with a four-color looping gradient using the brand hero trait colors:
  - Rafi coral `#E8524A`
  - Ellie blue `#5BC8E8`
  - Gerry amber `#F0A830`
  - Zena green `#7BC74D`
- Use the existing `AppColors` constants (`rafiCoral`, `ellieBlue`, `gerryAmber`, `zenaGreen`).
- Keep a subtle white translucent border (`Colors.white.withValues(alpha: 0.35)`) and a soft matching shadow.

### Typography
- **“Let’s Play!”:** 26 sp, weight 900, white with a subtle shadow for readability over the moving gradient.
- **“Tap to start a session”:** 13 sp, weight 500, white at 92 % opacity.
- **“PLAY!” button text:** 13–14 sp, weight 900, dark (`Color(0xFF1A1A2E)`) on white.

### Animation
- Keep the existing `AnimationController` rotating the gradient angle.
- Swap the gradient colors to the four hero colors and adjust stops so the transition feels smooth and continuous.
- Maintain a ~10-second loop duration.

### Character
- Use the same random-hero selection (`rafi`, `ellie`, `gerry`, `zena`) and `assets/hero/$_hero.png`.
- Increase the hero image height to ~64 dp so it feels prominent inside the taller card.
- Remove the external sparkle stars or move them to float near the internal hero.

## Files to Change
- `lib/features/home/widgets/big_start_session_card.dart`

## Out of Scope
- No changes to idle-home spacing, app bar, or bottom nav.
- No changes to active-session “Let’s Play” CTAs (this card is only used on idle home).

## Acceptance Criteria
- [ ] Card is visibly taller and the hero image is fully inside the card.
- [ ] “Let’s Play!” text is larger and remains readable over the gradient.
- [ ] Gradient animates smoothly through the four hero colors.
- [ ] No overflow, clipping, or animation errors on hot reload.
- [ ] `flutter analyze` passes.