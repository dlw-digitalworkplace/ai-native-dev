# AI-Native Dev (AIND)

An AI-native development flow — a multi-agent pipeline that carries an Azure DevOps (ADO) user
story from readiness check → implementation plan → build → review, plus a continuous-improvement
loop — implemented as a reusable plugin that runs on **Claude Code** and **GitHub Copilot CLI**.

This README covers **what it is** and **where it stands**. To set it up and use it, see
**[GETTING-STARTED.md](GETTING-STARTED.md)**. The full design is in `design-doc.md` /
`design-log.md`, with the flow diagram in `docs/index.html`.

> **Scope today:** the **plan phase** (intake → planning → plan review) and the build phase —
> **coding** (`/aind:implement`, which builds the code PR then drives an independent **code review**
> to a verdict, and on a re-run **revises** the open PR from the human's steering) and **close-out**
> (`/aind:complete`, which verifies the merged PR and writes the terminal status) — run locally via
> **Claude Code or GitHub Copilot CLI**, by hand (v0 manual scope, D6). The **dreaming phase**
> (`/aind:dream`) is now built and live-validated. A test-writer and unattended automation are
> designed but not yet built — see [Implementation status](#implementation-status).

## What it does

A **user story** is the unit of work. The flow moves it through phases, each with one or more
agents:

- **Onboarding** (one-time, pre-flow): reads an existing codebase and drafts the project's
  `.claude/` config (rules, skills, rubric copy). For a **new/greenfield** project with no code to
  scan, a companion **kickstart** step elicits the same config through a guided conversation.
- **Plan phase:** an **intake** agent scores the story against a readiness rubric; a **planner**
  turns an approved story into an implementation plan delivered as a GitHub PR; a human
  reviews and approves it.
- **Build phase** *(coder + reviewer + revision loop + merge close-out built)*: a **coding agent**
  (`/aind:implement`) builds an approved plan into a GitHub code PR, then a cold, independent
  **reviewer** challenges it and the two iterate to a verdict; a human can **steer the coder from the
  PR** on a re-run (apply a picked suggestion or a tiebreak verdict — revise mode); once a human
  merges, **`/aind:complete`** verifies the merge and writes the terminal `Implementation complete`
  status. A test-writer is designed but not yet built.
- **Dreaming phase** *(built)*: agents emit lessons-learned to a dedicated branch as they run; the
  manual **`/aind:dream`** command has a cold "dreamer" cluster that exhaust into patterns, a human
  curates the clusters, and the approved ones land as one `.claude` config PR to accept or reject.

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
  (e.g. a hook requires every ADO comment to be signed by its agent). Comments on GitHub PRs —
  review summaries, resolvable threads, and replies — are signed by the posting agent too, so a
  reviewer finding and a coder rebuttal stay distinguishable under one shared GitHub identity.

Rationale for every choice is in `design-log.md` (decisions **D1–D31**).

## Repository layout

```
.claude-plugin/plugin.json   Claude Code manifest (name: aind)
.github/plugin/plugin.json   GitHub Copilot CLI manifest (same plugin; points to the Copilot hook)
commands/                    onboard, kickstart, intake, plan, approve-plan, implement, complete, dream  (human entry points)
skills/                      aind-workitem, aind-status, aind-comment, aind-plan-pr, aind-preflight
scripts/                     Bash mechanics over az + gh + curl (the deterministic layer)
hooks/                       Per-host PreToolUse hooks enforcing signed ADO comments (Claude + Copilot)
rubric/intake-rubric.seed.md D11 readiness rubric core (projects copy & extend)
agents/                      reviewer.md (cold code-PR reviewer), dreamer.md (cold lessons synthesiser); test-writer/E2E land here next
project-template/            What a project copies into its own .claude/
deploy.sh                    Publish to GitHub (Release-asset zip + Pages diagram)
design-doc.md, design-log.md The design and the decisions (D1–D31)
GETTING-STARTED.md           Prerequisites, install, setup, usage
```

## Implementation status

**Implemented:** ✅ done · 🟡 partial · ⬜ not started  
**Tested:** ✅ live (against real ADO/GitHub) · 🟡 offline (syntax/logic/fixtures) · ⬜ not tested · — n/a

| Phase | Step / agent | Implemented | Tested | Notes |
|---|---|:--:|:--:|---|
| Onboarding (pre-flow) | Onboarding agent — `/aind:onboard` | ✅ | ✅ | Three-lens, evidence-only rule discovery (D18). |
| Onboarding (pre-flow) | Kickstart agent — `/aind:kickstart` | ✅ | ✅ | Greenfield twin of onboard (D31): guided conversation → drafts the same `.claude/` config when there's no code to scan; skills cover build/test/run **and** other dev workflows (deploy, migrate, seed, …); undecided items become TODOs, never fabricated rules. Live-validated (session run). |
| Plan · 0 | Intake agent — `/aind:intake` | ✅ | ✅ | Live-validated fail→fix→pass; signed verdict, scoring, table, tag swap. |
| Plan · 1 | Planner agent — `/aind:plan` | ✅ | ✅ | Live-validated (plan.md, plan PR, AIND-LINKS, assumption threads). Enriched plan template (D23): keep-it-simple/non-goals, conditional data contracts, rule-citing task breakdown, considerations, sourced definition-of-done. |
| Plan · 2 | Plan review (human) | — | — | Human step in GitHub; no code. |
| Plan · 2 | Close-out — `/aind:approve-plan` | ✅ | ✅ | Live-validated: refuses while the plan PR is unmerged; once merged, sets `Ready for implementation` and runs plan-branch cleanup. |
| Build | Test-writer agent (optional, cold) | ⬜ | — | Not built; test authoring deferred this iteration (D8). |
| Build | Coding agent — `/aind:implement` | ✅ | ✅ | Live-validated end-to-end on a real story: precondition gate, grounding + existing-pattern reuse, pre-PR project build, deviation reporting, code PR with AIND-LINKS + AB# linking. Now also drives the review loop below (D24) and is **mode-aware** — a re-run revises the open PR (D28); scope ends at reviewer approval / human tiebreak. |
| Build | Polish (warm) — in `/aind:implement` | ✅ | ✅ | Final in-context phase of the coder — style/self-consistency only, no structural change. |
| Build | CI gates | ⬜ | — | Coder runs the project build locally before the PR; CI-pipeline gates not built. |
| Build | Live / E2E gate (optional) | ⬜ | — | Manual path is the design target for v0 (D15); not built. |
| Build | Reviewer agent (cold) — in `/aind:implement` | ✅ | ✅ | Live-validated: spawned cold from the coder with only the work-item id + PR number; checks the diff against the plan **and** the full rule/skill set; CRITICAL+WARNING block, SUGGESTION doesn't; posts resolvable threads + a summary; ≤3 passes with warm-coder fixes; deadlock → human tiebreak, tag unchanged (D26). |
| Build | Code-revision loop — `/aind:implement` revise mode | ✅ | ✅ | Re-run on a story with an open code PR enters revise mode: check out the PR branch, read the steering digest, apply **only** human-directed changes (a picked suggestion, a tiebreak verdict, a touch-up), reply on threads (never resolve), push to the same PR, re-review by default (D28). Live-validated on a real story: applied only the directed change, re-reviewed CLEAN, tag unmoved. |
| Build | Merge + `Implementation complete` — `/aind:complete` | ✅ | ✅ | Live-validated on AB#19: resolves the code PR, verifies MERGED (refuses otherwise), writes the terminal tag, posts a signed note, and cleans up the merged branch — verify-then-tag, merge first (D13/D27). |
| Dreaming | Lessons-learned emission — `aind-emit-lesson.sh` | ✅ | ✅ | Live-validated: each agent emits a signed record (severity enum + observation) to the `aind/lessons` orphan branch at session end, via worktree-safe git plumbing; human PR feedback becomes correction/suggestion lessons through the revise runs (D30). |
| Dreaming | Dreamer agent (cold) — `/aind:dream` | ✅ | ✅ | Live-validated end-to-end: the cold dreamer clusters unprocessed lessons and judges them (severity × recurrence × factualness), a human curates the clusters (gate 1), and approved clusters land as one `.claude` PR (gate 2). Caught a seeded lint-skill defect **and** surfaced genuine project-rule gaps (e.g. backend input-file-type validation); scope stays within `.claude`, structural findings → parking-lot (D30). |

## Docs

- **[GETTING-STARTED.md](GETTING-STARTED.md)** — prerequisites, install/load, project setup, and how to use.
- **`design-doc.md`** — how the flow works (actors, phases, status model, glossary).
- **`design-log.md`** — decisions D1–D31 with rationale.
- **[CHANGELOG.md](CHANGELOG.md)** — what changed in each released version.
- **`docs/index.html`** — visual flow diagram (served via GitHub Pages once deployed).
