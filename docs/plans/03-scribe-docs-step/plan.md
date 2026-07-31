# PR-03 — SCRIBE: an evidence-gated documentation step in /implement

_Status: planned (re-based 2026-07-28 onto v0.18.0 / D42 — no config/forge dependency; only a
step-renumbering caveat, see the task notes). Restores the one Azelis-v3 capability with no AIND
equivalent (SCRIBE), reshaped to AIND's conventions. New D-entry required (D43+)._

## Context
Nothing in the flow updates documentation. Azelis v3 had SCRIBE (digest + commit walkthroughs)
between review and PR composition; AIND dropped it. Decision from the flow redesign: documentation
is authored **inside the implement phase, before the PR exists**, so docs travel in the reviewed
diff ("cold-signed + docs") and no merged change is undocumented.

## Keep it simple (non-goals)
- **Evidence-gated, exactly like testing (D33):** no docs practice in the project (no docs rule, no
  `docs/` the rules point to, no doc skill) → no docs step, and the coder never bootstraps a docs
  system per story. This is a config fact read from `.claude/`, not a per-story invention.
- No separate SCRIBE agent/subagent. Documentation is warm authoring by the coder (the D20/D24
  line: cold = independent verification only). "SCRIBE" survives as the *step name*, not an actor.
- No generated changelogs/digests in v1 (Azelis's digest.md stays retired; the dossier covers the
  org-level need per the registry design).

## Implementation approach
Mirror the D33 testing shape at every layer: the **planner** sets a docs expectation when the
project has a docs practice, the **coder** authors, the **reviewer** checks.

## Task breakdown
1. `commands/plan.md` — in the plan template's **Definition of done** derivation, add: when the
   project's rules/skills define a docs practice, include the doc updates this change requires as
   DoD items (which docs, what must be true). When there is no docs practice: nothing (no heading,
   no filler) — the D23 drop-rather-than-fabricate discipline. Size doc items minimally — the
   smallest doc change that keeps the named docs true; small stories must not grow ceremonial doc
   items.
2. `commands/implement.md` — new **"Document (SCRIBE)"** step between polish and self-check/build:
   if the plan's DoD carries doc items, update exactly those docs, following the project's docs
   rule; commit. No structural/behavioral code change in this step. _(Re-base note: `implement.md`
   grew since drafting — worktree grounding (D37/D40) and D42 telemetry brackets — so re-derive the
   exact step letter against the current file; the **position** (after polish, before build) is what
   matters, not the label `A5.5`.)_
3. `agents/reviewer.md` — §2 gains a **Docs** dimension: the D33 test triple, ported. **Coverage**
   — a DoD doc item with no corresponding doc change in the diff → **WARNING** (objective: the DoD
   names it). **Fidelity** — a doc statement the diff's code contradicts → **WARNING** (objective;
   stale docs mask defects exactly as wrong-assertion tests do). **Quality** — "could be written
   better" → **SUGGESTION**, never gates. This split is what keeps the docs check from becoming a
   disguised judgment gate and the review loop from deadlocking on prose taste. When the plan
   carried no doc items, there is nothing to check — never invent a docs requirement. _(Re-base
   note: `reviewer.md` §2 now also carries the D38 merge-conflict dimension on top of the D33 test
   triple — append **Docs** as an additional dimension to the current list.)_
4. `design-log/` — D-entry: docs-as-DoD-items (reusing D33's strategy→author→review shape), why
   no agent, why pre-PR placement (docs ride the reviewed diff).

## Assumptions & open questions
- Should the planner get a first-class "Docs" heading instead of DoD items? Recommend DoD items —
  no new plan section (the D33 precedent folded testing into existing headings).
- README/API-reference drift *outside* the story's touched area: out of scope (reviewer's
  "respect scope" constraint §4 already covers noting-not-gating).

## Benefit signal (shifted-cost accounting)
Coder pays now; reviewer and future maintainers benefit later. The proof, from existing artifacts
at dream-cycle cadence: (a) reviewer **coverage/fidelity findings on docs** — each one is a defect
the step caught that would otherwise have merged; (b) **ceremonial doc items** — doc DoD items
threaded/deferred as unnecessary during plan review or spar. If (b) rivals (a), the sizing rule is
failing and the step is process debt — tighten or retire it.

## Definition of done
- [ ] On a project with a docs rule: plan DoD names doc updates; coder commits them pre-PR;
      reviewer blocks (WARNING) when missing.
- [ ] On a project with no docs practice: zero behavior change, zero filler in plans.
- [ ] D-entry recorded.

## Files affected
`commands/plan.md`, `commands/implement.md`, `agents/reviewer.md`, `design-log/`.
