# Changelog

All notable changes to the **aind** plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Each version matches the `vX.Y.Z` GitHub Release that
`deploy.sh` cuts from the `version` in `.claude-plugin/plugin.json` (kept in sync with
`.github/plugin/plugin.json`). Design rationale for each change lives in `design-log.md`, cited by
decision ID (e.g. D23).

> Versions before 0.4.0 were reconstructed retroactively from git history and the design log.

## [0.4.0] — 2026-06-30

### Added
- **Richer plan template** so a plan carries enough for a coding agent to execute without
  re-deriving the planner's decisions, while staying domain-agnostic (D23):
  - **Keep it simple** — explicit non-goals plus the simpler option chosen over a heavier one (a
    guard against over-engineering); dropped when there is nothing real to fence off.
  - **Data contracts** *(conditional)* — only when a change crosses a boundary (API↔client,
    service↔service, module↔module), pins the exact shape both sides must agree on (field names,
    types, nullability, mapping) in the project's own language(s); never fabricated otherwise.
  - **Task breakdown** — a dependency-ordered task list whose tasks **cite the project rule files
    (`.claude/rules/*.md`)** they must obey, rather than being filed under fixed domain buckets.
  - **Considerations** — non-blocking reviewer context (security, performance, edge cases).
  - **Definition of done** — a checklist whose every item traces to a real source (an acceptance
    criterion, a cited rule's "what done looks like" bar, an invariant, or a ratified testing
    recommendation).
- Planner now grounds in the project's **skills** and **`docs/`** (not just rules + code) and
  respects a multi-project / deployment topology where the rules define one.

### Changed
- Planner biases toward the **simplest change that satisfies the acceptance criteria** — no
  speculative abstraction, configurability, or generalization the story doesn't call for.
- Sharpened the **Considerations vs. Assumptions & open questions** boundary: anything a reviewer
  could reasonably want done differently is an open question (→ a resolvable thread / merge gate),
  not a consideration — when in doubt, prefer the open question.
- Revise mode (a `/aind:plan` re-run) keeps the new plan sections honest, not just the assumptions.

### Validated
- `/aind:plan` with the enriched template — live-validated on a real story.
- `/aind:approve-plan` — live-validated end-to-end: refuses while the plan PR is unmerged; once
  merged, sets `Ready for implementation` and runs the plan-branch cleanup.

## [0.3.0] — 2026-06-30

### Added
- **GitHub Copilot CLI as a second host** (D22) — the plugin runs on both Claude Code and Copilot
  CLI from one repo with no behavior fork. A second manifest (`.github/plugin/plugin.json`) and
  per-tool hooks (`hooks.claude.json` / `hooks.copilot.json`) absorb the only incompatibility;
  `commands/`, `skills/`, and `scripts/` are shared unchanged.

### Notes
- On Windows, Git's `bash` must win on PATH over `System32\bash.exe` (the WSL launcher) — prepend
  `C:\Program Files\Git\bin` in the PowerShell `$PROFILE`.

## [0.2.0] — 2026-06-29

### Added
- **Plan phase.** `/aind:plan` delivers an implementation plan as a GitHub **plan PR**
  (`plans/<id>/plan.md`), with assumptions and open questions posted as **resolvable review
  threads** that gate the merge, plus the `AIND-LINKS` artifact-linking block (D5, D10, D17).
- `/aind:approve-plan` close-out — sets `Ready for implementation` and cleans up the plan branch.
- **Plan-revision loop** (D21) — re-running `/aind:plan` on a story that already has an open plan
  PR folds the PR's review feedback into the same PR instead of opening a second one.

## [0.1.0] — 2026-06-26

### Added
- Initial **aind** plugin — the AI-Native Dev flow foundation for Azure DevOps + GitHub.
- **Intake** agent (`/aind:intake`) — scores a story against the readiness rubric, posts a signed
  verdict, and swaps the single `AIND status` tag (D2, D4, D11).
- **Onboarding** agent (`/aind:onboard`) — bootstraps a project's `.claude/` config from its
  codebase via three-lens, evidence-only rule discovery (D18).
- Shared scripted ADO/GitHub mechanics (`scripts/`, surfaced via `skills/`), signing-enforcement
  hooks, and the seed intake rubric.
- `deploy.sh` publishing — a root-structured release-asset zip plus the Pages flow diagram.
