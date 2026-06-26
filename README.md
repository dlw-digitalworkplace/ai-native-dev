# AI-Native Dev (AIND)

The **design** of an AI-native dev flow (`design-doc.md`, `design-log.md`, `aind-flow.html`)
**and** its implementation as a reusable **Claude Code plugin**. This iteration ships the
**plan phase** — intake, planning, and plan review.

## What's here

```
.claude-plugin/plugin.json   Plugin manifest (name: aind)
commands/                    /onboard, /intake, /plan, /approve-plan  (human entry points)
skills/                      aind-workitem, aind-status, aind-comment, aind-plan-pr, aind-preflight
scripts/                     Bash mechanics over `az` + `gh` (the deterministic layer)
hooks/                       PreToolUse hook that enforces signed ADO comments
rubric/intake-rubric.seed.md D11 readiness rubric core (projects copy & extend)
agents/                      (empty — build-phase cold subagents land here next)
project-template/            What a project copies into its own .claude/
deploy.sh                    Publish to GitHub (Release asset zip + Pages diagram)
design-doc.md, design-log.md The design (D1–D18)
```

**Framework vs project split:** flow-mechanical pieces (commands, agents, skills, hooks, seed
rubric) ship in this plugin and are reused across projects. Project-specific config (rules,
the edited rubric, "how to run the app" skills) lives in the project's own `.claude/`.

## Implementation status

**Implemented:** ✅ done · 🟡 partial · ⬜ not started  
**Tested:** ✅ live (against real ADO/GitHub) · 🟡 offline (syntax/logic/fixtures) · ⬜ not tested · — n/a

| Phase | Step / agent | Implemented | Tested | Notes |
|---|---|:--:|:--:|---|
| Onboarding (pre-flow) | Onboarding agent — `/aind:onboard` | ✅ | ✅ | Three-lens, evidence-only rule discovery (D18). |
| Plan · 0 | Intake agent — `/aind:intake` | ✅ | ✅ | Live-validated fail→fix→pass; signed verdict, scoring, table, tag swap. |
| Plan · 1 | Planner agent — `/aind:plan` | ✅ | ⬜ | Built (plan.md, plan PR, AIND-LINKS, assumption threads); not yet run live. |
| Plan · 2 | Plan review (human) | — | — | Human step in GitHub; no code. |
| Plan · 2 | Close-out — `/aind:approve-plan` | ✅ | ⬜ | Sets `Ready for implementation`; not yet run live. |
| Build | Test-writer agent (optional, cold) | ⬜ | — | Not built. |
| Build | Coding agent | ⬜ | — | Not built. |
| Build | Polish agent (warm) | ⬜ | — | Not built. |
| Build | CI gates | ⬜ | — | Not built. |
| Build | Live / E2E gate (optional) | ⬜ | — | Manual path is the design target for v0 (D15); not built. |
| Build | Reviewer agent (cold) | ⬜ | — | Not built. |
| Build | Merge + `Implementation complete` | ⬜ | — | Not built. |
| Dreaming | Lessons-learned emission | ⬜ | — | Out of scope this iteration (D16). |
| Dreaming | Dreamer agent (cold) | ⬜ | — | Out of scope this iteration (D16). |

## Prerequisites (one-time)

1. **ADO auth:** a PAT with Work Items (r/w) + Code (r/w) in `AZURE_DEVOPS_EXT_PAT`.
2. **GitHub:** `gh` authenticated with access to the target repo.
3. **Tools:** `az` (+ `azure-devops` extension), `gh`, `git`, `curl`, `jq`, `bash`.
4. **Azure Boards ↔ GitHub integration** connected (enables `AB#<id>` native linking, D17).
5. **Branch protection** on the integration branch: *require conversation resolution before
   merging* (so assumption threads gate the plan-PR merge, D5).

## Set up a project

1. Install the plugin (during development, load locally):
   ```bash
   claude --plugin-dir /path/to/ai-native-dev
   ```
2. **Bootstrap the config** — from the project root, run `/aind:onboard`. It reads the
   codebase, discovers domains, and drafts `.claude/` (per-domain rules, `CLAUDE.md`, project
   skills, a rubric copy), then reports prerequisites. **Review and edit the drafts**, then
   commit. *(Or do it by hand: copy `project-template/CLAUDE.md` + `project-template/rules`
   and `rubric/intake-rubric.seed.md` → your project's `.claude/`.)*
3. Copy `project-template/aind.env.sample` → `.claude/aind.env`, fill it in, gitignore it.
4. Run the commands below from the project checkout — the AIND scripts auto-load
   `.claude/aind.env` (walk-up from the working directory), so no manual `source` is needed.
   *(An already-set environment wins, so CI or a parent shell can still override it.)*

> The plugin scripts must be executable in a fresh clone. After committing, set the bit once:
> `git update-index --chmod=+x scripts/*.sh hooks/*.sh`.

## Plan-phase usage

> Plugin commands are **namespaced** with the plugin name (`aind`). Type `/aind` in the
> session to list them — bare `/onboard` will not resolve.

| Command | Phase | Effect |
|---|---|---|
| `/aind:onboard`           | setup | One-time: discover domains, draft `.claude/` config + skills from the codebase, report prerequisites. |
| `/aind:intake <id>`       | 0 | Score the story; signed verdict comment; tag → `Intake approved`/`Intake declined`. |
| `/aind:plan <id>`         | 1 | Write `plans/<id>/plan.md`; open plan PR (AB#, AIND-LINKS); assumptions as resolvable threads; tag → `Plan ready for review`. |
| `/aind:approve-plan <id>` | 2 | After human approves+merges the plan PR: tag → `Ready for implementation`. |

**New to this?** See [GETTING-STARTED.md](GETTING-STARTED.md) for a full walkthrough on a real
project (loading the plugin, the onboard-first flow, auth/config, and troubleshooting).

## End-to-end verification

See the approved plan for the full checklist. In short: create an ADO story tagged
`AIND status - Ready for intake`, run `/intake` (declined → fix → approved), confirm the
signed comment and single status tag; run `/plan`, confirm the plan PR with the `AIND-LINKS`
block, native `AB#` link, and a resolvable thread per assumption; confirm branch protection
blocks merge until threads resolve; merge and run `/approve-plan`.

## Out of scope (next)

Build phase (coder/polish + cold reviewer/test-writer/E2E subagents), the dreaming phase, and
the GitHub Actions automation + service-identity layer (descoped per D6). The layout above
absorbs these without rework.
