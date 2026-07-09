# AIND plugin — working notes (CLAUDE.md)

Context for working **on** the AIND plugin itself. (Not to be confused with
`project-template/CLAUDE.md`, which is the template a *consuming* project copies into its own
`.claude/`.)

## What this repo is

The design **and** implementation of an **AI-Native Dev (AIND)** flow: a multi-agent pipeline
that takes an Azure DevOps (ADO) user story → readiness intake → implementation plan (GitHub PR)
→ build → review, with a cross-cutting "dreaming" improvement loop. This repo is itself a
**plugin for both Claude Code and GitHub Copilot CLI** (manifests: `.claude-plugin/plugin.json` for
Claude, `.github/plugin/plugin.json` for Copilot; name `aind`) that ships the flow's commands,
skills, scripts, hooks, and the seed rubric. A consuming project installs the plugin and layers its
own `.claude/` (rules, edited rubric, project skills) on top. The two hosts share one behavior layer
— only the manifest + hook format differ per host (D22).

## Design docs (read these first for the "why")

- **`design-doc.md`** — how the flow works (actors, phases, status model, glossary).
- **`design-log.md`** — the decisions **D1–D18** with rationale. This is the source of truth for
  *why* things are the way they are. Key ones to know: D4 (single `AIND status` tag invariant),
  D5 (plan PR + resolvable assumption threads), D6 (manual/local v0 scope; automation descoped),
  D10 (separate plan PR, `/plans/<id>/plan.md`), D11 (two-layer hybrid rubric), D13 (merge-then-tag),
  D16 (dreaming phase), D17 (AIND-LINKS), D18 (onboarding agent).
- **`docs/index.html`** — visual diagram (published via GitHub Pages).
- **`README.md`** / **`GETTING-STARTED.md`** — install + per-project setup walkthrough.

## Repo layout

```
.claude-plugin/plugin.json   manifest (name: aind)
commands/   onboard, kickstart, intake, plan, approve-plan, implement, complete, dream   (human entry points; namespaced /aind:*)
skills/     aind-workitem, aind-status, aind-comment, aind-plan-pr, aind-preflight
scripts/    bash mechanics over az + gh + curl/jq (the deterministic layer)
hooks/      hooks.claude.json + check-claude-comment.sh (Claude); hooks.copilot.json + check-copilot-comment.{ps1,sh} (Copilot)  — signing enforcement, per-tool format
.github/plugin/plugin.json   Copilot CLI manifest (-> hooks.copilot.json); Claude uses .claude-plugin/plugin.json
rubric/intake-rubric.seed.md                            (D11 core; onboarding copies to project)
project-template/  CLAUDE.md, aind.env.sample, rules/_TEMPLATE.md   (what a project copies in)
agents/     reviewer.md (cold code-PR reviewer, D26); dreamer.md (cold lessons synthesiser, D30)
```

## Current status (2026-07-09)

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
  `commands/implement.md` + the script are written; live validation is pending.
- **Build phase — code reviewer built (D26, 2026-07-01), pending live validation.** Phase 4 review is
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
  ends at reviewer-approval or human-tiebreak** — no merge, no terminal tag, no test authoring.
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
- **Testing — redesigned (D33, 2026-07-09), supersedes D8/D9/D14/D15; wired, live-validation pending.**
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
  (coder authors tests; approve ratifies the strategy). **Live-validation is the only step left.**
- **Deferred by design:** GitHub Actions automation + service identity (D6);
  the dreamer's cross-repo path into the companion standards plugin (D25 — a parking-lot note for now).

## Architecture invariants that constrain how you work

- **Suggest, don't assert.** Agents propose; humans decide (intake D2, onboarding D18, dreamer D16).
- **Config layer vs. flow.** Agents may shape the `.claude` config; they must never change the
  flow (status model, gates, D1–D15). Onboarder bootstraps config from the codebase; dreamer
  evolves it from exhaust — both human-gated, both barred from the flow.
- **Cold vs. warm.** **Cold** roles are the independent **checks** — reviewer and
  dreamer: a separate invocation re-grounded from artifacts only, so their judgment isn't
  contaminated by the work they're checking → these are **subagents** in `agents/`. **Warm** roles
  are human-facing **authoring/entry** roles with nothing to stay independent *from* (a human
  reviews their output): intake, the planner, **and the coder** run **in-session as slash commands**
  (`/aind:intake`, `/aind:plan`, `/aind:implement`); polish runs in the coder's context as that
  command's final phase (D24). Per-role model for a command
  is set by choosing the **session** model per invocation (the phases are gated apart anyway), not
  by a subagent. *(D19 briefly made intake/planner cold subagents; D20 reverted them — independence,
  not model selection, is what justifies coldness, and these two don't need it. See design-log.)*
- **Commands are thin.** Judgment + orchestration only; all deterministic ADO/GitHub mechanics live
  in `scripts/` and are reused via `skills/`. "What can be scripted should be scripted."
- **Rubric is data, command is procedure.** `/aind:intake` is criteria-agnostic: it reads the
  project rubric's **Objective**/**Judgment** sections and scores whatever it finds. Never hardcode
  criteria in the command.

## Hard-won operational lessons (don't re-learn these)

**ADO work-item comments are an HTML rich-text field, not markdown.**
- `aind-comment.sh` runs `md_to_html()` (an awk converter) over a markdown subset: headings,
  `-`/`1.` lists, `**bold**`, `` `code` ``, paragraphs, and **pipe tables**. Stay in that subset;
  nested lists and links don't render. (User confirmed `<table>` renders in ADO.)
- **ADO strips HTML comments**, so the agent-signature marker is a `display:none` span
  (`<span style="display:none">AIND-AGENT: <name></span>`) — invisible when rendered, still
  greppable in stored text. Don't switch it back to an HTML comment.
- **Windows/MSYS UTF-8 gotcha:** multibyte chars (the em-dash in the signature) get mangled if
  passed as an inline `curl -d` argument. Always send the body via a **temp file + `--data-binary`**
  and `Content-Type: …; charset=utf-8`. Capture HTTP status + ADO `.message` so failures are
  legible.

**Setting the `AIND status` tag (D4: exactly one).**
- **Never** write tags with `az boards work-item update --fields "System.Tags=…"` — on at least
  one `az` build that emits a JSON-Patch **`add`** which *merges* into existing tags (leaves two
  AIND status tags). `aind-status.sh` writes via **REST PATCH with `op: replace`** (curl + PAT),
  using `add` only when the item has no tags yet (field absent). Reads still use `az`.
- Tag matching is **normalized** (strip `\r`, lowercase, collapse whitespace) so UI casing/spacing
  and `az.cmd` CRLF can't leave a stale tag. The script **verifies** post-write and auto-corrects +
  warns if ≠1 AIND tag.

**Config / env.**
- `aind-common.sh` **auto-sources** the project's `.claude/aind.env` (walk-up from `$PWD`);
  an already-set `AIND_ADO_ORG` wins (CI/parent override). `aind-preflight.sh` self-sources the
  same way inline (it deliberately does *not* source `aind-common.sh`, to avoid `set -e`).
  **No manual `source` needed** anywhere — don't reintroduce that instruction into docs.

**Plugin loading & commands.**
- `claude --plugin-dir <repo-root>` loads this single plugin for the session.
- Commands are **namespaced**: `/aind:onboard`, `/aind:intake`, etc. — bare `/onboard` won't
  resolve. Validate structure with **plain `claude plugin validate <path>`** (expect **exit 0 with
  one warning** — see next bullet).
- **Known & accepted validation warning — don't re-investigate.** Validation reports:
  *"CLAUDE.md at the plugin root is not loaded as project context. To ship context with your plugin,
  use a skill instead."* This is **expected and deliberately accepted**: this repo *is* the plugin
  (manifest at the repo root), so the root `CLAUDE.md` doubles as committed, in-repo **dev-notes**
  (auto-loaded only when working *in* this repo) — it is **not** consumer-shipped context, and a
  plugin's root `CLAUDE.md` is never loaded for consumers regardless, so the warning is a false
  positive for this layout. Consequence: **`--strict` will fail on it** — that's by design, not a
  regression, so use plain `validate`. *Considered and declined* (2026-06-26): moving the plugin
  under a subdir (`aind/`) to split plugin-root from repo-root — correct but not worth the churn;
  and renaming to `CLAUDE.local.md` — rejected because `.local` is the personal/gitignored
  convention, wrong for committed shared notes.

**Signing enforcement.**
- **PR comments are signed too — not just ADO comments.** Every GitHub PR comment/thread/reply
  goes through a plugin script that appends the agent signature via `aind_gh_signature <agent>`
  (in `aind-common.sh`): `aind-thread.sh` (planner assumptions / reviewer findings),
  `aind-review-pr.sh summary|thread|reply` (reviewer + coder — these take an explicit `<agent>`
  arg), and `aind-revise-code-pr.sh push` / `aind-revise-plan-pr.sh push|reply` (hardcode `coder` /
  `planner`, since each is single-author). Same rationale as ADO signing: in local mode the coder,
  reviewer, and planner post under **one** GitHub identity, so the signature is what tells them
  apart. GitHub renders markdown and **preserves HTML comments**, so the machine marker there is a
  real `<!-- AIND-AGENT: <name> -->` (greppable, invisible when rendered) — *not* the display:none
  span ADO needs (ADO strips HTML comments). Unlike ADO, there is **no PreToolUse hook** enforcing
  the PR path yet — signing holds because every PR-comment site already routes through these
  scripts; a raw `gh pr comment` would bypass it. PR **bodies** (open-plan-pr / open-code-pr) are
  deliberately left unsigned — they're the artifact, authored once, and carry the `AIND-LINKS` marker.
- All ADO comments must go through `aind-comment.sh` (it signs). The `PreToolUse` hook
  (`hooks/check-claude-comment.sh`, wired via `.claude-plugin/plugin.json`'s `hooks` field) blocks
  raw comment calls (`…/_apis/wit/workItems/<id>/comments`, `az devops invoke … comments`). Logic is
  unit-tested; live harness enforcement is best confirmed in a `--plugin-dir` session.
- **Copilot CLI uses a separate hook** (`hooks/check-copilot-comment.ps1`/`.sh` via
  `hooks/hooks.copilot.json`, referenced by `.github/plugin/plugin.json`): different schema
  (`version:1`/`preToolUse`, `bash`+`powershell` keys), different I/O (reads `toolArgs` JSON on
  stdin, returns a `permissionDecision` JSON; it does **not** use exit-code 2). Same enforcement
  intent. Each tool loads only its own hook file — they don't collide.

**Copilot CLI (second host) — what's the same, what differs.**
- **Install:** `copilot plugin install <owner>/<repo>` (or a local path — local installs are
  **snapshots**, so re-install after changes). Commands register **namespaced** (`/aind:intake`)
  exactly as in Claude; the manifest is read directly. Confirmed live on Copilot CLI 1.0.65.
- **Manifest split:** Copilot reads `.github/plugin/plugin.json` (preferred over `.claude-plugin/`);
  Claude reads `.claude-plugin/plugin.json`. Each points its own `hooks` field at its own hook file.
  **Keep the two manifests' non-hook fields in sync** when you edit one.
- **`${CLAUDE_PLUGIN_ROOT}` works under Copilot** — it's injected into the hook env alongside
  `PLUGIN_ROOT`/`COPILOT_PLUGIN_ROOT`; no token rename needed. (Stale docs claimed otherwise — wrong.)
- **The *right* `bash` must WIN on PATH (Windows) — non-negotiable.** Copilot's shell tool is
  **PowerShell**; if Git's `bash` doesn't resolve, the model either **reimplements the scripts in
  PowerShell** (silently breaking the single-`AIND status` tag invariant + comment signing — observed:
  duplicate tags, unsigned comment via ad-hoc `az`/REST) or **gives up mid-run** ("no bash/ADO access").
  - **Two traps, both hit live:** (1) the Git installer puts only `Git\cmd` (has `git`, not `bash`) on
    PATH; (2) Windows ships **`C:\Windows\System32\bash.exe` (the WSL launcher)** which **shadows Git's
    bash** and errors `No such file or directory` when no WSL distro exists. Because `System32` is on
    the **machine** PATH (searched before user PATH), **appending `Git\bin` to the user PATH does NOT
    win** — Git's bash must come *first*.
  - **Fix that actually works:** **prepend** `C:\Program Files\Git\bin` in the PowerShell `$PROFILE`
    (`$env:PATH = "C:\Program Files\Git\bin;" + $env:PATH`), so every new shell (and `copilot` launched
    from it) resolves Git's bash first. Verify with **`(Get-Command bash).Source`** → must be Git's
    bash, not `System32\bash.exe`. (A session-level prepend works too; a permanent *user-PATH append*
    does not, and disabling the WSL app-execution alias alone doesn't remove the System32 launcher.)
  - **Fresh terminal required** after any PATH/profile change — Windows Terminal/VS Code cache env at
    host launch, so a new *tab* isn't enough. When Git's bash wins, scripts run and signing/tagging
    behave exactly as on Claude.
- **Trust a live `copilot` over docs.** This port corrected stale docs repeatedly (commands
  "unsupported", no `CLAUDE_PLUGIN_ROOT`, hook format) — every time, installing and running was the
  corrective. Validate empirically, not by searching.

**Permissions / allowlisting (avoid prompt spam).**
- **Invoke every script as a single command — never a pipeline.** Feed multi-line input to
  `aind-comment.sh` with a **direct heredoc** — `bash "…/aind-comment.sh" <id> <agent> <<'EOF'` —
  **not** `cat <<'EOF' | bash "…/aind-comment.sh" …`. A pipeline makes the harness check *each side*
  separately, so the `cat` half can't be covered by the script allow-rule and the call re-prompts
  forever. A single `bash "${CLAUDE_PLUGIN_ROOT}/scripts/…"` command is matched by one rule.
- **Permissions come from the project Claude runs in, not the plugin.** A consuming project (or this
  repo, when testing here) silences the prompts by adding to its **own** `.claude/settings.local.json`:
  `"Bash(bash \"${CLAUDE_PLUGIN_ROOT}/scripts/*)"` — one rule covers all scripts. The literal
  `${CLAUDE_PLUGIN_ROOT}` is matched *pre-expansion*, so the rule is machine-independent. The plugin
  cannot ship allow-rules into a consumer's settings; document the rule (or have `/aind:onboard`
  write it) instead.

**Rubric guard (no silent fallback).**
- `/aind:intake` runs `aind-rubric-check.sh .claude/intake-rubric.md` first and **stops without
  touching the work item** if the rubric is missing (exit 2), empty (3), or has no objective
  criteria (4). The plugin seed is a copy-at-onboarding template, **not** a runtime fallback.

**Lessons stream / dreaming plumbing (D30).**
- **Emission must never disturb the agent's session.** `aind-emit-lesson.sh` (and `aind-dream.sh`
  `consume`/`note`) write to the `aind/lessons` branch **without checking it out** — they build the
  new tree in a throwaway `GIT_INDEX_FILE`, `git commit-tree` it onto the branch tip, `update-ref`,
  and push (helpers `aind_lessons_ref`/`aind_lessons_push` in `aind-common.sh`). This is deliberate:
  a coder can emit mid-implementation and stay on its feature branch, working tree untouched. Don't
  "simplify" this to a `git checkout aind/lessons` — that would yank the agent off its branch.
- **The lessons branch is an orphan** — no shared history with the code, so it can never merge into
  or diff against integration. `aind_lessons_ref` resolves it remote-first (a fresh clone/other
  machine may have emitted since), then local. A rejected push means a concurrent emit raced it →
  the script fails so the caller re-runs (records are never silently lost).
- **Lifecycle is directory-based, not a status field:** `.aind/lessons/new/` → `archive/` (folded
  into a dream PR) or `rejected/` (curated out). Un-actioned lessons stay in `new/` on purpose — the
  pool for future pattern detection. Don't add a `status:` front-matter field (it would be a second,
  drift-prone source of truth).
- **MSYS colon gotcha (dev only):** reading a file from the branch as `git show "<branch>:<path>"`
  gets mangled by Git-Bash on Windows when the ref has slashes before the `:` (`aind/lessons:…` →
  `aind\lessons;…`). The scripts avoid this by resolving to a **SHA first** and using `<sha>:<path>`
  — do the same in any ad-hoc check.

## Conventions for editing & testing

- **Language:** Bash scripts wrapping `az` + `gh` + `curl`/`jq` (portable to the future Linux/CI
  automation phase). Deps: `az` (+ azure-devops ext), `gh`, `git`, `curl`, `jq`.
- **`jq` is required** and is often **not** installed on the dev box — `aind-preflight.sh` flags it.
- After adding scripts, set the exec bit for fresh clones: `git update-index --chmod=+x scripts/*.sh hooks/*.sh`.
- **Can't hit live ADO/GitHub from a dev session** — verify with: `bash -n` (syntax), offline unit
  tests of the awk/bash logic (e.g. feed `md_to_html` sample markdown; feed the hook sample
  tool-call JSON; run `aind-rubric-check.sh` against fixtures). This is how intake's fixes were
  validated before the user's live runs.
- Keep the plugin **portable** — no project-specific values (org/repo/account) in code or docs;
  use `<placeholders>`. Config comes from env / `.claude/aind.env`.
- **No design-log references in shipped artifacts.** The design log is **not** part of the plugin
  — a consuming project loads the commands/skills/agents but never sees `design-log.md`. So
  everything that ships or is copied into a project — `commands/`, `skills/`, `agents/`,
  `scripts/`, `hooks/`, the rubric seed, and `project-template/` — must be **self-contained**:
  **never** cite a decision ID (`D4`, `D19`, …) or the literal `design-log` in them (prose,
  frontmatter `description`, code comments, or user-facing strings alike). Keep the decision's
  *substance* (e.g. "exactly one AIND status tag per item"), drop the citation. Decision
  references live **only** in the repo's own dev docs: `design-log.md`, `design-doc.md`, and this
  `CLAUDE.md`. Quick guard before publishing:
  `grep -rnE 'design-log|\bD[0-9]+\b' commands skills agents scripts hooks rubric project-template`
  should return nothing.
- **Script invocation:** commands/skills call scripts as `bash "${CLAUDE_PLUGIN_ROOT}/scripts/x.sh"`
  (not direct exec) so the plugin runs even when a zip/clone drops the executable bit. Keep new
  calls in that form.
- **Publishing (`deploy.sh`):** publishes to a public GitHub repo for remote loading — a
  root-structured `aind.zip` from `HEAD` (`git archive`) as a **Release asset**, and the diagram
  `docs/index.html` to **Pages** (served from `<branch>/docs`). Load with
  `claude --plugin-url …/releases/latest/download/aind.zip`. The zip is a snapshot — re-deploy
  after changes; bump `plugin.json` `version` for a new release tag. `aind.zip` is gitignored.

## Likely next steps

1. Finish the **Copilot CLI validation**: complete the intake E2E (parity with Claude) and confirm
   the renamed Claude hook loads via the custom `hooks` manifest path (`claude --plugin-dir … --debug`).
   Optionally add a **"verify bash first; never reimplement a script — stop instead" guard** so a
   consumer without bash fails loud rather than improvising (the open hardening item from D22).
2. Live-exercise the **plan-revision loop** (D21): leave PR comments + reply to assumption
   threads, re-run `/aind:plan`, confirm it ingests the feedback and pushes to the same PR
   (`aind-revise-plan-pr.sh` `status`/`begin`/`push`).
3. **Live-validate the build phase end-to-end** (D24 + D26 + D27): run `/aind:implement` on a real
   `Ready for implementation` story — confirm it builds → opens the code PR → the cold reviewer
   (`aind-reviewer`) challenges it → the coder fixes/rebuts across passes → the loop ends at a
   `CLEAN` approval or a 3-pass human tiebreak (and that `CANNOT-REVIEW` raises `Needs attention`).
   Exercise the `gh`-live phases of `aind-review-pr.sh` (`fetch`/`summary`/`thread`/`resolve`/`reply`)
   that offline tests couldn't cover. (The **`/aind:complete`** close-out is already **live-validated**
   on AB#19.) Then live-validate the **code-revision loop** (D28): with the code PR open, leave a PR
   comment asking for a change (AB#19's unapplied `minHeight:44` suggestion is the ready-made case),
   re-run `/aind:implement 19`, and confirm it enters revise mode, applies **only** that change, pushes
   to the same PR, re-reviews, and never moves the tag — then `/aind:complete 19`.
4. **Live-validate the dreaming phase** (D30): on a testbed with a `lint` skill that runs an
   uninstalled eslint, run `/aind:implement` and confirm the coder emits the missing-eslint defect as
   an `observation` lesson (`aind-emit-lesson.sh` → `aind/lessons`), then run **`/aind:dream`** and
   confirm the cold `aind-dreamer` clusters it, the human curates (Gate 1), and it proposes the
   skill fix as one `.claude` PR (Gate 2). Exercise the `gh`-live phases of `aind-dream.sh`
   (`start`/`open-pr`) and the human-PR-feedback→`correction`-lesson path via a `/aind:plan` or
   `/aind:implement` revise run. Confirm the dreamer stays inside `.claude` and routes a structural
   finding to `aind-dream.sh note` (`.aind/parking-lot.md`).
5. **Live-validate the testing redesign** (D33, wired in v0.11.0): a story whose plan carries a
   must-cover list → `/aind:implement` has the coder author the tests at the stated altitude → confirm
   the cold reviewer catches a **missing must-cover case** (WARNING) and an **assert-to-bug** test
   (CRITICAL — a green test masking a defect), and does *not* block on a taste-level test nit. Also
   confirm the planner correctly recommends **no automated tests** on a project with no test practice,
   and that the coder then writes none (no per-story framework bootstrap).
