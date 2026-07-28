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

- **`STATUS.md`** — **where things stand right now** (what's built/validated, what's next). This
  file (`CLAUDE.md`) holds only **stable rules**; anything fluid lives in `STATUS.md`. **Rule:
  for current status or next steps, read `STATUS.md` — do not add status prose here, and update
  `STATUS.md` (not this file) as work lands.**
- **`design-doc.md`** — how the flow works (actors, phases, status model, glossary).
- **`design-log/`** — the decisions **D1–D42**, **one file per decision** (`D<N>-<slug>.md`) with an
  index at `design-log/README.md`. This is the source of truth for *why* things are the way they
  are. Key ones to know: D4 (single `AIND status` tag invariant),
  D5 (plan PR + resolvable assumption threads), D6 (manual/local v0 scope; automation descoped),
  D10 (separate plan PR, `/plans/<id>/plan.md`), D11 (two-layer hybrid rubric), D13 (merge-then-tag),
  D16 (dreaming phase), D17 (AIND-LINKS), D18 (onboarding agent). A new decision is a **new file**
  (`D43-…`), never an edit to a shared log — so parallel feature PRs don't collide on it.
- **`docs/plans/`** — the planned-feature backlog, one subfolder per feature, each a standalone PR
  (`docs/plans/README.md` indexes them).
- **`docs/index.html`** — visual diagram (published via GitHub Pages).
- **`README.md`** / **`GETTING-STARTED.md`** — install + per-project setup walkthrough.

## Repo layout

```
.claude-plugin/plugin.json   manifest (name: aind)
commands/   onboard, kickstart, intake, plan, approve-plan, implement, complete, dream   (human entry points; namespaced /aind:*)
skills/     aind-workitem, aind-status, aind-comment, aind-plan-pr, aind-preflight
scripts/    bash mechanics over az + gh + curl/jq (the deterministic layer); aind-forge.sh = the GitHub/ADO code-host adapter (D36); aind-usage.sh = per-phase usage telemetry (D42)
hooks/      hooks.claude.json + check-claude-comment.sh (Claude); hooks.copilot.json + check-copilot-comment.{ps1,sh} (Copilot)  — signing enforcement, per-tool format
.github/plugin/plugin.json   Copilot CLI manifest (-> hooks.copilot.json); Claude uses .claude-plugin/plugin.json
rubric/intake-rubric.seed.md                            (D11 core; onboarding copies to project)
project-template/  CLAUDE.md, aind.settings.sample.json, aind.env.sample, rules/_TEMPLATE.md   (what a project copies in)
agents/     reviewer.md (cold code-PR reviewer, D26); dreamer.md (cold lessons synthesiser, D30)
```

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

**Config / env (two-file model, D41).**
- Per-project config is **two files** under `.claude/`, both auto-loaded (walk-up from `$PWD`):
  **`aind.settings.json`** (shared, checked in — ADO org/project, code host, repo, branches, branch
  prefixes, and the `worktree` block) and **`aind.env`** (gitignored — the PAT + optional
  `AIND_ACTOR`). The `AIND_*` env vars are still the interface every script reads; the JSON is just
  storage mapped in by the loader.
- `aind-common.sh` **sources `aind.env` first** (secrets / per-user overrides win) then **jq-maps
  `aind.settings.json`** into any still-unset `AIND_*` var (`.ado.org`→`AIND_ADO_ORG`, etc.); values
  are CRLF-stripped. An already-set `AIND_ADO_ORG` short-circuits the whole load (CI/parent override).
  `aind-preflight.sh` mirrors this inline (it deliberately does *not* source `aind-common.sh`, to
  avoid `set -e`). **No manual `source` needed** anywhere — don't reintroduce that into docs.
- **Worktree opt-in = `worktree.enabled: true` in `aind.settings.json`** (not a separate file's
  presence anymore). `aind-worktree.sh` reads the nested `.worktree.*` keys. Clean break (v0): the
  old `aind-worktree.config.json` is no longer read.
- **Onboard/kickstart create+fill both files** (PAT as a `<pat>` placeholder — never write a real
  secret) and append the gitignore lines idempotently; they no longer just drop `.sample` copies.

**Code host / forge (D36).**
- **All PR/comment/thread mechanics go through `aind-forge.sh`** — never call `gh` or `az repos`
  directly from a PR script. The verbs (`forge_pr_create/list/meta/field/diff/edit_body`,
  `forge_comment`, `forge_thread`, `forge_thread_list`, `forge_comment_list`, `forge_resolve`,
  `forge_reply`) dispatch on `AIND_CODE_HOST` to `_gh_*` / `_ado_*`. A PR script sources the forge
  (which sources `aind-common.sh`), calls `forge_require`, then uses verbs. `aind-preflight.sh` may
  probe `gh`/`az repos` directly — it's the one legitimate exception.
- **Keep PR/thread tokens opaque** across the script↔command/agent boundary. The `thread=<id>` in a
  digest is a GitHub GraphQL node id on one host and an ADO `threadId` on the other — commands/agents
  must pass it back verbatim, never parse it. Don't reintroduce a host-specific field into a prompt.
- **PR state is normalised** to `OPEN`/`MERGED`/`CLOSED` and thread state to `[OPEN]`/`[RESOLVED]` by
  the adapter (GitHub already uses these; ADO `active/completed/abandoned` and `active/fixed/closed`
  are mapped). Callers compare against the normalised values.
- **Mergeability is a normalised forge verb, and `UNKNOWN` is asynchronous, not a verdict.**
  `forge_pr_mergeable` maps `gh` `mergeable` (already `MERGEABLE|CONFLICTING|UNKNOWN`) and ADO
  `mergeStatus` (`succeeded→MERGEABLE`, `conflicts|failure→CONFLICTING`, `queued|notSet→UNKNOWN`) to
  one vocabulary. **Both hosts compute it lazily** — right after a push it's `UNKNOWN` until the host
  recomputes — so `aind-review-pr.sh mergeability` **polls** while `UNKNOWN` and the loop treats a
  lingering `UNKNOWN` as advisory (only a confirmed `CONFLICTING` blocks). Don't gate on `UNKNOWN`.
- **A rebase's push must be `--force-with-lease`, and only when history actually diverged.** Resolving
  a merge conflict rebases the PR head onto moved integration (rewrites history), so a plain
  `git push` is rejected non-fast-forward (the recorded 57-coder lesson). `aind-revise-code-pr.sh
  push` now fetches `origin/<branch>` and uses `--force-with-lease` **only** when
  `git merge-base --is-ancestor origin/<branch> HEAD` is false (diverged); otherwise a plain
  fast-forward push. Scoped to the coder-owned branch + the lease guard = safe. The `/aind:implement`
  review loop's own post-rebase push likewise uses `git push --force-with-lease`.
- **Windows/MSYS leading-slash argv rewrite (bit us once).** Never pass a native `.exe` (jq, curl,
  az) an argument that *starts with* `/` on Git-Bash: MSYS rewrites it to a Windows path
  (`/plans/x` → `C:/Program Files/Git/plans/x`). The ADO inline-thread `filePath` requires a leading
  `/`, so build that slash **inside** jq (`filePath:("/" + $p)`), never in the shell. Same family as
  the UTF-8-via-`--data-binary` and `git show <branch>:<path>` colon gotchas above.
- **ADO PR carrier is spike-defaulted:** the signature marker is a `display:none` span and the
  `AIND-LINKS` block an HTML comment (validated to work on ADO); revisit those two carriers if ADO's
  markdown sanitisation ever changes.

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

**Usage-telemetry plumbing (D42, `aind-usage.sh`).**
- **The only place token counts exist is the agent host's on-disk per-session events file** — the
  bash scripts never see the model's tokens. Locations are undocumented internals, so `aind_collect_usage`
  isolates all path derivation in two backends: Claude `~/.claude/projects/<slug>/<session>.jsonl`
  (slug = the **main-checkout** path with `:` `\` `/` → `-`; falls back to matching each session's
  recorded `.cwd` to the main checkout if the slug transform drifts) + its `<session>/subagents/*.jsonl`;
  Copilot `~/.copilot/session-state/<session>/events.jsonl` (matched via `workspace.yaml`
  `git_root`/`cwd`). Resolve `$HOME` from **`USERPROFILE`** (MSYS `$HOME` can be a mapped drive).
- **Worktree gotcha (bit us on `/aind:plan`): key discovery off the MAIN checkout (`_main_root`),
  never `$PWD`/`git --show-toplevel`.** Claude keys the transcript's project folder to the session's
  *launch* cwd — always the main checkout under drive-from-main — but `/aind:plan` and `/aind:implement`
  let the shell `cd` into a per-phase worktree, so at `report` time `$PWD` is the worktree. Slugging
  `$PWD` (or matching against the worktree's `git --show-toplevel`) then looks under a
  `…-worktrees-<id>-<phase>` slug that doesn't exist → "no session events file found" → no attachment
  (the marker still resolves, because it was already main-rooted, so you get a *silent* miss: empty
  `.aind/usage/` but nothing written). `_claude_file`/`_copilot_file` use `_main_root` (git-common-dir
  → main) for both the slug and the `.cwd`/`git_root` match, so discovery works from inside a worktree.
- **Two summation rules that are load-bearing:** Claude streaming writes **repeat a `message.id`**, so
  aggregation **dedupes by `message.id`** (keying an id-less line by its uuid/timestamp so distinct
  lines aren't collapsed); and **subagent transcripts are NOT rolled into the parent** usage, so they
  are summed in separately (a build total therefore includes the reviewer passes). Claude carries
  `message.model` per message → a per-model breakdown; Copilot events carry no per-message model or
  input/cache → a single `copilot` bucket, **output tokens only**.
- **Attribution is a timestamp window, and there are two of them.** `begin` stamps a marker at
  `<main-checkout>/.aind/usage/<id>-<agent>.json` — rooted at the **main checkout** (via
  `git --git-common-dir`) so `begin` (session on main) and `report` (session may have cd'd into a
  worktree) agree; `report` consumes the marker on read (so a stale marker can't widen a later window).
  **Duration** = `[begin, report]` (active work time). The Claude **token** window is **head-anchored**:
  a slash command's first turn (reading the command + grounding context — a full cache-read) fires
  *before* it can run the `begin` bash step, so the token window starts at the timestamp of the most
  recent `<command-name>/aind:…` invocation in the transcript (`_claude_anchor_lo`), pulling that load
  turn in. The trailing post-`report` narration turn is still unmeasured (report can't see its own
  future) — marginal, and negligible on multi-turn phases. Copilot has no such tag, so it uses `begin`.
- **ADO attachment = the token-breakdown truth; a numeric field = time.** `_attach_upload` POSTs to
  `{org}/{project}/_apis/wit/attachments?fileName=…` then `_attach_link` adds an `AttachedFile`
  relation via a work-item JSON-Patch. As with `aind-status.sh`/`aind-forge.sh`, the `/fields/…` and
  **`/relations/-`** paths are built **inside jq**, never as a shell arg — a leading-slash argv is
  rewritten to a Windows path by MSYS. One append-only attachment **per phase-run** (ADO attachments
  are immutable blobs, so a "kept-current" file would force a fragile read-modify-write).
- **Best-effort, never blocks a phase, inert unless `telemetry.enabled`** — same discipline as the
  lessons emitter above; a missing marker / no session file / missing creds / ADO hiccup all WARN and
  return 0.
- **Windows MAX_PATH + jq (dev/test only):** `jq` is a native `.exe` bound by the ~260-char path
  limit, while MSYS `ls`/`cat` are not. A Claude transcript path is `~/.claude/projects/<slug>/…` where
  the slug is the *full cwd* dashed — fine for a normal checkout, but a deeply-nested **test** cwd can
  push the transcript path past 260 chars and `jq` then reports "No such file or directory" on a file
  that plainly exists. Run offline telemetry tests from a short path.

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
  — a consuming project loads the commands/skills/agents but never sees `design-log/`. So
  everything that ships or is copied into a project — `commands/`, `skills/`, `agents/`,
  `scripts/`, `hooks/`, the rubric seed, and `project-template/` — must be **self-contained**:
  **never** cite a decision ID (`D4`, `D19`, …) or the literal `design-log` in them (prose,
  frontmatter `description`, code comments, or user-facing strings alike). Keep the decision's
  *substance* (e.g. "exactly one AIND status tag per item"), drop the citation. Decision
  references live **only** in the repo's own dev docs: `design-log/`, `design-doc.md`, and this
  `CLAUDE.md`. Quick guard before publishing:
  `grep -rnE 'design-log|\bD[0-9]+\b' commands skills agents scripts hooks rubric project-template`
  should return nothing.
- **Design log is one file per decision (`design-log/D<N>-<slug>.md`).** Adding a decision = adding a
  **new file** and one row to `design-log/README.md`'s index — never editing a shared monolith, so
  concurrent feature PRs don't conflict on it. New numbers (D43+) are assigned **in merge order**
  (assign at merge time, not when the PR is opened, so two open PRs don't both claim D43). A
  decision that supersedes/amends an earlier one adds a new file and marks the old file's **Status**
  line (e.g. `Superseded by D44`) — the only edit to an existing decision file.
- **Never bump the plugin `version` in a feature PR.** Version bumps live in a **separate release
  commit on `main`** (both manifests kept in sync), so parallel feature PRs never collide on
  `plugin.json` / `.github/plugin/plugin.json`. See the publishing note below.
- **Script invocation:** commands/skills call scripts as `bash "${CLAUDE_PLUGIN_ROOT}/scripts/x.sh"`
  (not direct exec) so the plugin runs even when a zip/clone drops the executable bit. Keep new
  calls in that form.
- **Publishing (`deploy.sh`):** publishes to a public GitHub repo for remote loading — a
  root-structured `aind.zip` from `HEAD` (`git archive`) as a **Release asset**, and the diagram
  `docs/index.html` to **Pages** (served from `<branch>/docs`). Load with
  `claude --plugin-url …/releases/latest/download/aind.zip`. The zip is a snapshot — re-deploy
  after changes; bump `plugin.json` `version` for a new release tag. `aind.zip` is gitignored.

