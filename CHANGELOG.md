# Changelog

All notable changes to the **aind** plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Each version matches the `vX.Y.Z` GitHub Release that
`deploy.sh` cuts from the `version` in `.claude-plugin/plugin.json` (kept in sync with
`.github/plugin/plugin.json`). Design rationale for each change lives in `design-log.md`, cited by
decision ID (e.g. D23).

> Versions before 0.4.0 were reconstructed retroactively from git history and the design log.

## [0.6.0] — 2026-07-01

### Added
- **Build phase — code reviewer (Phase 4).** After `/aind:implement` opens the code PR it now drives
  an **independent code review to a verdict** (D26). A **cold reviewer subagent** (`agents/reviewer.md`,
  `aind-reviewer`, strong-model override) is spawned from inside the command with **only** the
  work-item id + PR number — coldness is structural: it re-grounds from artifacts (the PR diff, the
  merged plan, the project's rules and skills), never the coder's context. It challenges the diff
  against the merged plan **and the full project rule + skill set** (an asymmetry with the coder,
  which obeys only each task's *cited* rules), posts resolvable PR threads for blocking findings plus
  a summary comment, and returns a structured verdict. The **warm coder** fixes or rebuts between
  passes — **up to 3 passes**, early-exit on a clean pass.
- `scripts/aind-review-pr.sh` — PR-review mechanics (`fetch` / `digest` / `summary` / `thread` /
  `resolve` / `reply`), each a single allow-listed command so a fresh subagent context is not
  re-prompted per call. It posts the verdict as a comment (never a GitHub self-approval, which the
  same-user local mode forbids); loop termination is driven by the returned verdict.
- Three-tier severity with a deliberately strict gate: **CRITICAL and WARNING both block**; only
  SUGGESTION is non-blocking (recorded in the PR summary body). An objective/taste split keeps the
  loop from deadlocking on nits, and **scope creep beyond the plan is a finding**.

### Changed
- `/aind:implement` gains the review loop (adds `Task` to its allowed-tools) and now ends at
  **reviewer approval or a human tiebreak**, not at PR creation. The `AIND status` tag stays
  `In implementation` throughout — the code PR owns all review iteration.

### Notes
- **Escalation:** after 3 deadlocked passes a human tiebreak is signalled by a PR summary **and** a
  signed `reviewer` ADO comment; the tag is **not** moved (a disagreement is not a stuck-state). A
  reviewer that cannot ground returns `CANNOT-REVIEW` → the coder raises `Needs attention` (D12).
- Scope still stops before **merge** and the terminal `Implementation complete` write (D13); test
  authoring stays deferred (D8/D9). Acting on a non-blocking suggestion or a human's verdict against
  an already-open code PR (a **code-revision loop**, the twin of the plan-revision loop) is a noted
  next iteration.

### Validated
- The review loop — live-validated on a real story: the **clean-approval** path (`CLEAN` on pass 1,
  tag unchanged, PR ready for a human merge) and the **blocking** path (findings posted as resolvable
  threads, coder fix, re-review). Offline: `aind-review-pr.sh` `digest` parsing and the `fetch`
  link-parse path.

## [0.5.0] — 2026-06-30

### Added
- **Build phase — coding agent.** `/aind:implement <work-item-id>` turns an approved, merged plan
  into a GitHub **code PR** (D24). It is a warm in-session command (authoring, not an independent
  check): a single rule-driven coder whose per-domain conventions come from each task's cited
  `rules/*.md`, with **polish** as its final in-context phase (style/self-consistency only, no
  structural change). It grounds from the merged plan + cited rules + the project's build/run
  skills, generates a `<type>/<id>-<short-name>` branch, and stops at PR creation — the status tag
  stays `In implementation`.
- `scripts/aind-open-code-pr.sh` — the GitHub-flow twin of `aind-open-plan-pr.sh`: `start` (branch
  off the integration branch, with a dirty-working-tree guard) and `open` (push + open the code PR
  carrying the `AIND-LINKS` block incl. the plan-PR URL, and native Boards↔GitHub linking via
  `AB#<id>`).
- Coder hardening habits lifted from prior multi-agent practice: read an existing implementation of
  the same type before writing new code, make data contracts exact on the wire, self-check against
  the Definition of done, and get the project's build green before opening the PR (fail-fast — not
  test authoring).

### Notes
- This first build-phase iteration scopes to **code-PR creation**: no test authoring, and code
  review, the merge gate, and the terminal `Implementation complete` write are the next steps
  (D24). The cold test-writer and the coder's own unit tests stay deferred (D8/D9).
- Generic, reusable developer guidance (SOLID, .NET, house style) is ruled **out** of AIND — it
  belongs in a separate companion **dev-standards plugin** (skills), consumed via the two-layer
  rule-extends-skill pattern and wired by onboarding (D25).

### Validated
- `/aind:implement` — live-validated end-to-end on a real story: the precondition gate stops a
  story that is not `Ready for implementation`; grounding + existing-pattern reuse; the pre-PR
  project build; honest deviation reporting; and code-PR creation with correct links and status
  discipline.

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
