# PR-05 — The knowledge registry: the whole closed loop, one feature

_Status: planned. ONE PR to this repo (plus the prerequisite registry repo itself). The feature is
the closed loop — shared skills consumed at plan time, produced at dream time, dossiers published
and kept fresh. A partial loop has no standalone value, so it ships whole. **Success depends
primarily on organizational adoption and maintainer stewardship, not on technical completion of
the loop** — good rollout + mediocre implementation beats the reverse; the deck / AI-Experience
rollout owns this PR's dominant risk, and the section "Success criteria beyond code" below is
where that risk is tracked. Design authority: `docs/skill-registry-design.md` (v2). Stage-level
detail: `docs/plans/05-knowledge-registry/detail/registry-stage-*.md`._

**Re-based 2026-07-28 onto v0.18.0 / D42.** Three reconciliations with work that landed since
drafting: **(1) config** — `AIND_KNOWLEDGE_REPO` is shared project config, so it lives in
`.claude/aind.settings.json` (D41), not `aind.env`; onboard/kickstart *ask + write* the key (they no
longer copy `.sample` files). **(2) registry PRs** (stages 3–4) route through the `aind-forge.sh`
adapter (D36) — **but with a registry-host selector distinct from the project's `AIND_CODE_HOST`**,
because the registry repo may live on a different host than the project's code (prerequisite decision
#1). **(3) submodule under worktrees** (D37/D39) — a fresh per-phase worktree does not init
submodules and `copyFiles`/`symlinkDirs` don't cover them, so stage 1 must handle submodule init in
worktree mode. New D-entry required (D43+).

## Context
Today delaware projects are islands: no skill crosses a project boundary, no consultant can ask
"which projects use .NET 10, who knows MSAL, what does Azelis actually do." The feature: a private
`aind-knowledge` git repo (pattern skills + project dossiers), consumed as a pinned submodule at
`.claude/skills/shared/`, wired into the flow at three points — the **planner** names skills and
proposes pin updates/adoptions, the **reviewer** checks conformance to cited skills, the
**dreamer** diffs local skills against the registry (promote / improve / flag) and drift-checks
the dossier. Value exists only when the loop closes; that is why this is one PR.

## Prerequisite decisions (block the whole PR — decide first)
1. **Registry host** — ADO or GitHub (pick the one the team authenticates against daily).
2. **Maintainer names** for the registry CODEOWNERS (`pattern/**`, per-`project/<name>/`).
3. **IP basis** for the Azelis dossier (contractual green light or sanitization rule).

## Stage 0 — the registry repo itself (separate repo, done first)
Create `aind-knowledge`: README, CODEOWNERS, branch protection; seed with the 3 generalized Azelis
pattern skills (core + marked slots, provenance, maintainer-reviewed) and the Azelis dossier
(`maturity: seed`, IP-basis line, people with as-of date). Acceptance: a cold clone + an agent
answering "which projects use .NET 10 / who worked on Azelis" from frontmatter alone.
→ detail: `detail/registry-stage-0-repo-seed.md`

## The AIND PR — five stages, one commit per stage
_Stage 2 is the one legitimate pause point if the PR grows too heavy mid-build: repo + wiring +
planner/reviewer consumption is a coherent consume-only registry; stages 3–5 add the production
side. Pausing there is a fallback, not the plan._

**Stage 1 — wiring.** Optional `AIND_KNOWLEDGE_REPO` config (in `aind.settings.json`, D41);
onboard/kickstart offer the
`git submodule add` (human-gated, **recommended-yes by default** — the optionality is technical,
not a neutral stance; adoption is the point); preflight probes (never blocking); Copilot-side
frontmatter scan rule; GETTING-STARTED section. → `detail/registry-stage-1-submodule.md`

**Stage 2 — planner + reviewer (consumption).** Plan tasks cite the skill(s) they must follow
(parallel to rule citation); pin-update and adoption proposals as either/or threads (adoption only
on a dreamer-set `overlaps:` flag, new-code-only, migration = separate backlog item); implement
reads cited skills; reviewer treats cited-skill violations as objective WARNINGs (third oracle:
plan · brief · cited skills). Pin changes at plan time only. Packaging: the registry-facing
procedure ships as a **plugin skill** the planner loads on demand — one paragraph in `plan.md`,
not a page (`plan.md` is already the repo's heaviest prompt; progressive disclosure is the
weight control). → `detail/registry-stage-2-planner-loop.md`

**Stage 3 — dossier publish.** New `/aind:publish-dossier` + `scripts/aind-dossier.sh`; distills
local understanding into `skills/project/<name>/SKILL.md` (v2 §5 sections + tags), PR to the
registry, IP-basis required. Timing: brownfield may be offered post-onboard; greenfield never at
kickstart — earliest after the first merged PR (`/complete` makes the offer). Always
`maturity: seed`. → `detail/registry-stage-3-dossier-publish.md`

**Stage 4 — dreamer registry diff (production).** Analyze gains promote / improve / flag
dispositions (never adopt — detection where visibility is, disposition where validation is);
author generalizes into a registry worktree; the dream cycle can open at most one registry PR
alongside the config PR (third human gate = registry CODEOWNERS). Flag = `overlaps: pattern/<id>`
frontmatter on the local skill, via the normal local config PR — Stage 2's planner consumes it.
→ `detail/registry-stage-4-dreamer-diff.md`

**Stage 5 — dossier drift-check.** Dream re-runs the onboard lenses in diff mode against the
published dossier; drift → registry PR updating exactly the touched sections/tags; `seed →
validated` after ~3 merged stories with no substantive drift. People-data freshness is explicitly
not solved (as-of date is the honesty mechanism). → `detail/registry-stage-5-drift-check.md`

## Keep it simple (non-goals) — from the v2 design, held across all stages
No resolver, no lockfile, no semver/`versions/`, no `catalog.json`, no eval CI, no MCP layer, no
`workflow/` kind in the registry, no auto-publish, no adoption by the dreamer, no pin changes at
implement time.

## The one invariant to test at every stage
**Registry-optional:** a project without `AIND_KNOWLEDGE_REPO` behaves byte-identically to today —
plan, implement, review, dream all unchanged.

## Design-log obligation
One PR, several D-entries (in the log's style): submodule-as-distribution (supersedes D25's
plugin delivery for org knowledge), skill citation in tasks (D23 parallel) + plan-time pinning,
dossier publish timing (understanding ≠ dossier; story = validation vehicle), the dreamer's
amended one-repo boundary (D16/D30) + why adopt is excluded, drift-check + maturity semantics.

## Definition of done (the loop, end to end, on the testbed)
- [ ] Onboarded project has the pinned submodule; shared skills discoverable on both hosts.
- [ ] A story in a pattern-governed area: plan cites the skill → coder follows it → reviewer can
      anchor a WARNING to the citation.
- [ ] `/publish-dossier` produces a maintainer-reviewable dossier PR (and refuses pre-first-merge
      on greenfield).
- [ ] A dream cycle on a novel local pattern yields a promote PR to the registry; on a duplicate,
      an `overlaps:` flag the next plan run surfaces as an adoption proposal.
- [ ] A story that changes the stack yields a drift cluster and a dossier-update PR.
- [ ] A project without the registry config: byte-identical behavior everywhere.
- [ ] All D-entries recorded.

## Success criteria beyond code (the actual risk)
**Developer-value ordering: this feature is pitched consumption-first, always.** The first promise
is that today's story starts smarter — plans citing proven patterns instead of re-deriving them.
Contribution (dossiers, promotion, drift) is secondary and must stay low-ceremony; the moment
contribution pressure is more visible to a dev than consumption value, adoption is expected to
fail and developers to route around it.

The DoD above proves the loop works; this section is what proves the feature worked. Known
existential risk, tracked, with a date:
- A **second project** onboards with the submodule within ~90 days of merge.
- The **first non-seed registry PR** (promote/improve/dossier) comes from someone other than the
  original author.
- The named maintainers have **actually reviewed** at least one registry PR each.
- **Consumption signals** (from plan artifacts, at dream-cycle cadence): plans citing shared
  skills; cited skills preventing reviewer pattern-warnings/rework; accept-vs-defer rates on
  pin-update and adoption threads. Consumption signals trending to zero while contribution
  machinery runs = the failure mode, regardless of registry content volume.
If none of these fire by the tripwire date, the registry is declared **dormant-by-design** —
revisit the rollout (the deck's AI-Experience vehicle), not the code. A lightly-used registry with
no stewardship is worse than none; do not let it zombie.

## Files affected (whole PR)
`project-template/CLAUDE.md`, `project-template/aind.env.sample`, `commands/onboard.md`,
`commands/kickstart.md`, `commands/plan.md`, `commands/implement.md`, `commands/complete.md`,
`commands/dream.md`, `commands/publish-dossier.md` (new), `agents/reviewer.md`,
`agents/dreamer.md`, `scripts/aind-preflight.sh`, `scripts/aind-dossier.sh` (new),
`scripts/aind-dream.sh`, `GETTING-STARTED.md`, `design-log/`, `design-doc.md`, `docs/index.html`.
