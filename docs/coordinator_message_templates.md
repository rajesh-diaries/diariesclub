# Coordinator message templates

Reusable shapes for messages the coordinator sends. **All Claude
Code messages must be in fenced code blocks** so the founder can
copy with one click.

Pattern for every coordinator response:
1. **Plain English (2-3 sentences):** what's happening and why
   this message.
2. **Fenced Claude Code message.**
3. **One sentence on verification:** what we'll check after this
   lands.

---

## 1. Bug report

Use when the founder reports a defect and wants Claude Code to
fix it. Include priority, symptoms, verification SQL (if data is
involved), and the verification steps the founder will run after
the commit.

```
BUG-XXX: <one-line title>

Priority: <P0 blocker / P1 launch-week / P2 v1.1 candidate>

Symptoms:
- <what the founder observed, verbatim if possible>
- <screen / route / RPC involved>
- <reproduction steps if known>

Suspected cause (don't anchor on this — verify first):
- <hypothesis, optional>

Verification SQL (run before fixing, to confirm reality):
```sql
-- e.g. SELECT id, status, created_at FROM <table> WHERE <condition>;
```

After fix, founder will verify by:
1. <concrete step on the device or web>
2. <follow-up SQL if state is involved>

Acceptance: <one-sentence definition of done>

DO NOT:
- Touch unrelated files.
- Add error handling for cases that can't happen.
- "Improve" surrounding code.
- Skip the verification SQL — that's how we caught BUG-048's
  real cause was a stream cache, not the screen.
```

---

## 2. Audit request (don't fix yet)

Use when the founder asks "is X working everywhere" or "are we
sure Y is consistent". The coordinator must NOT let Claude Code
start fixing in an audit. The output is a *table*, not a diff.

```
AUDIT — do not fix yet, return findings only.

Question: <the founder's question, made specific>

Surfaces to check:
- <file or directory 1>
- <file or directory 2>
- <RPC or table if relevant>

For each surface, return one row:

| Surface | Status | Evidence | Notes |
|---|---|---|---|
| path/to/file.dart | OK / BROKEN / UNKNOWN | grep / line ref | one-line note |

Rules:
- Read-only. No Edit, no Write, no migrations.
- If a surface is UNKNOWN, say what would be needed to confirm —
  don't guess.
- One audit, one table. Don't mix in opinions about how to fix
  until I confirm the audit is complete.

After the table lands, I'll review with the founder and decide
which rows become fix tasks.
```

---

## 3. Status check

Use when the founder asks "where are we" or "what's open". The
output the coordinator gives the founder has three buckets per
bug or feature:

- **Shipped + verified** — code merged AND founder confirmed it
  works in the device/web/admin context where it matters.
- **Shipped + untested** — code merged, no founder verification
  yet. THIS BUCKET IS DANGEROUS — call it out explicitly.
- **Open** — no fix yet, or actively in flight.

Format:

```
Status as of <YYYY-MM-DD HH:MM>:

Shipped + verified:
- BUG-XXX <title> — verified <how>
- BUG-YYY <title> — verified <how>

Shipped + untested (these are not done — verify before counting):
- BUG-AAA <title> — needs <verification step>
- BUG-BBB <title> — needs <verification step>

Open:
- BUG-CCC <title> — <state: investigating / blocked / queued>
- BUG-DDD <title> — <state>

Deferred to v1.1 (not open, not in v1 scope):
- <one-liner per item with reason>
```

The "shipped + untested" bucket is the highest-risk one. Always
ask the founder to pick one to verify before pulling new work.

---

## 4. Decision lock (v1 vs v1.1 framing)

Use when the founder is mid-build and a new ask appears that could
expand scope. The coordinator's job is to make the trade-off
explicit, get a decision, then write it down.

```
DECISION — <one-line summary of the choice>

Context:
- <2-3 sentences on why this came up now>

Option A — <name>
- What ships: <concrete deliverable>
- Cost: <hours or days>
- Risk: <one sentence>
- v1 impact: <does this push the launch date?>

Option B — <name>
- What ships: <concrete deliverable>
- Cost: <hours or days>
- Risk: <one sentence>
- v1 impact: <does this push the launch date?>

Recommendation: <A or B, one sentence why>

If you pick <deferral option>, I'll add it to docs/v1_1_backlog.md
with this rationale so we don't re-litigate it next week.

Decide and I'll send the next message to Claude Code.
```

After the founder picks, the coordinator does TWO things in one
turn:

1. Update `SCOPE_LOCKED.md` or `docs/v1_1_backlog.md` with the
   decision + date + one-line rationale.
2. Send the Claude Code message that implements the chosen path.

Decisions that aren't written down get re-asked. Re-asked
decisions cost trust.

---

## 5. Verification message (post-commit)

Use after Claude Code reports a commit landed. The coordinator
asks the founder to verify *one specific thing* before moving on.
Don't ask "does it work" — ask the specific question.

```
Commit <hash> landed: <one-line summary>.

To verify, please:
1. <specific action — open a screen, run an SQL query, send a
   push, scan a QR>
2. <expected result — what you should see>

If you see <expected>, we're good and I'll send the next message.
If you see <anything else>, paste a screenshot or the error and
we'll bisect from there.
```

---

## 6. Bisect message (after 2 failed fixes)

Use when a bug has resisted 2 fix attempts. Don't try a third
guess — strip the screen.

```
BISECT — <BUG-XXX>

Two fix attempts haven't held. Stop guessing. Let's strip the
<screen / widget / flow> down to the simplest version that
reproduces, then add elements back one at a time.

Step 1 — strip:
- Comment out everything in <file:lines> except a placeholder
  Text("alive") widget.
- Confirm the screen renders that placeholder on web AND mobile.
- Commit as "debug(<area>): bisect base — alive".

After founder confirms the placeholder shows on both surfaces,
I'll send the next message: add back element 1.

DO NOT:
- Try to fix the bug in the same commit as the strip.
- Add back more than one element per commit.
- Skip the founder's verification between commits.
```

This pattern caught BUG-048 and BUG-051. Cheaper than the third
guess.
