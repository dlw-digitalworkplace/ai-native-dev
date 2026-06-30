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
commands/   onboard, intake, plan, approve-plan        (human entry points; namespaced /aind:*)
skills/     aind-workitem, aind-status, aind-comment, aind-plan-pr, aind-preflight
scripts/    bash mechanics over az + gh + curl/jq (the deterministic layer)
hooks/      hooks.claude.json + check-claude-comment.sh (Claude); hooks.copilot.json + check-copilot-comment.{ps1,sh} (Copilot)  — signing enforcement, per-tool format
.github/plugin/plugin.json   Copilot CLI manifest (-> hooks.copilot.json); Claude uses .claude-plugin/plugin.json
rubric/intake-rubric.seed.md                            (D11 core; onboarding copies to project)
project-template/  CLAUDE.md, aind.env.sample, rules/_TEMPLATE.md   (what a project copies in)
agents/     (empty) — build-phase cold subagents (reviewer, test-writer, E2E, dreamer) land here
```

## Current status (2026-06-30)

- **Dual-host: runs on Claude Code AND GitHub Copilot CLI (D22, 2026-06-30).** One behavior layer
  (commands/skills/scripts); a second manifest (`.github/plugin/plugin.json`) + per-tool hooks
  (`hooks.claude.json` / `hooks.copilot.json`) absorb the only incompatibility. Copilot needs Git's
  `bash` on PATH (Windows) — see the Copilot lesson below. Claude side re-validated (intake, WI 18,
  under the renamed hooks); Copilot intake E2E being confirmed.
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
- **Build phase started — coder designed, not yet built (D24, 2026-06-30).** The coding agent is
  packaged as a **warm in-session command `/aind:implement`** (per D20 — it authors, it is not an
  independent check): a **single** rule-driven coder (per-domain conventions come from each task's
  cited `rules/*.md`, D23), with **polish as its final in-context phase** (D7, no structural change).
  It grounds from the merged plan + cited rules + project build/run **skills** (D18 — dev skills are
  the project's, not the plugin's), and the only new plugin script is `aind-open-code-pr.sh` (the
  GitHub-flow twin of `aind-open-plan-pr.sh`). The coder **generates** its branch as
  `[type]/<id>-<short-name>` (e.g. `feat/123-new-component`); the PR stays the only handle (D17).
  **First iteration scope ends at code-PR creation** — all test authoring is deferred (D8/D9), and
  code review (cold reviewer), the merge gate, and the terminal `Implementation complete` write
  (`/aind:complete`, D13) are the next iterations. Design is documented; `commands/implement.md` +
  the script are the next thing to write.
- **Not built yet:** the rest of the build phase (cold reviewer/test-writer/E2E subagents, merge +
  terminal tag) and the dreaming phase (lessons-learned emission + cold dreamer). Out of scope per
  D6/D16.
- **Deferred by design:** GitHub Actions automation + service identity (D6); automated E2E (D15);
  lessons-learned emission (D16).

## Architecture invariants that constrain how you work

- **Suggest, don't assert.** Agents propose; humans decide (intake D2, onboarding D18, dreamer D16).
- **Config layer vs. flow.** Agents may shape the `.claude` config; they must never change the
  flow (status model, gates, D1–D15). Onboarder bootstraps config from the codebase; dreamer
  evolves it from exhaust — both human-gated, both barred from the flow.
- **Cold vs. warm.** **Cold** roles are the independent **checks** — reviewer, test-writer, E2E,
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
3. Build the **coding agent** (D24): write `commands/implement.md` (the warm `/aind:implement`
   command — ground → implement task breakdown against the Definition of done → in-context polish →
   open code PR; stuck-state mirrors `plan.md`) and `scripts/aind-open-code-pr.sh` (twin of
   `aind-open-plan-pr.sh`, adding the code PR's `AIND-LINKS` block with the plan-PR URL). Scope ends
   at PR creation — no tests, no merge/complete.
4. Then the **build phase** cold subagents in `agents/` (reviewer first), then the merge gate +
   terminal tag (`/aind:complete`, D13).
