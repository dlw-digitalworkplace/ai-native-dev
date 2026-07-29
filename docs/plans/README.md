# AIND feature plans — index

_One plan per feature, **one subfolder per plan** (`docs/plans/<feature>/plan.md`): each is a
standalone, separately-discussable PR that delivers vertical value when merged and does not block
the others. Written 2026-07-13 against v0.12.0 (design log through D35); **re-based 2026-07-28
onto v0.18.0 / D42** (config now in `aind.settings.json` per D41; PR mechanics via the `aind-forge.sh`
adapter per D36). Sources: the flow-design sessions of 2026-07-13 and `docs/skill-registry-design.md` (v2)._

## The five features

| # | Plan | Feature | Standalone value when merged |
|---|------|---------|------------------------------|
| 01 | `01-approve-plan-merges/plan.md` | `/approve-plan` approves + merges the plan PR (gate = threads resolved) | One command closes the plan phase; no UI round-trip, no repo/ADO drift window |
| 02 | `02-ado-native-state-mirror/plan.md` | Mirror AIND status into the native ADO State field | The board reflects the flow — PMs/functionals see progress without opening the repo |
| 03 | `03-scribe-docs-step/plan.md` | SCRIBE: evidence-gated docs step in /implement + reviewer check | No merged change is undocumented (on projects with a docs practice) |
| 04 | `07-plan-sparring-mode/plan.md` | Plan co-forming: interactive sparring when attended, threads when headless | Planning becomes "let's form this together"; assumption threads shrink to what's genuinely open |
| 05 | `05-knowledge-registry/plan.md` | **The knowledge registry — the whole closed loop, one PR** (+ prerequisite registry repo) | Skills and project knowledge cross project boundaries: reuse, discovery, who-knows-what |

All four flow features (01–04) are mutually independent and independent of 05 — open in any order.
Post-review suggested order: **01 → 02 → 04 → 03 → 05** (04 moved up after the draft-then-spar
redesign collapsed its complexity; 03 after its objective/subjective docs split is now explicit).
Feature 05 is one PR built commit-per-stage (wiring → planner/reviewer → dossier → dreamer →
drift), with stage detail in `05-knowledge-registry/detail/registry-stage-*.md`; it blocks on three human decisions
(registry host, maintainer names, IP basis) and on standing up the `aind-knowledge` repo first
(stage 0, a separate repo). Its dominant risk is organizational adoption, not code — see the
plan's "Success criteria beyond code" section.

## Done upstream (removed from this set)
- **Host-neutral code repo (GitHub or ADO Repos)** — was plan 11 here; **implemented upstream as D36**
  (the `AIND_CODE_HOST=github|ado` forge adapter, `scripts/aind-forge.sh`), which covers exactly what
  that plan proposed. The plan file was dropped; nothing to propose.

## Cross-cutting rules for every PR
- **No shared-file contention (this is what keeps the PRs non-blocking).** Each PR touches only its
  own `docs/plans/<feature>/` subfolder plus the harness code it changes. Specifically:
  - **Design log:** each PR adds its decision as a **new file** `design-log/D<N>-<slug>.md` (+ one
    row in `design-log/README.md`) — never an edit to a shared monolith. Numbers (D43+, since the log
    is through D42) are assigned **in merge order** (at merge time, so two open PRs don't both claim
    D43). Where a plan supersedes
    or amends a recorded decision (01 vs the approve-plan recorder shape; 05 vs D25's plugin delivery
    and D16/D30's one-repo dreamer boundary), the new entry says so explicitly and marks the old
    file's `Status` line — the one allowed edit to an existing decision file.
  - **Version:** do **not** bump `plugin.json` / `.github/plugin/plugin.json` `version` in a feature
    PR — versions are bumped in a separate release commit on `main`.
- **Friction ledger:** every D-entry states the feature's per-story decision delta — which human
  decisions it adds, removes, or moves down into the harness, who pays and who benefits, and when
  (today's story vs future stories vs the org). Time-shifted value is legitimate; unaccounted value
  is not. Baseline **decisions-per-story** from existing testbed stories (assumption threads,
  review passes, tiebreaks, confirms, curation approvals — all countable from PRs + the status
  trail + the lessons branch) before this set merges; the flow-level count must not trend up
  without an explicitly accepted value trade-off.
- **Benefit signal (shifted-cost features):** when a feature asks one person to pay now so another
  person or a future story benefits later, its plan names the observable signal that will prove the
  benefit materialized — countable from **existing artifacts only** (PR findings, thread
  accept/defer rates, citations, spar resolutions), checked at **existing cadence points** (dream
  cycles, tripwire dates), never per-story reporting. A shifted-cost feature without a named signal
  is treated as process debt. The ledger itself must not become a tax.
- **Portability question, asked in every D-entry:** does this strengthen the harness abstraction
  or a specific host dependency? Host couplings are allowed but must be named (the current ledger:
  PR mechanics now go through the host-agnostic `aind-forge.sh` adapter (D36), so a new host coupling
  should be added there, not hardcoded to `gh`; AskUserQuestion — capability fork noted in plan 04).
  The knowledge layer stays host-free by design (files, frontmatter, git).
- Registry-optional invariant: a project without `AIND_KNOWLEDGE_REPO` runs the flow byte-identically.
- Live validation per PR follows the repo's habit: offline-validate mechanics, then one real story
  on the testbed before calling it done.
