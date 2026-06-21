# Play Diaries Scoreboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single self-contained HTML scoreboard page for today's Play Diaries event.

**Architecture:** One HTML file with inline CSS and JavaScript. Four team cards display per-game editable scores and auto-calculated totals. An editable game-name row sits below the cards.

**Tech Stack:** Plain HTML5, CSS3, vanilla JavaScript. No build tools or dependencies.

---

### Task 1: Create the scoreboard HTML file

**Files:**
- Create: `/Users/admin/dev/diariesclub/play-diaries-scoreboard.html`

- [ ] **Step 1: Write the complete page**

Create `play-diaries-scoreboard.html` with:
- Full-screen playful layout optimized for TV/projector.
- Four team cards: Rafi Lions (Brave), Ellie Elephants (Kind), Gerry Giraffes (Curious), Zena Chameleons (Curious).
- Each card has a placeholder image (`assets/play-diaries/<team>.png`), team name, trait, 8 editable score cells, and a large total.
- Editable game-name row with placeholders `Game 1` through `Game 8`.
- JavaScript that:
  - Recalculates totals when any score changes.
  - Clamps scores to 0–5.
  - Saves nothing (local-only).

```html
<!-- File: play-diaries-scoreboard.html -->
<!-- Complete implementation goes here -->
```

- [ ] **Step 2: Verify the file opens in a browser**

Run: `open /Users/admin/dev/diariesclub/play-diaries-scoreboard.html`
Expected: Browser opens and shows the four team cards with editable scores.

- [ ] **Step 3: Test score updates**

1. Click a score cell and type a number between 0 and 5.
2. Expected: The team's total updates immediately.
3. Type a number greater than 5.
4. Expected: It clamps to 5.

- [ ] **Step 4: Commit**

```bash
cd /Users/admin/dev/diariesclub
git add play-diaries-scoreboard.html
git commit -m "feat: add Play Diaries live scoreboard"
```

---

## Self-Review

- **Spec coverage:** All requirements (4 teams, 8 games, 0–5 scores, auto totals, editable game names, TV-friendly, playful style, placeholders for photos) are covered in Task 1.
- **Placeholder scan:** No TBDs or vague steps.
- **Type consistency:** N/A — plain HTML/JS.
