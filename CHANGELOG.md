# Changelog

All notable changes to the **aind** plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Each version matches the `vX.Y.Z` GitHub Release that
`deploy.sh` cuts from the `version` in `.claude-plugin/plugin.json` (kept in sync with
`.github/plugin/plugin.json`). Design rationale for each change lives in `design-log.md`, cited by
decision ID (e.g. D23).

> Versions before 0.4.0 were reconstructed retroactively from git history and the design log.

## [0.9.0] — 2026-07-07

### Added
- **Dreaming phase — continuous improvement loop** (D30, realises D16). The flow now closes the loop
  on improving its own `.claude` config.
  - **Emission** — a new signed script `aind-emit-lesson.sh` (the exhaust twin of `aind-comment.sh`)
    that every authoring agent calls at session end. Each *lessons-learned* record is front-matter
    (work item, agent, phase, a **severity** enum — `observation`/`suggestion`/`correction`/`blocker`
    keyed to how far a human had to step in, a `source`, an optional `area`) plus an **Observation**
    body only (what happened and *why* — never a proposed fix; the remedy is the dreamer's). Records
    write to a dedicated **orphan branch** (`aind/lessons`, `AIND_LESSONS_BRANCH` optional) via
    throwaway-index git plumbing, so an agent emits mid-run without leaving its branch. Wired into
    `/aind:intake`, `/aind:plan`, and `/aind:implement`; **human PR feedback becomes lessons** through
    the planner/coder revise runs (a correction/suggestion sourced to the thread).
  - **Synthesis** — the manual command **`/aind:dream`** (a warm orchestrator) spawns a new cold
    subagent `aind-dreamer` twice: an *analyze* pass clusters the unprocessed lessons and judges each
    on **severity × recurrence × factualness** (a rubric, not a counter; borderline clusters surfaced
    with a confidence label), the **human curates the clusters** (gate 1), and an *author* pass turns
    approved clusters into `.claude` edits that land as **one PR** (gate 2). New mechanics script
    `aind-dream.sh` (`digest`/`start`/`open-pr`/`consume`/`note`); directory-based lesson lifecycle
    (`new/` → `archive/`/`rejected/`).
  - **Scope** is any behavior file under the project's `.claude/` (scope-by-default, not a folder
    allowlist) minus four carve-outs it never edits: the **flow** (status model, gates, operational
    rules), its own **guardrails** (`settings*.json`, enforcement/signing hooks — told from a dev hook
    by purpose, not name), **secrets** (`aind.env`), and anything **outside `.claude/`**. A structural
    problem or generic reusable knowledge (→ the companion standards plugin, D25) is a `aind-dream.sh
    note` parking-lot entry, never a diff.
- New optional config `AIND_LESSONS_BRANCH` (GitHub-side; defaults to `aind/lessons`).

## [0.8.1] — 2026-07-06

### Fixed
- **GitHub PR comments are now signed** (D29). Agent signing was only ever built into the ADO
  comment path (`aind-comment.sh`), so every PR-side post — review summaries, resolvable threads,
  and thread replies — went out unsigned, making a reviewer finding and a coder rebuttal
  indistinguishable when the coder, reviewer, and planner all post under one GitHub identity. A new
  shared `aind_gh_signature <agent>` helper (`aind-common.sh`) is now appended by every PR-posting
  site: `aind-thread.sh`, `aind-review-pr.sh summary|thread|reply` (which gain an explicit `<agent>`
  argument), and `aind-revise-code-pr.sh push` / `aind-revise-plan-pr.sh push|reply` (which sign as
  `coder` / `planner`). The GitHub machine marker is an HTML comment `<!-- AIND-AGENT: <name> -->`
  (invisible when rendered, still greppable); PR bodies remain unsigned by design.

## [0.8.0] — 2026-07-01

### Added
- **Build phase — code-revision loop (steer the coder from the PR).** `/aind:implement` is now
  **mode-aware** (D28): a re-run on a story that already has an open code PR enters **revise mode**.
  It checks out the PR's head branch, prints a **steering digest** (PR comments + review threads),
  applies **only the human-directed** changes — a reviewer suggestion the human picked, a **tiebreak
  verdict**, or a touch-up — replies on each acted thread (**never resolving** — resolution stays the
  human's merge gate), pushes to the **same** PR, and re-runs the code review by default (skippable
  for a trivial touch-up). The `AIND status` tag stays `In implementation` throughout.
- `scripts/aind-revise-code-pr.sh` — `status` (detect an open code PR by marker-search), `begin`
  (check out the head branch + print the steering digest), `push` (push to the same PR + optional
  comment). The twin of `aind-revise-plan-pr.sh`; thread replies reuse `aind-review-pr.sh reply`.

### Changed
- The code-PR marker-search is factored into a shared `aind-common.sh` helper (`aind_find_code_prs`),
  reused by `/aind:complete` (a single MERGED match) and the revision loop (a single OPEN match).
- `/aind:complete` cleanup now also **fast-forwards the integration branch** to include the merge
  when you end up on it with a clean tree (fast-forward only; a diverged local branch is left for a
  manual pull), so your local trunk isn't silently behind (D27 refinement).
- `aind-open-code-pr.sh`'s re-run refusal now points to revise mode instead of "not supported".

### Notes
- Applying **only human-directed** changes keeps the human the decision-maker (suggest-don't-assert):
  the coder does not sweep up undirected suggestions or re-implement freely.
- Scope still stops before merge — `/aind:complete` remains the only terminal step; a plan-level
  problem surfaced during revision is flagged for a human, never silently re-planned.

### Validated
- The code-revision loop — live-validated on a real story: a re-run entered revise mode, applied
  **only** the directed change, replied without resolving, pushed to the same PR, re-reviewed CLEAN,
  and never moved the tag. Offline: 13/13 code-PR selection unit tests (the shared resolver —
  single-MERGED for complete, single-OPEN for revise — plus id-boundary cases).

## [0.7.0] — 2026-07-01

### Added
- **Build phase — merge gate + terminal completion (Phase 4 close-out).** `/aind:complete <id> [pr]`
  closes out the build phase (D27) — the twin of `/aind:approve-plan`. It resolves the story's code
  PR, **verifies it is MERGED (refuses otherwise)**, writes the terminal `Implementation complete`
  tag, posts a signed `coder` completion note, and cleans up the merged code branch. **Merge-then-tag**
  (D13): the tag is only written after a confirmed merge, so a tag-write failure leaves the item
  recoverable rather than falsely complete; branch cleanup runs last so a hygiene hiccup can't corrupt
  status. The command does **not** merge — a human merges in GitHub and this records the result
  (D13 realised as verify-then-tag, not command-merges).
- `scripts/aind-complete.sh` — `verify` (resolve the code PR by searching the work-item id against the
  flow's own markers — a title `(AB#<id>)` or the `AIND-LINKS` work-item URL — requiring a single
  MERGED match, with an explicit `[pr]` override; the coder-generated branch is non-derivable, so the
  PR is found by search, never by reconstructing a name) and `cleanup` (delete the remote branch only
  if still present — a no-op when the merge auto-deleted it — prune the stale remote-tracking ref, and
  remove the lingering local branch, switching off it only when the working tree is clean).

### Notes
- **Scope is `/aind:complete` alone.** A **code-revision loop** — re-entering an already-open code PR
  to apply a wanted suggestion, a rebutted fix, or a human's tiebreak verdict, then pushing to the same
  PR (the twin of the plan-revision loop) — is the next iteration. Until then, the sanctioned interim
  bridge for those cases is a direct edit on the PR branch + push before merge.
- Test authoring (D8/D9) and the dreaming phase (D16) remain deferred; unattended automation +
  auto-merge stay out of manual scope (D6).

### Validated
- `/aind:complete` — live-validated on a real story (AB#19): refuses while the PR is unmerged, then
  once merged flips the tag to `Implementation complete`, posts the note, and cleans up the code
  branch. Offline: 7/7 unit tests on the code-PR selection logic (single-MERGED match, none-merged,
  ambiguous, no-match, body-marker fallback, and the id-boundary case).

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
