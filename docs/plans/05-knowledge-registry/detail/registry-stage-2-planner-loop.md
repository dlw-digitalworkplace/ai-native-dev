# PR-06 — The planner closes the skill loop: name skills, propose pin updates and adoptions

_Status: planned. Depends on PR-05. Extends D23 (plan template) + D26/D33 (reviewer oracles).
New D-entry required._

## Context
Skills exist but nothing consumes them deliberately: the planner reads `.claude/skills/` for
grounding, but the plan never records which skills govern the story, so the coder's use of a
pattern is an accident and the reviewer's skill-pattern check is unanchored. Settled design: skill
choice is an **intent decision made in the plan** — named in the sparred contract — after which
implement loads exactly those, and the cold review gains skills-conformance as an explicit,
plan-anchored oracle. The planner also owns the two registry-facing proposals: a submodule **pin
update** (when the registry has a relevant newer skill) and **adoption** (when a local skill
carries the dreamer's `overlaps:` flag — see PR-09) — both as open-question threads, human-gated.

## Keep it simple (non-goals)
- The planner **proposes** pin updates and adoptions; it never executes them. Execution is the
  human resolving the thread + the coder implementing per the merged plan.
- Adoption scope rule (from the design discussion): adopt for **this story's new code only**;
  migrating existing code that followed the old local skill is a separate backlog item, never
  silent scope creep.
- No pin changes at implement time, ever — plan-time pinning keeps the story reproducible against
  one registry SHA.

## Task breakdown
1. `commands/plan.md` step 2 (grounding) — add: scan skill **frontmatter** across
   `.claude/skills/` including `shared/`; when the project has the registry submodule, note the
   pinned SHA.
2. `commands/plan.md` step 3 (template) — **Task breakdown** tasks additionally cite the
   **skill(s)** whose pattern they must follow (exactly parallel to rule citation — same
   mechanism, same rationale from D23: the citation is what makes the coder apply the pattern).
   No new heading.
3. `commands/plan.md` step 4 (threads) — two new thread sources, both explicit either/or:
   (a) *pin update* — "registry has `pattern/x` @ newer content relevant to this story: update the
   submodule pin as task 0 of this story, **or** stay on the current pin?"; (b) *adoption* — when
   a scanned local skill's frontmatter carries `overlaps: pattern/<id>` and the story touches that
   area: "adopt the canonical skill for this story's new code, **or** keep the local one?"
4. `commands/implement.md` A2 — read the **skills each task cites** (alongside its cited rules);
   A4 — obey the cited skill's pattern exactly as cited rules are obeyed.
5. `agents/reviewer.md` — sharpen §2 *Skill-pattern compliance*: for **cited** skills, a violated
   pattern is a **WARNING** anchored to the citation (objective); un-cited skill patterns remain
   the existing judgment-based check. The three oracles are now plan, brief/ACs, cited skills.
6. `design-log/` — D-entry: skill citation in tasks (D23 parallel), plan-time-only pin changes
   (reproducibility), planner-owns-adoption (validation lives in the story; the dreamer only
   flags — cross-ref PR-09's D-entry).

## Assumptions & open questions
- "Registry has newer relevant content" detection without a catalog: `git -C .claude/skills/shared
  fetch && git log HEAD..origin/main -- skills/pattern/` scoped by the skills the plan names —
  cheap and honest. Confirm this is enough (it is a *prompt* for the planner to look, not a diff
  engine).
- Does skill citation belong in **Data contracts**-style conditionality (only when a pattern skill
  is genuinely in play)? Recommend yes — cite only where a pattern governs; never filler.

## Definition of done
- [ ] A plan on a story touching a pattern-governed area names the skill in its tasks; the coder
      follows it; the reviewer can cite the plan when it doesn't.
- [ ] Pin-update and adoption threads appear only when their trigger holds, phrased either/or.
- [ ] A story on a project without the submodule plans byte-identically to today.
- [ ] D-entry recorded.

## Files affected
`commands/plan.md`, `commands/implement.md`, `agents/reviewer.md`, `design-log/`.
