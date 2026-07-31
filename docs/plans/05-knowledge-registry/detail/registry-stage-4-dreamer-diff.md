# PR-09 — Dreamer registry diff: promote, improve, flag

_Status: planned. Depends on PR-05 (submodule) + WS-00; pairs with PR-06 (the planner consumes the
`overlaps:` flag this PR produces). Extends D30's dreamer scope across the repo boundary — the
D-entry must amend the D16/D30 "one repo, one PR" boundary explicitly._

## Context
The dreamer improves one project's `.claude` and parks everything else. Settled design: dreaming
gains a **registry diff** — compare the project's local skills (and lesson-validated patterns)
against `aind-knowledge` and dispose each finding: **promote** (fills a registry gap → generalize:
core vs marked specialization slots, provenance kept → PR to the registry), **improve** (overlaps
a canonical skill and the local version learned something → propose a delta to the canonical skill,
not a duplicate), **flag** (local skill duplicates a canonical one → write `overlaps: pattern/<id>`
into the local skill's frontmatter via the normal local-`.claude` PR — the dreamer detects,
**never adopts**; adoption is the planner's, in-story, PR-06). Diff-first prevents the
fork/duplicate explosion a write-only promotion loop would create; this realizes the parked D25
path through the registry.

## Keep it simple (non-goals)
- The dreamer never edits the submodule in place and never merges anything: registry changes are
  PRs to the registry repo, gated by its CODEOWNERS maintainer — a **third human gate**, on top of
  the existing two.
- No adoption disposition (planner's job, PR-06). No dossier work here (PR-10).
- Skip the entire pass when the project has no registry submodule — zero behavior change.

## Task breakdown
1. `agents/dreamer.md` — `analyze` mode gains a **registry-diff step** (after re-grounding): read
   local `.claude/skills/*` vs `shared/skills/pattern/*` frontmatter+bodies; emit registry
   clusters in the same `CLUSTERS:` structure with a new `disposition: promote | improve | flag`
   and `target:` pointing at a registry path (promote/improve) or the local skill file (flag).
   Judgment bar: promote/improve need lesson-corroboration or verifiable substance (the D30
   severity×recurrence×factualness rubric applies unchanged); flag is factual (overlap exists) and
   cheap. `author` mode: `flag` clusters edit the local skill frontmatter (inside the existing
   `.claude` boundary — no new permissions); promote/improve clusters author files in a **registry
   worktree** the orchestrator prepares (see 2), generalizing per the v2 design (slots, provenance).
2. `commands/dream.md` + `scripts/aind-dream.sh` — orchestrator prepares/commits/pushes a registry
   branch and opens the registry PR (`aind-dream.sh registry-start` / `registry-open-pr`, mirroring
   the existing `start`/`open-pr` for the local config PR). Since D36 the config-PR opener is already
   an `aind-forge.sh` wrapper, so `registry-open-pr` opens through the **same forge verbs** — driven
   by the **registry-host selector** (distinct from the project's `AIND_CODE_HOST`; the same one
   stage 3's `aind-dossier.sh` uses). Curation gate (§2) now shows registry clusters alongside config
   clusters; **one dream cycle = at most one config PR + one registry PR**.
3. `agents/dreamer.md` boundary section — amend: the registry worktree is in-scope for
   promote/improve authoring; everything previously out-of-bounds stays out-of-bounds.
4. `design-log/` — D-entry: the registry diff (three dispositions and why adopt is excluded —
   detection where visibility is, disposition where validation is), the amended one-repo boundary
   (now: local config PR + registry PR, each human-gated), maintainer gate as the registry-side
   control.

## Assumptions & open questions
- Generalization quality at n=1 project: with only Azelis-derived seeds, "improve" will be rare
  and "promote" risks near-duplicates of the seed set — acceptable; the maintainer gate is the
  control, and the diff itself prevents blind duplication.
- Meta-lessons routing (harness-improvement backlog in the registry, v2 §6.4): fold in here as a
  fourth cheap disposition (`meta` → a file under a registry `backlog/`), or keep parked in
  `.aind/parking-lot.md`? Recommend keep parked in v1 — one new boundary crossing per PR.

## Definition of done
- [ ] On a project with the submodule and a genuinely novel local pattern: analyze proposes
      `promote`; after curation, author produces a generalized skill (slots + provenance) and the
      cycle ends with a registry PR the maintainer can review.
- [ ] On a local skill duplicating a canonical: analyze proposes `flag`; the local config PR
      carries the one-line frontmatter addition; PR-06's planner picks it up on the next story.
- [ ] No submodule → dream cycle byte-identical to today.
- [ ] D-entry recorded (boundary amendment explicit).

## Files affected
`agents/dreamer.md`, `commands/dream.md`, `scripts/aind-dream.sh`, `design-log/`.
