# PR-10 — Dossier drift-check in the dream cycle

_Status: planned. Depends on PR-08 (a dossier must exist) and PR-09 (the registry-PR plumbing in
the dream cycle). New D-entry required._

## Context
A published dossier rots silently: integrations get added, stacks bump, cross-cutting rules
change, and the registry copy stays frozen at publish time. Settled design: the anti-rot mechanism
is a **drift-check inside dreaming** — out-of-band curation with human approval, the same shape as
dreaming itself. It also owns maturity promotion: `seed → validated` once the dossier has survived
real stories. Known limit (stated, not papered over): it runs only where the harness runs; a
dormant project's dossier freezes as a valid snapshot — except people data, which rots on
organizational time and which no code-driven check can see.

## Keep it simple (non-goals)
- No CI, no schedules, no webhooks: the check rides the existing manual `/dream` cadence.
- People-data freshness is explicitly NOT solved here (the as-of date is the honesty mechanism).
- No dossier rewrites: smallest-diff updates, matching the dreamer's existing author discipline.

## Task breakdown
1. `commands/dream.md` — new optional step (skipped when no submodule or no published dossier for
   this project): include the current dossier in the analyze pass input.
2. `agents/dreamer.md` — `analyze` gains a **drift-check**: re-run the onboard three lenses
   (technical layers / cross-cutting / functional-domain) in **diff mode** against the published
   dossier's sections and frontmatter tags: new or removed integrations, stack changes, changed
   cross-cutting rules, patterns adopted/dropped (`patterns_in_use` vs the plan/skill citations
   now in the repo). Emit `disposition: dossier-drift` clusters (same structure); `author` edits
   the dossier in the registry worktree (PR-09's plumbing), updating `updated:` and the touched
   sections/tags only. **Maturity promotion:** when the diff finds the dossier substantially
   accurate after ≥N merged stories (default 3) since publish, propose `maturity: seed →
   validated` as its own low-risk cluster.
3. `design-log/` — D-entry: drift-check as the dossier's anti-rot mechanism, the
   harness-activity coupling limit and the dormant-project snapshot argument, maturity semantics.

## Assumptions & open questions
- N for maturity promotion (default 3 merged stories): tune later; any value beats never.
- Story-count source: `plans/*/plan.md` dirs on the integration branch newer than the dossier's
  `updated:` — cheap and adequate? Recommend yes.

## Definition of done
- [ ] After a story that adds an integration/dependency the dossier doesn't mention: the next
      dream cycle proposes a drift cluster; approval yields a registry PR updating exactly the
      affected sections + tags.
- [ ] After N merged stories with no substantive drift: the maturity-promotion cluster appears.
- [ ] No dossier / no submodule → dream cycle unchanged.
- [ ] D-entry recorded.

## Files affected
`commands/dream.md`, `agents/dreamer.md`, `design-log/`.
