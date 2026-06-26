# AIND plugin — working notes (CLAUDE.md)

Context for working **on** the AIND plugin itself. (Not to be confused with
`project-template/CLAUDE.md`, which is the template a *consuming* project copies into its own
`.claude/`.)

## What this repo is

The design **and** implementation of an **AI-Native Dev (AIND)** flow: a multi-agent pipeline
that takes an Azure DevOps (ADO) user story → readiness intake → implementation plan (GitHub PR)
→ build → review, with a cross-cutting "dreaming" improvement loop. This repo is itself a
**Claude Code plugin** (`.claude-plugin/plugin.json`, name `aind`) that ships the flow's
commands, skills, scripts, hooks, and the seed rubric. A consuming project installs the plugin
and layers its own `.claude/` (rules, edited rubric, project skills) on top.

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
hooks/      hooks.json + check-signed-comment.sh        (PreToolUse signing enforcement)
rubric/intake-rubric.seed.md                            (D11 core; onboarding copies to project)
project-template/  CLAUDE.md, aind.env.sample, rules/_TEMPLATE.md   (what a project copies in)
agents/     (empty) — build-phase cold subagents land here next
```

## Current status (2026-06-26)

- **Plan phase = implemented.** **Intake (`/aind:intake`) is live-validated** end-to-end
  (fail→fix→pass, signed comments, tag transitions, scoring, table output all confirmed by the
  user). **Onboarding (`/aind:onboard`) is validated.** **Planner (`/aind:plan`,
  `aind-open-plan-pr`, `aind-links`, `aind-thread`) and `/aind:approve-plan` are implemented but
  NOT yet exercised live** — that's the natural next step.
- **Not built yet:** build phase (coder/polish + cold reviewer/test-writer/E2E subagents) and the
  dreaming phase (lessons-learned emission + cold dreamer). Out of scope per D6/D16.
- **Deferred by design:** GitHub Actions automation + service identity (D6); automated E2E (D15);
  lessons-learned emission (D16).

## Architecture invariants that constrain how you work

- **Suggest, don't assert.** Agents propose; humans decide (intake D2, onboarding D18, dreamer D16).
- **Config layer vs. flow.** Agents may shape the `.claude` config; they must never change the
  flow (status model, gates, D1–D15). Onboarder bootstraps config from the codebase; dreamer
  evolves it from exhaust — both human-gated, both barred from the flow.
- **Cold vs. warm.** Independent checks (reviewer, test-writer, E2E, dreamer) must be **cold** —
  separate invocation, re-grounded from artifacts only → these become **subagents** in `agents/`.
  Warm/entry roles (intake, planner, polish) run in-session → slash **commands**.
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
  resolve. Validate structure with `claude plugin validate <path>` (`--strict`).

**Signing enforcement.**
- All ADO comments must go through `aind-comment.sh` (it signs). The `PreToolUse` hook
  (`hooks/check-signed-comment.sh`) blocks raw comment calls (`…/_apis/wit/workItems/<id>/comments`,
  `az devops invoke … comments`). Logic is unit-tested; live harness enforcement is best confirmed
  in a `--plugin-dir` session.

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
- **Script invocation:** commands/skills call scripts as `bash "${CLAUDE_PLUGIN_ROOT}/scripts/x.sh"`
  (not direct exec) so the plugin runs even when a zip/clone drops the executable bit. Keep new
  calls in that form.
- **Publishing (`deploy.sh`):** publishes to a public GitHub repo for remote loading — a
  root-structured `aind.zip` from `HEAD` (`git archive`) as a **Release asset**, and the diagram
  `docs/index.html` to **Pages** (served from `<branch>/docs`). Load with
  `claude --plugin-url …/releases/latest/download/aind.zip`. The zip is a snapshot — re-deploy
  after changes; bump `plugin.json` `version` for a new release tag. `aind.zip` is gitignored.

## Likely next steps

1. Live-exercise the **planner** (`/aind:plan`): plan PR, AIND-LINKS, resolvable assumption
   threads, testing recommendations (D8/D9).
2. Then the **build phase** cold subagents in `agents/` (reviewer first).
