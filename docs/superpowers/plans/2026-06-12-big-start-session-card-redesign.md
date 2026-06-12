# Big Start Session Card Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the idle-home “Let’s Play!” card so it is taller, uses a four-hero-color moving gradient, places the hero image inside the card, and enlarges the title text.

**Architecture:** A single-widget change in `big_start_session_card.dart`. Keep the existing `AnimationController` and hero-selection logic; only update the layout, gradient colors, typography, and image placement.

**Tech Stack:** Flutter, Dart, `phosphor_flutter`, existing app theme.

---

## File Structure

- `lib/features/home/widgets/big_start_session_card.dart` — the only file modified.

---

### Task 1: Update the gradient to four hero colors

**Files:**
- Modify: `lib/features/home/widgets/big_start_session_card.dart`

- [ ] **Step 1: Import app colors**

  Add at the top:

  ```dart
  import '../../../core/theme/app_colors.dart';
  ```

- [ ] **Step 2: Replace gradient colors**

  Change the `LinearGradient` colors list from coral/amber to the four hero trait colors:

  ```dart
  colors: const [
    AppColors.rafiCoral,
    AppColors.ellieBlue,
    AppColors.gerryAmber,
    AppColors.zenaGreen,
    AppColors.rafiCoral,
  ],
  stops: const [0.0, 0.30, 0.55, 0.80, 1.0],
  ```

  The repeated first/last color makes the loop seamless.

- [ ] **Step 3: Verify animation still loops**

  The existing `GradientRotation(angle)` with the 10-second controller stays in place.

---

### Task 2: Make the card taller and move the hero inside

**Files:**
- Modify: `lib/features/home/widgets/big_start_session_card.dart`

- [ ] **Step 1: Increase card padding and internal Row height**

  Change `padding` to `EdgeInsets.fromLTRB(16, 18, 16, 14)` and wrap the main `Container` in a fixed-height `SizedBox` of 120 dp so the card is consistently tall:

  ```dart
  SizedBox(
    height: 120,
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      ...
    ),
  )
  ```

- [ ] **Step 2: Move the hero image inside the Row**

  Remove the `Positioned` hero that sits above the card. Instead, add the hero image as the middle child of the internal `Row`, between the text column and the PLAY button:

  ```dart
  Image.asset(
    'assets/hero/$_hero.png',
    height: 64,
    fit: BoxFit.contain,
  ),
  ```

- [ ] **Step 3: Remove the external sparkle stars**

  Delete the `_sparkle` widgets and the `Stack`’s `clipBehavior: Clip.none` is no longer needed because nothing overflows.

---

### Task 3: Enlarge “Let’s Play!” text

**Files:**
- Modify: `lib/features/home/widgets/big_start_session_card.dart`

- [ ] **Step 1: Update title style**

  Change the title `TextStyle` to:

  ```dart
  const Text(
    "Let's Play!",
    style: TextStyle(
      color: Colors.white,
      fontSize: 26,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.3,
      shadows: [
        Shadow(
          color: Colors.black26,
          blurRadius: 4,
          offset: Offset(0, 2),
        ),
      ],
    ),
  ),
  ```

- [ ] **Step 2: Keep subtitle readable**

  Leave the subtitle at 13 sp with 92 % white opacity.

---

### Task 4: Run verification

**Files:**
- Modify: none

- [ ] **Step 1: Analyze**

  Run:

  ```bash
  flutter analyze lib/features/home/widgets/big_start_session_card.dart
  ```

  Expected: `No issues found!`

- [ ] **Step 2: Hot-reload check**

  Run the app, navigate to idle home, and confirm:
  - Card is taller.
  - Gradient smoothly animates through four colors.
  - Hero image is fully inside the card and not clipped.
  - “Let’s Play!” text is larger.
  - PLAY button remains tappable.

- [ ] **Step 3: Commit**

  ```bash
  git add lib/features/home/widgets/big_start_session_card.dart docs/superpowers/specs/2026-06-12-big-start-session-card-redesign.md docs/superpowers/plans/2026-06-12-big-start-session-card-redesign.md
  git commit -m "feat(home): redesign Let's Play card with four hero colors and internal hero"
  ```

---

## Self-Review Checklist

- [x] Spec coverage: all design points (taller, colors, internal hero, bigger text) map to a task.
- [x] No placeholders: every step has concrete code/commands.
- [x] Type consistency: uses existing `AppColors` names and existing asset path pattern.
