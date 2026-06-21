# Play Diaries Live Scoreboard — Design

**Date:** 2026-06-21  
**Event:** Play Diaries celebration  
**Audience:** 4 groups × 5 families each, projected on a large TV/projector.

## Goal
A single, self-contained local web page that displays the four teams, eight games, and live-updating scores for today's event.

## Teams

| Team | Mascot | Trait | Accent color |
|------|--------|-------|--------------|
| Rafi | Lion | Brave | Purple |
| Ellie | Elephant | Kind | Blue |
| Gerry | Giraffe | Curious | Amber |
| Zena | Chameleon | Curious | Green |

## Layout

- **Big Team Cards Grid**: four large cards side-by-side, optimized for readability from a distance.
- Each card shows:
  - Team mascot photo / emoji
  - Team name and trait
  - Total score (large)
  - Per-game score cells (Game 1–Game 8)
- Below the cards: an editable row to rename Game 1–Game 8.

## Interaction

- Game names and scores are `contenteditable` fields.
- Each game score is constrained to 0–5 points.
- Total score updates automatically as scores change.
- No persistence across page refreshes (intentionally local/simple).

## Files

- `play-diaries-scoreboard.html` — the complete scoreboard page.
- `assets/play-diaries/` — optional folder for team mascot photos (to be provided by the user).

## Technical approach

Single self-contained HTML file with inline CSS and JavaScript. No build step, no backend, no internet required.

## Visual style

Playful and colorful for kids: rounded cards, big numbers, friendly font stack, bright team accent colors, emoji fallback if photos are not yet available.
