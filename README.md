# AI-Native Dev (AIND)

An AI-native development flow — a multi-agent pipeline that carries an Azure DevOps (ADO) user
story from readiness check → implementation plan → build → review, plus a continuous-improvement
loop — implemented as a reusable **Claude Code plugin**.

This README covers **what it is** and **where it stands**. To set it up and use it, see
**[GETTING-STARTED.md](GETTING-STARTED.md)**. The full design is in `design-doc.md` /
`design-log.md`, with the flow diagram in `docs/index.html`.

> **Scope today:** the **plan phase** (intake → planning → plan review) runs locally via Claude
> Code, by hand (v0 manual scope, D6). The build phase, dreaming phase, and unattended automation
> are designed but not yet built — see [Implementation status](#implementation-status).

## What it does

A **user story** is the unit of work. The flow moves it through phases, each with one or more
agents:

- **Onboarding** (one-time, pre-flow): reads an existing codebase and drafts the project's
  `.claude/` config (rules, skills, rubric copy).
- **Plan phase:** an **intake** agent scores the story against a readiness rubric; a **planner**
  turns an approved story into an implementation plan delivered as a GitHub PR; a human
  reviews and approves it.
- **Build phase** *(designed, not built)*: test-writer → coder → reviewer turn the plan into
  merged code behind objective and review gates.
- **Dreaming phase** *(designed, not built)*: a cold "dreamer" learns from the flow's exhaust
  and proposes config improvements.

State is tracked by a single `AIND status - <state>` tag on the ADO work item; the GitHub PRs
own the fine-grained iteration.

## Concepts

- **Framework vs. project split.** Flow-mechanical pieces (commands, agents, skills, hooks, the
  seed rubric) ship in this plugin and are reused across projects. Project-specific config
  (domain rules, the edited rubric, "how to run the app" skills) lives in each project's own
  `.claude/`.
- **Agents suggest, humans decide.** Intake, the planner, the onboarder, and the dreamer all
  *propose* — a human ratifies (a verdict, a plan merge, a config change).
- **Cold vs. warm.** Independent checks (reviewer, test-writer, dreamer) run *cold* — a separate
  invocation re-grounded from artifacts only — so they can't rubber-stamp the work they review.
  Entry/authoring agents run *warm* (in-session).
- **Config layer vs. the flow.** Agents may shape the `.claude` config; they never change the
  flow itself (the status model, the gates, the structural decisions).
- **Deterministic mechanics are scripted.** Agents make judgments; all ADO/GitHub side-effects
  (tag swaps, signed comments, PRs, links) go through bash scripts — enforced where it matters
  (e.g. a hook requires every ADO comment to be signed by its agent).

Rationale for every choice is in `design-log.md` (decisions **D1–D18**).

## Repository layout

```
.claude-plugin/plugin.json   Plugin manifest (name: aind)
commands/                    onboard, intake, plan, approve-plan  (human entry points)
skills/                      aind-workitem, aind-status, aind-comment, aind-plan-pr, aind-preflight
scripts/                     Bash mechanics over az + gh + curl (the deterministic layer)
hooks/                       PreToolUse hook that enforces signed ADO comments
rubric/intake-rubric.seed.md D11 readiness rubric core (projects copy & extend)
agents/                      (empty — build-phase cold subagents land here next)
project-template/            What a project copies into its own .claude/
deploy.sh                    Publish to GitHub (Release-asset zip + Pages diagram)
design-doc.md, design-log.md The design and the decisions (D1–D18)
GETTING-STARTED.md           Prerequisites, install, setup, usage
```

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

## Docs

- **[GETTING-STARTED.md](GETTING-STARTED.md)** — prerequisites, install/load, project setup, and how to use.
- **`design-doc.md`** — how the flow works (actors, phases, status model, glossary).
- **`design-log.md`** — decisions D1–D18 with rationale.
- **`docs/index.html`** — visual flow diagram (served via GitHub Pages once deployed).
