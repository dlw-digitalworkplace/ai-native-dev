# D57 — Plan sparring becomes an iterative round loop (amends D44)

- **Area:** Planning (phase 1); config side of the D1–D15 line; amends D44
- **Date:** 2026-09-25
- **Status:** Active

## Decision
**Step 4.5 of `/aind:plan` (the attended "spar" over drafted Assumptions & open questions) becomes
an iterative loop over a shrinking question frontier, capped at 4 rounds, instead of a single fixed
`AskUserQuestion` batch.**

- **Round 1's frontier is the full drafted list** from step 4, presented as one batch exactly as
  before.
- **Each round folds its answers into the plan** the same way as today: an answered item becomes a
  decision in the plan body (provenance-noted), a deferred item stays untouched in *Assumptions &
  open questions* and is never re-asked — it falls through to step 5's thread-what's-left behavior.
- **After folding, the planner re-scans — narrowly.** It looks only at the plan areas the round's
  answers actually touch (task breakdown, data contracts, AC coverage, non-goals) for an either/or
  question that only became askable because of an answer just given. This is a targeted follow-up
  bounded to those four areas, never a full re-audit of the plan and never an open-ended
  "is this the right idea" question. Whatever it finds becomes the next round's frontier, phrased as
  an explicit either/or exactly per step 4's existing rule.
- **The loop stops** when a round's re-scan finds nothing new (frontier empty — this can happen on
  round 1) or after 4 rounds, whichever comes first. Either ending degrades identically to the
  existing behavior: everything still open when the loop stops stays in *Assumptions & open
  questions* and is threaded in step 5 exactly as before. Hitting the cap is not an error.
- **Unchanged:** the channel is still `AskUserQuestion`; this still only applies in **attended**,
  **non-trivial** create-mode runs (D44's triage/fast-track is untouched); **headless** mode,
  **revise** mode (Section B), and the **local same-branch flow** (Section C, which references step
  4.5 by number) are all untouched — local inherits the loop for free, with no separate edit.
- **No new skill.** This is judgment/conversation logic with exactly one caller
  (`commands/plan.md`), not reusable deterministic mechanics — it doesn't fit this repo's
  `skills/*/SKILL.md` convention (which wraps scripted mechanics for reuse across commands).
- **No new config key.** The 4-round cap is fixed in the command's own instructions, not a
  `.claude/aind.settings.json` key — no one has asked for it to be tunable yet, and `planning.mode`
  (D44) is untouched.

## Rationale
D44's spar already conceded the gap this closes: its own text allowed "a second [batch] only if an
answer invalidates other items" but never described how that second round should work, or bounded
what it could ask. A developer who is present to spar round 1 is present for rounds 2–4 too, so
resolving a newly-surfaced choice live — rather than silently picking one, or leaving it to a cold
PR thread the same session already had the context to settle — keeps D44's real invariant intact:
**no silent decision.**

The 4-round cap and the four-area re-scan restriction both exist to stop this from becoming
something it isn't: an open-ended interrogation of the idea itself. That would fight the planner's
existing bias toward the simplest change that satisfies the acceptance criteria and its explicit
non-goals discipline — the loop's job is to finish specifying an already-scoped plan, not to
relitigate its scope. Capping at 4 rounds (rather than looping until truly exhausted) accepts that
trade-off deliberately: it bounds worst-case chattiness while still covering the realistic case of
one or two follow-on questions cascading from an early answer.
