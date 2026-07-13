# Changelog

All notable changes to the **aind** plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Each version matches the `vX.Y.Z` GitHub Release that
`deploy.sh` cuts from the `version` in `.claude-plugin/plugin.json` (kept in sync with
`.github/plugin/plugin.json`). Design rationale for each change lives in `design-log.md`, cited by
decision ID (e.g. D23).

> Versions before 0.4.0 were reconstructed retroactively from git history and the design log.

## [0.13.0] — 2026-07-13

### Added
- **Pluggable code host — Azure DevOps Repos as an alternative to GitHub** (D36). The code, its
  pull requests, and its PR comments can now live in **ADO Repos** instead of GitHub, selected
  per-project by `AIND_CODE_HOST=github|ado` (default `github`). This is a **script-only** change —
  `commands/`, `skills/`, and `agents/` are unchanged, and an existing GitHub project keeps working
  with no config change.
  - **New forge adapter `scripts/aind-forge.sh`** — host-agnostic PR verbs (create / list / view /
    diff / edit-body / comment / thread / thread-list / resolve / reply) that dispatch on
    `AIND_CODE_HOST` to `gh` (GitHub) or `az repos` + the **ADO PR Threads REST API** (ADO), reusing
    the existing `AZURE_DEVOPS_EXT_PAT` (no new credential). Opaque PR/thread tokens keep the
    reviewer/coder prompts host-blind; PR/thread states normalise to one vocabulary
    (`OPEN`/`MERGED`/`CLOSED`, `[OPEN]`/`[RESOLVED]`). ADO PR diffs are computed locally with git.
  - All PR scripts (`aind-open-plan-pr`, `aind-open-code-pr`, `aind-review-pr`, `aind-thread`,
    `aind-revise-plan-pr`, `aind-revise-code-pr`, `aind-complete`, and the dreaming config-PR opener
    in `aind-dream`) are now thin callers of the adapter. `aind_gh_signature` →
    host-aware `aind_pr_signature`; code-PR discovery moved into the adapter.
  - **Native work-item linking** is simpler on ADO (same platform): `az repos pr create --work-items`
    hard-links the PR — no Azure Boards ↔ GitHub app needed.
  - **New config** `AIND_CODE_HOST` and `AIND_ADO_REPO`; `aind-preflight.sh` is host-conditional
    (`gh`/auth for GitHub; `az repos` extension + PAT **Code** scope + repo reachability for ADO).
    `/aind:onboard` detects the code host from the git remote and writes it; `/aind:kickstart` asks
    (GitHub vs ADO Repos) and writes it.

### Fixed
- **ADO inline review threads anchored to a mangled path** (Windows/MSYS). The ADO code host anchored
  plan/code review threads to e.g. `C:/Program Files/Git/plans/47/plan.md` (ADO then reported the
  file missing): Git-Bash/MSYS rewrites any argv that starts with `/` into a Windows path before
  native `jq.exe` sees it. Fixed by building the required leading-slash `filePath` **inside** jq, not
  in the shell. The GitHub path was unaffected.

### Notes
- **Two orthogonal axes now:** the **agent host** (Claude Code vs GitHub Copilot CLI, D22) and the
  **code host** (GitHub vs ADO Repos, D36). Docs updated in lockstep: `design-log.md` (D36),
  `design-doc.md`, `README.md`, `GETTING-STARTED.md`, `docs/index.html`, `CLAUDE.md`, and the
  project-template env sample / `CLAUDE.md`.

### Validated
- **Live-validated end-to-end on Azure DevOps Repos** — onboarding, kickstart, intake, and the full
  plan → build → review → complete loop, plus the assumption/review threads landing on the correct
  `plans/<id>/plan.md` lines. GitHub path re-validated (offline unit checks + live).

## [0.12.0] — 2026-07-13

### Added
- **Reviewer read-only contract is now hook-enforced, not just prompt-stated.** A new PreToolUse
  hook (`hooks/check-claude-reviewer.sh`, wired via a second `Bash` entry in `hooks.claude.json`)
  scopes the cold reviewer to an allowlist — it may run only `aind-review-pr.sh` — so a reviewer that
  tries to `git push`, run tests, or otherwise mutate is blocked mechanically. `agents/reviewer.md`
  also declares `disallowedTools: Edit, Write` in its frontmatter. The hook is **fail-open**: if the
  calling agent can't be identified it never blocks anyone, so non-reviewer agents are unaffected.
  *(Load-bearing on the live PreToolUse payload exposing the calling agent; a Copilot-CLI twin is not
  yet built and remains a known cross-host hardening gap.)*
- **Human-directed deviations from the plan are captured on the code PR.** `aind-revise-code-pr.sh`
  gains a `deviation` op that maintains an idempotent `## Directed deviations` block in the code-PR
  body; `/aind:implement` records a human-directed deviation there during revise mode, and the cold
  reviewer reads and verifies that block (treating an unsigned entry as the human's) so a deliberate,
  human-sanctioned departure from the plan is no longer flagged as scope creep.

### Changed
- **The planner now explicitly covers the human-authored story's acceptance criteria.** `commands/plan.md`
  adds an AC-coverage pass and an `AC coverage` section so the plan can't silently narrow the story's
  stated acceptance criteria, with tightened non-goals and either/or assumption-thread phrasing that
  invites an unambiguous reply; `commands/approve-plan.md` ratifies AC coverage at approval.
- **Getting-started guidance now recommends a CI / branch-protection test gate** at story merge
  (`GETTING-STARTED.md`), the project-side complement to the reviewer's coverage/fidelity gate.

## [0.11.1] — 2026-07-09

### Fixed
- **The cold reviewer no longer runs the project's build / lint / test commands** (D35). The
  reviewer has `Bash` access (needed for the `aind-review-pr.sh` mechanics) and is told to read the
  project's `.claude/skills/`, but the prompt never said whether to *run* the build/lint/test
  commands those skills describe — so it improvised and re-ran them on every review pass, redundantly
  duplicating the coder's pre-PR build+tests gate up to 3× per story.
  - `agents/reviewer.md` now states the boundary: the reviewer **reviews by reading the diff** and
    does **not** run build/lint/test/run (new **Constraint §7**, plus clarifiers on the
    skills-reading step and the Bash-usage note). A code-won't-build / test-won't-pass is a
    **finding to report** (`file:line`), not something the reviewer executes.
  - The coder still runs build **and** tests before opening the PR — the objective build-green gate
    lives with the coder (D34) — and a green suite is never the reviewer's evidence regardless (D33),
    so re-running bought nothing and only cost a full cycle each pass.

### Notes
- **Prompt-only change — no scripts touched.** Docs updated in lockstep: `design-log.md` (D35) and
  `CLAUDE.md`.

## [0.11.0] — 2026-07-09

### Changed
- **Testing redesigned** (D33, supersedes D8/D9/D14/D15). Testing moves to: the **planner** sets a
  per-story **test strategy**, the **coder authors the tests warm, in-context**, and the **cold
  reviewer** is the independence gate on test quality.
  - **Planner (`commands/plan.md`)** — the *Testing recommendations* section is now a test strategy:
    **whether** to test (gated on the project actually having a test practice, read from its
    skills/rules — no framework ⇒ *no automated tests*, and the coder never bootstraps one per
    story), **at what altitude** (unit/integration/behavioral in the project's own vocabulary), and a
    conditional, additive **must-cover list** of the edge cases/failure modes the ACs don't already
    state, **each with its expected outcome** — dropped when the ACs already pin the behavior down.
    Live verification, where needed, is a single Definition-of-done line a developer clears by hand.
  - **Coder (`commands/implement.md`)** — now **authors the tests** the strategy calls for, covering
    every must-cover case with an assertion tied to the plan's *expected outcome* (never to whatever
    the code returns), and gets the build **and** the tests green before opening the PR. It does not
    pad the suite; fixing a failing test means fixing the code or a genuinely wrong test — never
    weakening a real assertion.
  - **Reviewer (`agents/reviewer.md`)** — gains a **test-quality mandate**: *coverage* (every
    must-cover case has a test) and *fidelity* (each test asserts the spec'd outcome — a green suite
    is never taken as evidence, so an assert-to-bug test is a blocking finding) both **block**;
    tautological / framework-testing / redundant-bulk tests are non-blocking **suggestions**.

### Removed
- The **cold test-writer agent** and its same-branch red→green machinery, and the **live/E2E test
  agent** as a first-class actor (D33). Authoring meaningful *executable* tests before any code
  exists is self-contradictory (the "cold" author ends up designing the code), and running the app is
  a per-project concern — so "how to run the app / E2E" is a project **skill**, never plugin
  machinery. Live verification survives only as an optional Definition-of-done line satisfied by a
  human PR signal.

### Notes
- **Prompt-only change — no scripts touched.** Accepted residual: a diff-reading reviewer *reduces*
  but does not eliminate test-gaming/inflation; **mutation testing** in a project's CI is the
  named-not-built mechanical upgrade a team can add (objective gates are CI's job).
- Docs updated in lockstep: `design-log.md` (D33 + D8/D9/D14/D15 marked superseded), `design-doc.md`,
  `README.md`, `CLAUDE.md`, and the flow diagram (`docs/index.html`).

### Validated
- Offline: `claude plugin validate` passes (the one accepted root-`CLAUDE.md` warning), and the
  shipped artifacts carry no decision-ID / design-log references.
- **Live-validated** end-to-end on a real story with a unit-testing practice: the planner produced a
  test strategy + must-cover list, the coder authored the tests in-context, and the cold reviewer's
  coverage/fidelity gate behaved as designed (missing must-cover case → WARNING, assert-to-bug →
  CRITICAL, test nits stayed non-blocking). With this the **whole build phase** (coder + cold
  reviewer + revise loop + testing) is fully live-tested.

## [0.10.1] — 2026-07-08

### Fixed
- **Intake now validates that a story's dependencies are actually _implemented_, not merely
  _named_** (D32). Previously intake read only the story text — rubric criterion O5 checks that
  dependencies/blockers are named or explicitly "none" — but never inspected the **linked**
  predecessor stories, so a well-formed story could pass intake and enter planning while a story
  it depends on was still unbuilt. `/aind:intake` gains a **dependency gate**: it resolves the
  item's ADO **Predecessor** links, checks each linked story's status, and **declines** the story
  if any dependency is not implemented yet.
  - **The gate is orthogonal to the readiness score.** A perfectly-defined story can score **100**
    and still be declined solely because a story it depends on isn't done — the verdict comment
    names the unmet dependencies in a dedicated **Dependencies** section, and the score is untouched.
  - **"Implemented"** = the dependency carries the AIND status `Implementation complete`, or — for a
    dependency not tracked by AIND — a done-like ADO state (Closed / Done / Resolved / Completed).
    An unreadable link (deleted / no access) is treated as unmet (fail-safe).
  - **A story declined only for an unmet dependency needs no text edit** — it becomes ready once the
    dependency lands and the human re-runs `/aind:intake`; the report says so.
  - **New script:** `scripts/aind-deps.sh` (resolves Predecessor links → per-dependency status →
    `DEPS_VERDICT: NONE|MET|UNMET`). `commands/intake.md` gains the gate as step 4. Only
    Predecessor (`Dependency-Reverse`) links gate; Successor/Hierarchy/Related links are ignored.

## [0.10.0] — 2026-07-08

### Added
- **Greenfield onboarding — `/aind:kickstart`** (D31), the sibling of `/aind:onboard` for a **new
  project with no code to scan**. Instead of reading a codebase, it elicits the project's shape
  through a **guided conversation** across three lenses — functional/domain, technical layers,
  cross-cutting concerns — plus operational config (integration branch, ADO/GitHub targets, intended
  tooling), reading any design docs you point it at. It then drafts the *same* `.claude/` config
  onboarding produces: rule files per **decided** area, a wired `CLAUDE.md`, placeholder skills, and
  a seed-rubric + env-sample copy. It **proposes the whole `.claude/` tree for validation before
  writing**, runs preflight, and summarizes next steps.
  - **Warm in-session command, no new scripts** — it reuses onboarding's tooling (`_TEMPLATE.md`,
    `project-template/CLAUDE.md`, the seed-rubric/env copy, `aind-preflight.sh`). Same gate as
    onboard: suggest-don't-assert, GREENFIELD DRAFT files, config-layer only (never the flow).
  - **The one greenfield-specific rule: never fabricate a convention.** Because a new project's
    answers are often decisions not yet made, an undecided point becomes an explicit `TODO` / open
    question in the draft, not an authoritative rule. Skills carry the *intended* command marked
    unverified (the toolchain may not exist yet).
  - **Complementary to onboard:** kickstart bootstraps config *before* code exists; re-run
    `/aind:onboard` once real code lands to reconcile the drafts against the actual codebase.

### Changed
- **Skills are no longer framed as just build/test/run.** Both `/aind:kickstart` and `/aind:onboard`
  now stub the broader set of deterministic dev workflows — build/test/run/lint as the common core
  plus deploy, DB migrations, data seeding, codegen/scaffolding, formatting, starting local
  dependencies, API-client generation, e2e — while keeping the discipline (onboard stubs only what it
  finds in the repo; kickstart stubs only what the user intends).

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
