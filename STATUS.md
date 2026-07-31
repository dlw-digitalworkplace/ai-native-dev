# AIND — current status & next steps

_Fluid project state: what is built, what is validated, what is next. The stable, set-in-stone rules live in `CLAUDE.md` — update THIS file as work lands, never bake status into the rules. See `docs/plans/` for the planned-feature backlog and `design-log/` for the decision record._

## Current status (2026-07-30)

- **Pluggable work-item tracker — a local markdown-file backend (D46, 2026-07-30, offline-validated
  + live-validated end-to-end).** Where work items live is now a **third pluggable axis** (alongside the
  D22 agent host and D36 code host), selected per project by `AIND_TRACKER=ado|file` (default `ado`,
  so existing projects are byte-for-byte unaffected) behind a new **`scripts/aind-tracker.sh`** adapter
  that mirrors the D36 forge. The **`file` backend = one markdown file per work item** under a
  configurable `trackerDir` (default `<main-checkout>/.aind/items`, **may live outside the repo**) —
  built for the motivating case of **no ADO backlog / code-only PAT access**. The no-deadlock
  requirement rules out a single CSV/Excel (Excel's exclusive lock *is* the deadlock; one shared file
  serialises writes); file-per-item + a **machine-owned front-matter block** (`state`, `dependsOn`,
  `links`, `durationSeconds` — flat scalars, no YAML parser) split from **human-owned `##` sections**
  (`Description`/`Acceptance` read-only, `Comments` append-only) + **atomic temp-then-`mv` writes**
  make no-deadlock structural (the plugin can write while the file is open in an editor). It is
  *simpler* than ADO: the scalar `state:` kills the single-tag dance and the native-State mirror; no
  `md_to_html`/`display:none` carrier; `dependsOn:` replaces relation-URL parsing; `tracker_new`
  scaffolds from `project-template/item-template.md` (id = `max+1`), wrapped by a guided
  **`/aind:new-item`** command (Q&A → drafts the item file for review; file-tracker only). The six work-item scripts become
  thin tracker callers (`aind-workitem` now emits normalised JSON); `aind-usage` write-side and
  `aind-links`'s URL route through the adapter; telemetry verbs are best-effort. `aind-common` maps
  `.tracker`/`.trackerDir` and generalises its config sentinel; `aind-preflight` gained a file branch
  (az/PAT/ext now conditional on ADO tracker *or* code host). `/aind:onboard` + `/aind:kickstart`
  elicit the tracker and write the keys (gitignoring only the in-repo default, seeding the template);
  `/aind:map-states` + the native-State mirror are gated to the ADO tracker; the three work-item skills
  and `project-template/CLAUDE.md` are genericised. Signing for the file backend holds by routing (all
  comments go through `tracker_comment`), not the ADO URL hook. Script + docs + templates only; the
  flow, status model, gates, and PR contract are untouched. **Offline-validated** (24-check file-backend
  suite against a temp store + `bash -n` + preflight in file mode) and **live-validated end-to-end** on a
  real no-ADO repo (onboard→`tracker_new`→intake→plan→implement→complete).
- **Onboarding rule depth, convention capture & conflict resolution (D45, 2026-07-30, live-validated
  on a real .NET + React repo over successive Copilot-CLI runs).** `/aind:onboard` (and its greenfield
  twin `/aind:kickstart`) now produce deep, enforceable rules on the **first pass** instead of shallow
  map-only rules the human had to hand-correct. Same D18 boundaries (evidence-only, suggest-don't-assert,
  config-layer-only); the change is depth + voice: it **reads existing agent-instruction files first**
  (`.github/copilot-instructions.md`, `.github/instructions/*`, `AGENTS.md`, `CLAUDE.md`, cursor/windsurf
  rules, `CONTRIBUTING.md`) and folds them into rules; does a **mandatory representative-source read**
  adapted to project type (web app / library / script collection / CLI / pipeline / IaC); runs a
  **distinct functional/domain reading pass** (the core domain abstraction + its extension model +
  *how you add a new unit of the domain*) behind a **completeness guard** (a functional rule, or a
  stated reason none exists); writes rules as **directives** (the draft is the suggestion; each kept
  rule is an enforced requirement — DRAFT banner reworded); probes a **stack-agnostic convention
  checklist** (logging, error handling, naming, folder/module roles, abstraction placement, wiring,
  imports, I/O, state, a unit's public contract, lint baseline — pointing to tooling where it already
  enforces a rule); and **detects competing patterns and resolves each material one interactively**
  (`AskUserQuestion` — a candidate rule per option; chosen option becomes the rule, alternatives kept
  as a Convention decision note). Two fixes ride along: a bare test **runner with no test artifacts**
  is stubbed but flagged **UNVERIFIED in the skill `description`** (not asserted as a real suite), and
  every stubbed `SKILL.md` carries the required **`name` frontmatter** (kills the "Skill should provide
  a name" host warning). `project-template/CLAUDE.md` is restructured **project-first** (context + rule
  imports lead; AIND config a compact layer beneath; worktree/telemetry detail replaced by pointers).
  Prompt/template only (`commands/onboard.md`, `commands/kickstart.md`, `project-template/CLAUDE.md`,
  `project-template/rules/_TEMPLATE.md`); the flow, status model, gates, and PR contract are untouched.
  Residual is model variance — the completeness guard makes a miss *visible* rather than silent, and
  the dreaming loop (D30) remains the mechanism for the long tail.
- **Per-phase usage telemetry — raw tokens (work-item attachment) + time (numeric field), no cost
  (D42, 2026-07-28, live-validated — intake single-tree + implement in worktree mode).** Each ADO-touching phase
  (`/aind:intake`, `/aind:plan`, `/aind:implement`, `/aind:complete`) records **raw usage only** onto
  the work item — a **per-model, per-token-type** token breakdown + wall-clock time — with **no cost,
  no rate card, no rendered on-item view** (pricing is done entirely offline against the stored data,
  a separate story, so history can be re-priced anytime). Opt-in via a `telemetry` block in
  `.claude/aind.settings.json` (`enabled` + optional numeric `durationField`). Each phase brackets its
  work with `aind-usage.sh begin`/`report`; measurement is by **timestamp window** over the agent
  host's on-disk per-session events, so attribution is per-phase even when phases share a session. A
  **host-aware collector** (aind-forge-shaped, on the *agent*-host axis): Claude reads
  `~/.claude/projects/<slug>/<session>.jsonl` → dedupes by `message.id`, folds in the
  `<session>/subagents/*.jsonl` (so a build total includes the reviewer), reduces to a per-model map
  from `message.model`+`message.usage`; Copilot reads `~/.copilot/session-state/<session>/events.jsonl`
  → a single `copilot` bucket with **output tokens only** (its logs carry no per-message model or
  input/cache). **Truth = the token breakdown as an append-only JSON attachment per phase-run**
  (`aind-telemetry-<id>-<phase>-<agent>-<stamp>.json`, `wit/attachments` REST + an `AttachedFile`
  relation); **time = the numeric `durationField`** (queryable). New script `aind-usage.sh`
  (`_attach_upload`/`_attach_link` + the `_field_accumulate` from aind-status.sh's tag PATCH; `/fields/…`
  and `/relations/-` built inside jq for the MSYS trap); `.aind/usage/` gitignored. Best-effort/never
  blocks a phase; inert unless enabled — the tokens+time twin of the D30 lessons exhaust. Rejected an
  earlier single-token-total field (opaque + a false cost proxy: cache-reads were ~97% of tokens but
  ~61% of cost) and a rendered on-item table (token/UI clutter) in favour of raw-in-attachment +
  offline pricing. Config/packaging side of the D1–D15 line; the flow, status model, gates, and PR
  contract are untouched.
- **Config streamlined into two files, created by onboarding (D41, 2026-07-23, live-validated
  end-to-end).** Per-project config split: **`.claude/aind.settings.json`** (shared,
  checked in — ADO org/project, code host, repo, integration branch, branch prefixes, and the
  `worktree` block) + **`.claude/aind.env`** (gitignored — PAT + optional `AIND_ACTOR` only). The
  `AIND_*` env vars stay the interface; only the loaders changed (`aind-common.sh` +
  `aind-preflight.sh` source `aind.env` then jq-map the settings JSON into any unset `AIND_*` var,
  CRLF-stripped, already-set-`AIND_ADO_ORG` still short-circuits). **Worktree opt-in is now
  `worktree.enabled: true`** in the settings file (was file-presence); `aind-worktree.sh` reads the
  nested `.worktree.*` keys; **clean break** — the old `aind-worktree.config.json` is no longer read.
  `/aind:onboard` (gained `AskUserQuestion`) and `/aind:kickstart` now **create and fill** both files
  (PAT as a `<pat>` placeholder — never a real secret) and append the gitignore lines idempotently,
  instead of dropping `.sample` copies. New `project-template/aind.settings.sample.json`; `aind.env.sample`
  shrunk to secrets; `aind-worktree.config.sample.json` deleted; `project-template/CLAUDE.md`, README,
  GETTING-STARTED updated. Script + docs + templates only; the flow, status model, gates, and PR
  contract are untouched. Distinct config/packaging-side change; same spirit as D36/D37.
- **Share `node_modules` across worktrees — `symlinkDirs` (D39, 2026-07-22, offline-validated;
  live-validation pending).** Builds the large-dir-sharing extension D37 named-not-built, for
  front-end work where re-installing per worktree is slow/heavy. New optional **`symlinkDirs`** list
  in `.claude/aind-worktree.config.json`: on `aind-worktree.sh ensure`, each repo-relative dir is
  **linked** from the worktree to the same dir in the main checkout — a **directory junction** on
  Windows (`MSYS_NO_PATHCONV=1 cmd /c mklink /J`; no admin / no Developer Mode, unlike a `mklink /D`
  symlink; same-volume only, which holds inside the repo) and `ln -s` on Unix. A missing target is
  `mkdir`'d empty (+ warned) so install-from-worktree writes *through* the junction into the one
  shared store. **The load-bearing correctness point is teardown:** the `copyFiles` teardown uses
  `rm -rf`, which *through a junction would delete the real `node_modules` in the main checkout* — so
  `symlinkDirs` has its **own** unlink step (`aind_wt_unlink_dirs`) that runs **before** the copyFiles
  delete and before `git worktree remove`, in **both `remove` and `prune`**, removing only the **link**
  (`cmd /c rmdir` on Windows removes a junction without following it; `rm` the symlink on Unix) —
  **never `rm -rf`**. Iterated from the config list, not `test -L` probing (junctions are unreliable
  to detect on MSYS). **Shared state is a documented trade-off** (a branch changing deps re-installs
  into the shared store; a concurrent install in one worktree can disturb another's build) — docs
  **recommend pnpm** where per-branch isolation matters and offer `symlinkDirs` as the portable
  mechanic for npm/yarn. Generic list (also `.next/cache`, `.venv`, …). **Strict no-op when
  `symlinkDirs` is absent/empty** (regression bar). Script + docs only: `aind-worktree.sh`,
  `aind-preflight.sh` (reports shared dirs, warns on a not-yet-present target), the sample config,
  README/GETTING-STARTED/project-template. Windows `cmd` calls guarded with `MSYS_NO_PATHCONV=1`
  (leading-slash argv family). Requirements/design record folded into Appendix A of
  `files/implementation-plan-worktrees.md`. Distinct axis from D22 (agent host) and D36 (code host);
  same working-tree-layout axis as D37.
- **Worktree close-out returns the session to the main checkout first (D40, 2026-07-22,
  offline-validated).** Refines D37's drive-from-main teardown. The coder grounding runs build/test
  with `cd "<worktree>"` and the host shell's cwd **persists**, so `/aind:implement` ends parked
  *inside* the worktree; running `/aind:complete` / `/aind:approve-plan` from there made
  `git worktree remove` refuse (own-cwd lock — visible) **and** silently skipped the integration
  fast-forward (the cleanup script saw the worktree's code branch as `HEAD`, not integration → local
  main left behind origin while the terminal tag still succeeded). Both close-out commands now `cd` to
  the main checkout as their first step via a new **`aind-worktree.sh main-root`** verb (resolves main
  from inside a linked worktree). Fix is **agent-executed** by necessity: only moving the parent
  session shell frees the OS lock and re-points the cleanup's git ops at main — a subprocess `cd`
  can't. `/aind:plan` + `/aind:implement` grounding notes corrected (the old "cwd stays on main" claim
  was false in a persistent shell). `prune` stays the fallback for a genuinely stranded worktree.
- **Merge-conflict detection + rebase resolution in the review loop (D38, 2026-07-16, live-validated
  2026-07-17).** Parallel worktrees (D37) let a code PR go **conflicting** the moment
  another PR merges under it; the loop now sees and clears that. **Detection is a PR read, not a run**
  (keeps the reviewer cold/read-only per D35): new forge verb `forge_pr_mergeable` normalises
  `gh mergeable` / ADO `mergeStatus` to `MERGEABLE|CONFLICTING|UNKNOWN`; surfaced through
  `aind-review-pr.sh` in `fetch` and a new polling `mergeability` phase (both hosts compute it
  **asynchronously**, so `UNKNOWN` is polled briefly then treated as **advisory, non-blocking** — only
  a confirmed `CONFLICTING` blocks). The reviewer flags a `CONFLICTING` PR as a **CRITICAL** finding
  in its **summary** (no `file:line`, so not an inline thread) under the synthetic locus
  `merge:integration`. **Resolution** (fixes recorded lesson 57-coder): `aind-revise-code-pr.sh` gains
  a `rebase` phase (fetch integration, rebase the PR head, leave conflicts in-tree for the coder) and
  its `push` is now **force-with-lease-aware** (detects a rebase-diverged remote via
  `git merge-base --is-ancestor` and force-with-leases only then; plain fast-forward otherwise).
  `/aind:implement` wires this into the `CHANGES_REQUESTED` branch of the review loop and the
  Stuck-state note. **Kept reactive, not proactive** (no pre-emptive rebase before every push).
  Offline-validated (script `bash -n`; mergeStatus mapping + force-push guard exercised in a throwaway
  repo) then **live-validated end-to-end** on a real conflicting PR (reviewer flagged `CONFLICTING`,
  coder rebased + force-with-lease-pushed, re-review returned `CLEAN`). Distinct axis from D22 (agent
  host) and D36 (code host).
- **Parallel work via AIND-owned git worktrees (D37, 2026-07-15, built on `feat/worktree-parallelism`,
  offline-validated; live-validation pending).** Opt-in by the presence of
  `.claude/aind-worktree.config.json` (`worktreeRoot` default `.claude/worktrees`; a `copyFiles` list
  of gitignored files — `aind.env`, `settings.local.json`, project `.env` — copied into each fresh
  worktree). Every PR-creating path runs in its own **per-phase** worktree keyed `<id>-<phase>`
  (`/aind:plan`→`<id>-plan`, `/aind:implement`→`<id>-impl`); `/aind:approve-plan` and `/aind:complete`
  retire them. **`/aind:dream` is intentionally single-tree** (occasional cross-story flow, not
  per-story parallel work; its lesson emission uses no checkout, only its synthesis PR touches the
  tree — run it standalone from a clean main checkout). **Session model = drive-from-main:** the session cwd stays on the main checkout and
  *drives* a worktree by path (a process can't remove its own cwd worktree — Windows-hard); parallelism
  = multiple main-checkout terminals, each driving one story. New portable script `aind-worktree.sh`
  (`enabled`/`root`/`path`/`ensure`/`ensure-plan`/`list`/`remove`/`prune`); the PR scripts gain a
  one-line subprocess-`cd` into the worktree (session cwd untouched) and teardown folds into the
  existing `cleanup` paths. **Strict single-tree no-op when the config file is absent** (regression
  bar). **Two Windows gotchas handled** (same family as the existing ones): jq emits **CRLF** → strip
  `\r` off every parsed value; `git worktree list` prints **native `C:/`** paths vs our MSYS `/tmp` →
  normalise the root via `cygpath -m` for the prefix filter. Coder grounding (pin `$WT` as project
  root, cd-per-shell, worktree-rooted file ops, main-tree-clean guard) is the load-bearing mitigation
  of drive-from-main. `node_modules`/large-dir sharing is deferred to the project (pnpm). Offline
  smoke test green (18/18: opt-in toggle, create+copyFiles, reuse, list, main-untouched,
  self-removal guard, no-force teardown, prune). **Requirements/design record in
  `files/implementation-plan-worktrees.md`.** Distinct axis from D22 (agent host) and D36 (code host).
- **Pluggable code host — GitHub OR Azure DevOps Repos (D36, 2026-07-13, live-validated).** Code,
  PRs, and PR comments can live on either host, selected per-project by `AIND_CODE_HOST=github|ado`
  (+ `AIND_ADO_REPO`). Script-only change: a **forge adapter** (`scripts/aind-forge.sh`) dispatches
  every PR/comment/thread verb to `gh` or `az repos` + the ADO PR Threads REST API (reusing the ADO
  PAT); `commands/`, `skills/`, `agents/` are unchanged. **Terminology:** this "code host" axis is
  **distinct** from D22's "second host" (the *agent* host, Claude vs Copilot) — two orthogonal axes.
  `aind_gh_signature` → host-aware `aind_pr_signature`; onboard detects the host from the git remote,
  kickstart asks. Live-validated end-to-end on ADO Repos (plan→build→review→complete). Full plan in
  `implementation-plan-ado-code-host.md`.
- **Dual-host: runs on Claude Code AND GitHub Copilot CLI (D22, 2026-06-30).** One behavior layer
  (commands/skills/scripts); a second manifest (`.github/plugin/plugin.json`) + per-tool hooks
  (`hooks.claude.json` / `hooks.copilot.json`) absorb the only incompatibility. Copilot needs Git's
  `bash` on PATH (Windows) — see the Copilot lesson below. Claude side re-validated (intake, WI 18,
  under the renamed hooks); Copilot intake E2E being confirmed.
- **Greenfield onboarding — `/aind:kickstart` built & live-validated (D31, 2026-07-08).**
  The greenfield twin of `/aind:onboard`: for a **new project with no code to scan**, it elicits
  the project's shape through a **guided conversation** (three lenses — functional/domain, technical
  layers, cross-cutting concerns — plus operational config, reading any design docs pointed at), then
  drafts the *same* `.claude/` config onboarding produces. Warm in-session command (it authors; per
  the warm/cold line), reusing onboarding's tooling — `_TEMPLATE.md`, `project-template/CLAUDE.md`,
  the seed-rubric/env copy, `aind-preflight.sh` — so it added **no new scripts** (`commands/kickstart.md`
  only). Same gate as onboard (suggest-don't-assert, GREENFIELD DRAFT files, config-layer only), with
  one greenfield rule: **never fabricate a convention** — an undecided point becomes a visible `TODO`,
  not a rule. Proposes the whole `.claude/` tree for validation before writing. Skills are stubs
  carrying the *intended* build/test/run command marked unverified (no toolchain yet). Complementary
  to onboard: kickstart bootstraps before code, `/aind:onboard` reconciles the drafts once code exists.
  Skills are framed as **deterministic dev workflows** — build/test/run/lint as the common core plus
  deploy/migrate/seed/codegen/format/e2e where intended — not just build/test/run (same broadening
  applied to `/aind:onboard`). **Live-validated** in a session run; shipped in v0.10.0.
- **Intake dependency gate — built (D32, 2026-07-08), live-validation pending (v0.10.1).** Intake
  now validates that a story's *dependencies are implemented*, not just *named* (the O5 rubric
  criterion only checks naming). New script `aind-deps.sh` resolves the item's ADO **Predecessor**
  links, classifies each linked story `IMPLEMENTED`/`NOT IMPLEMENTED`/`UNKNOWN` (implemented = AIND
  `Implementation complete` tag, or a done-like ADO state for a non-AIND dependency), and emits
  `DEPS_VERDICT: NONE|MET|UNMET`. `commands/intake.md` gains this as **step 4**, a *command-level*
  gate (not a rubric criterion): an `UNMET` verdict **declines** the story **without touching the
  readiness score** — a flawless story can score 100 and still be declined for an unbuilt
  dependency, with the unmet stories named in a **Dependencies** comment section. Offline-validated
  (jq picks only `Dependency-Reverse`; helpers unit-checked); live-validate next against a story with
  a linked, unfinished predecessor.
- **Plan phase = implemented & live-exercised.** **Intake is live-validated** end-to-end
  (fail→fix→pass, signed comments, tag transitions, scoring, table output). **Onboarding
  (`/aind:onboard`) is validated.** **Planner create-path validated** (plan PR + assumption
  threads), now with the **enriched plan template (D23)** — Keep-it-simple/non-goals, conditional
  data contracts, a dependency-ordered task breakdown whose tasks cite the project's `rules/*.md`
  (not hardcoded domains), a Considerations section, and a sourced Definition-of-done checklist;
  live-validated on a real story (AB#19), where the simplicity bias visibly held (the planner
  declined an unrequested shared-nav-config refactor and logged it as a non-goal). **`/aind:approve-plan`
  is live-validated:** it correctly refuses while the plan PR is unmerged and, once merged, sets
  `Ready for implementation` and runs the plan-branch cleanup. **Plan-revision loop built (D21):**
  a re-run of `/aind:plan` on a story with an open plan PR enters revise mode — reads the PR's
  comments/threads and folds them into the same PR (`aind-revise-plan-pr.sh`). Revise path is
  implemented; confirm live next.
- **Role packaging settled (D19→D20, 2026-06-26).** Intake and the planner were briefly trialed as
  cold subagents (D19) then **reverted to in-session slash commands** (D20): live testing showed the
  subagent friction (permission re-prompts from fresh contexts, command→Task→subagent indirection,
  cold re-grounding cost) wasn't worth it for roles that author artifacts a human reviews. Per-role
  model is handled by **choosing the session model per invocation** (`claude --model …` / `/model`) —
  natural since the two phases are gated apart. Cold subagents stay reserved for the independent
  build-phase checks.
- **Build phase — coder built (D24, 2026-06-30).** The coding agent is the **warm in-session command
  `/aind:implement`** (per D20 — it authors, it is not an independent check): a **single** rule-driven
  coder (per-domain conventions come from each task's cited `rules/*.md`, D23), with **polish as its
  final in-context phase** (D7, no structural change). It grounds from the merged plan + cited rules +
  project build/run **skills** (D18 — dev skills are the project's, not the plugin's); its new plugin
  script is `aind-open-code-pr.sh` (the GitHub-flow twin of `aind-open-plan-pr.sh`). The coder
  **generates** its branch as `[type]/<id>-<short-name>`; the PR stays the only handle (D17).
  `commands/implement.md` + the script are written and **live-validated** end-to-end.
- **Build phase — code reviewer built & live-validated (D26, 2026-07-01).** Phase 4 review is
  now implemented as a **cold reviewer subagent** (`agents/reviewer.md`, `name: aind-reviewer`,
  strong-model override) driven from **inside `/aind:implement`**: after the code PR is opened the
  command spawns the reviewer (via `Task`, passing only the work-item id + PR number — coldness is
  structural), the **warm coder** fixes or rebuts findings, and it re-spawns **up to 3 passes**. The
  reviewer challenges the diff against the merged plan **and the full project rule + skill set** (an
  asymmetry with the coder, which obeys only each task's *cited* rules), with a deliberately strict
  **CRITICAL+WARNING-block** gate (only SUGGESTION is non-blocking; an objective/taste split keeps the
  loop from deadlocking on nits). It posts resolvable PR threads + a summary and **never authors
  fixes** (no `Edit`/`Write`, never commits/pushes). Tag stays `In implementation` throughout; a
  3-pass deadlock escalates to a human (PR summary + a signed `reviewer` ADO comment, tag unchanged);
  a reviewer that can't ground returns `CANNOT-REVIEW` → the coder raises `Needs attention` (D12). New
  plugin script: `aind-review-pr.sh` (`fetch`/`digest`/`summary`/`thread`/`resolve`/`reply`). **Scope
  ends at reviewer-approval or human-tiebreak** — no merge, no terminal tag.
  **Reviewer does not run build/lint/test (D35, 2026-07-09, prompt-only fix).** The reviewer had
  `Bash` (for `aind-review-pr.sh`) and was told to read the project skills, but the prompt never
  said whether to *run* their build/lint/test commands — so it improvised and re-ran them every
  pass, duplicating the coder's pre-PR A6 gate up to 3×. `agents/reviewer.md` now states the
  boundary (Constraint §7 + skills-step/Bash-line clarifiers): the reviewer **reviews by reading the
  diff**; a code-won't-build / test-won't-pass is a *finding to report* (`file:line`), not something
  it executes. The coder still runs build+tests (the objective gate lives with it, D34); a green
  suite is never the reviewer's evidence anyway (D33).
- **Build phase — merge gate + terminal completion built & live-validated (D27, 2026-07-01).**
  The build phase closes out with the human-run command **`/aind:complete <id> [pr]`** — the twin of
  `/aind:approve-plan`. It **verifies the code PR is MERGED (refuses otherwise)**, writes the terminal
  `Implementation complete` tag, posts a signed `coder` completion note, and cleans up the merged code
  branch — in that order (**merge-then-tag**: a tag-write failure leaves the item recoverable, never
  false-complete; cleanup last so a hygiene hiccup can't corrupt status). It does **not** merge — the
  human merges in GitHub and this records the result (D13 realised as *verify-then-tag*, not
  command-merges; matches approve-plan). The code PR is found by **search on the work-item id** (title
  `(AB#<id>)` / `AIND-LINKS` marker; explicit `[pr]` override; refuses on none-merged/no-match/ambiguous),
  since the coder-generated branch is non-derivable (D17). Branch cleanup is tuned for
  auto-delete-on-merge: remote deleted only if present, stale ref pruned, lingering local branch
  removed (switching off it only when the tree is clean). New plugin script: `aind-complete.sh`
  (`verify`/`cleanup`). Merge stays a human act in GitHub; `/aind:complete` records it.
- **Build phase — code-revision loop built & live-validated (D28, 2026-07-01).** `/aind:implement`
  is now **mode-aware** (the twin of the plan-revision loop D21): a re-run on a story with an **open
  code PR** enters **revise mode** — you *steer the coder from the PR*. It checks out the PR's head
  branch, prints the **steering digest** (PR comments + review threads via `aind-review-pr.sh digest`),
  applies **only the human-directed** changes (a picked reviewer suggestion, a **tiebreak verdict**, a
  touch-up — never undirected suggestions or a free re-implement; suggest-don't-assert), replies on
  each acted thread (**never resolves** — the human's gate), pushes to the same PR, and by default
  re-enters the review loop (skippable for a trivial touch-up). Tag stays `In implementation` (a
  revision is more PR iteration). New script `aind-revise-code-pr.sh` (`status`/`begin`/`push`); the
  code-PR marker-search is factored into `aind-common.sh` (`aind_find_code_prs`) and shared with
  `aind-complete.sh`; `aind-open-code-pr.sh`'s re-run refusal now points to revise mode. **Scope stops
  before merge** — `/aind:complete` is still the only terminal step; a plan-level problem is flagged
  for a human, never silently re-planned.
- **Dreaming phase — built (D30, 2026-07-07), live-validation pending.** The continuous-improvement
  loop is implemented. **Emission:** every authoring agent calls `aind-emit-lesson.sh` at session end
  (the exhaust twin of `aind-comment.sh`) — one record with front-matter (work item, agent, phase, a
  **severity** enum `observation`/`suggestion`/`correction`/`blocker` keyed to how far a human had to
  step in, a `source`, an optional `area`) + an **Observation** body only (what + why, never a
  proposed fix — the remedy is the dreamer's). Records write via **throwaway-index git plumbing** (no
  checkout) onto a dedicated **orphan branch** `aind/lessons` (`AIND_LESSONS_BRANCH` optional, default
  `aind/lessons`) that never merges into integration. Human PR feedback becomes lessons through the
  planner/coder *revise* runs (already read the threads → emit a `correction`/`suggestion` sourced to
  the thread) — realising D16's deferred human-override capture without a gate prompt. **Synthesis:**
  the manual command **`/aind:dream`** (warm orchestrator) spawns the cold `aind-dreamer` **twice** —
  an *analyze* pass clusters unprocessed lessons and judges each on **severity × recurrence ×
  factualness** (a rubric, not a counter; borderline clusters surfaced with a confidence label, not
  dropped); the **human curates the clusters** (Gate 1); an *author* pass turns approved clusters into
  `.claude` edits → **one PR** (Gate 2). Lifecycle is directory-based (`new/` → `archive/`/`rejected/`
  on the lessons branch). **Scope = any behavior file under the project's `.claude/`** (rules, skills,
  rubric, project agents, project dev scripts/hooks) — scope-by-default, **not** a hardcoded folder
  allowlist — with four carve-outs it must **never** edit (→ parking-lot instead): the **flow** (status
  model, gates, AIND operational rules), its own **guardrails** (`settings*.json`, enforcement/signing
  hooks — told from a dev hook by *purpose*, not name), **secrets** (`aind.env`), and anything
  **outside `.claude/`** (product code). A structural problem or generic knowledge (→ the D25 standards
  plugin) is a `aind-dream.sh note` parking-lot entry (`.aind/parking-lot.md`), never a diff. New scripts:
  `aind-emit-lesson.sh`, `aind-dream.sh` (`digest`/`start`/`open-pr`/`consume`/`note`); new agent
  `aind-dreamer`; `aind-common.sh` gains `aind_lessons_branch`/`aind_lessons_ref`/`aind_lessons_push`.
  Offline-validated (plumbing leaves the working tree untouched); **live-validate next** on a testbed
  where a `lint` skill runs an uninstalled eslint (probe: agent emits the defect → `/aind:dream`
  proposes the skill fix).
- **Testing — redesigned (D33, 2026-07-09), supersedes D8/D9/D14/D15; live-validated.**
  The cold test-writer, its same-branch red→green machinery, and the live/E2E agent are **removed
  from the design**. Testing is now: the **planner** records a per-story **test strategy** (whether —
  gated on the project having a test practice, read from its skills/rules — at what altitude, and a
  conditional additive **must-cover list** with expected outcomes, folded into Testing recommendations
  + Definition of done); the **coder authors the tests warm, in-context**; and the **cold reviewer**
  is the independence gate (coverage + fidelity **blocking**, meaningfulness/anti-inflation as
  non-blocking suggestions — the must-cover list is the objective/taste boundary). Live verification
  survives only as an optional Definition-of-done line satisfied by a human PR signal (no agent, no
  E2E CI gate — running the app is a project **skill**). Accepted residual: a diff-reading reviewer
  reduces but doesn't eliminate test-gaming/inflation — **mutation testing** in the project's CI is
  the named-not-built mechanical upgrade. **Docs *and* prompts done (v0.11.0):** `agents/reviewer.md`
  (test-quality mandate — coverage/fidelity block, green suite is never evidence), the planner
  (`commands/plan.md`) test-strategy output, `commands/implement.md` + `commands/approve-plan.md`
  (coder authors tests; approve ratifies the strategy). **Live-validated** on a real story: the
  planner's strategy + must-cover list, the coder-authored tests, and the reviewer's coverage/fidelity
  gate all behaved as designed. **With this, the whole build phase (D24 + D26 + D28 + D33) is now
  fully live-tested.**
- **Deferred by design:** GitHub Actions automation + service identity (D6);
  the dreamer's cross-repo path into the companion standards plugin (D25 — a parking-lot note for now).

## Likely next steps

1. Finish the **Copilot CLI validation**: complete the intake E2E (parity with Claude) and confirm
   the renamed Claude hook loads via the custom `hooks` manifest path (`claude --plugin-dir … --debug`).
   Optionally add a **"verify bash first; never reimplement a script — stop instead" guard** so a
   consumer without bash fails loud rather than improvising (the open hardening item from D22).
2. Live-exercise the **plan-revision loop** (D21): leave PR comments + reply to assumption
   threads, re-run `/aind:plan`, confirm it ingests the feedback and pushes to the same PR
   (`aind-revise-plan-pr.sh` `status`/`begin`/`push`).
3. **Live-validate the dreaming phase** (D30): on a testbed with a `lint` skill that runs an
   uninstalled eslint, run `/aind:implement` and confirm the coder emits the missing-eslint defect as
   an `observation` lesson (`aind-emit-lesson.sh` → `aind/lessons`), then run **`/aind:dream`** and
   confirm the cold `aind-dreamer` clusters it, the human curates (Gate 1), and it proposes the
   skill fix as one `.claude` PR (Gate 2). Exercise the `gh`-live phases of `aind-dream.sh`
   (`start`/`open-pr`) and the human-PR-feedback→`correction`-lesson path via a `/aind:plan` or
   `/aind:implement` revise run. Confirm the dreamer stays inside `.claude` and routes a structural
   finding to `aind-dream.sh note` (`.aind/parking-lot.md`).
