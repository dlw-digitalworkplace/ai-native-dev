# AI-Native Dev (AIND)

An AI-native development flow — a multi-agent pipeline that carries a user story from readiness
check → implementation plan → build → review, plus a continuous-improvement loop — packaged as a
reusable plugin that runs on **Claude Code** and **GitHub Copilot CLI**.

AIND is built around three independent, per-project choices:

- **Agent host** — where the agents run: **Claude Code** or **GitHub Copilot CLI**.
- **Code host** — where the code and its pull requests live: **GitHub** or **Azure DevOps Repos**
  (`AIND_CODE_HOST`).
- **Work-item tracker** — where the stories live: **Azure DevOps Boards** or a **local markdown
  file** per item (`AIND_TRACKER`).

The three are orthogonal — pick each independently. On top of the core flow, AIND adds opt-in
**git-worktree parallelism** (drive several stories from one clone) and opt-in **usage telemetry**
(per-phase raw token + time recorded onto the work item).

📖 **[Getting started](https://dlw-digitalworkplace.github.io/ai-native-dev/getting-started.html)**
· **[Reference docs](https://dlw-digitalworkplace.github.io/ai-native-dev/docs.html)**
· **[Flow diagram](https://dlw-digitalworkplace.github.io/ai-native-dev/)**

## What it does

A **user story** is the unit of work. The flow moves it through phases, each with one or more
agents:

- **Onboarding** (one-time, pre-flow): reads an existing codebase and drafts the project's
  `.claude/` config (rules, skills, rubric copy). For a **new/greenfield** project with no code to
  scan, a companion **kickstart** step elicits the same config through a guided conversation.
- **Plan phase:** an **intake** agent scores the story against a readiness rubric — and declines it
  if a story it depends on isn't implemented yet (a dependency gate, orthogonal to the score); a
  **planner** turns an approved story into an implementation plan delivered as a pull request; a
  human reviews and approves it.
- **Build phase:** a **coding agent** (`/aind:implement`) builds an approved plan into a code PR,
  then a cold, independent **reviewer** challenges it and the two iterate to a verdict; a human can
  **steer the coder from the PR** on a re-run. Once a human merges, **`/aind:complete`** verifies
  the merge and writes the terminal `Implementation complete` status. The planner sets a per-story
  test strategy, the coder authors the tests in-context, and the cold reviewer is the independence
  gate on test quality.
- **Dreaming phase:** agents emit lessons-learned to a dedicated branch as they run; the manual
  **`/aind:dream`** command has a cold "dreamer" cluster the exhaust into patterns, a human curates
  the clusters, and the approved ones land as one `.claude` config PR to accept or reject.

State is tracked by a single `AIND status - <state>` value on the work item (an ADO tag or a
front-matter field, depending on the tracker); the code-host PRs own the fine-grained iteration.

## Concepts

- **Framework vs. project split.** Flow-mechanical pieces (commands, agents, skills, hooks, the
  seed rubric) ship in this plugin and are reused across projects. Project-specific config
  (domain rules, the edited rubric, "how to run the app" skills) lives in each project's own
  `.claude/`.
- **Agents suggest, humans decide.** Intake, the planner, the onboarder, and the dreamer all
  *propose* — a human ratifies (a verdict, a plan merge, a config change).
- **Cold vs. warm.** Independent checks (reviewer, dreamer) run *cold* — a separate
  invocation re-grounded from artifacts only — so they can't rubber-stamp the work they review.
  Entry/authoring agents run *warm* (in-session); the coder authors its own tests warm, and the cold
  reviewer is what independently checks them.
- **Config layer vs. the flow.** Agents may shape the `.claude` config; they never change the
  flow itself (the status model, the gates, the structural decisions).
- **Deterministic mechanics are scripted.** Agents make judgments; all work-item / code-host
  side-effects (status swaps, signed comments, PRs, links) go through bash scripts — enforced where
  it matters (e.g. a hook requires every ADO comment to be signed by its agent). Comments on code-host
  PRs are signed by the posting agent too, so a reviewer finding and a coder rebuttal stay
  distinguishable under one shared identity.

## Docs

- **[Getting started](https://dlw-digitalworkplace.github.io/ai-native-dev/getting-started.html)** —
  prerequisites, install/load, project setup, and how to run the flow.
- **[Reference](https://dlw-digitalworkplace.github.io/ai-native-dev/docs.html)** — every command,
  agent, and skill, plus all `aind.settings.json` / `aind.env` configuration options.
- **[Flow diagram](https://dlw-digitalworkplace.github.io/ai-native-dev/)** — an interactive visual
  of the whole pipeline.
- **[CHANGELOG.md](CHANGELOG.md)** — what changed in each released version.
- **`design-log/`** — the design record for maintainers: **every design decision and its rationale**
  lives here (the `D<N>-…` decision files), alongside `design-log/design-doc.md` (how the flow works)
  and `design-log/STATUS.md` (current build/validation status).
