# D48 — Pre-story research command (`/aind:research`)

- **Area:** Pre-flow research (a thinking aid before intake; config/packaging side of the D1–D15 line; relates to D18, D31, D46)
- **Date:** 2026-08-04
- **Status:** Active

## Decision
Add an **optional, pre-flow** command **`/aind:research "<topic>"`** that researches technical
approaches **before a user story exists** and records the findings as a **markdown file** the human
reviews. It is a **warm, in-session slash command** (per D20 — it authors an artifact a human
reviews, so it is a command, not a cold `agents/` subagent), and it is **purely additive to the
flow**: it introduces **no** AIND status, **no** gate, and touches **no** work-item tracker, code
host, or telemetry. The status model, gates, and PR contract are untouched.

The command:
- **Grounds in the codebase first** (read-only: rules/skills + real source + manifests/lockfiles for
  the pinned toolchain) so the project's actual stack, conventions, and constraints *steer* the
  research and rule options in or out. The command itself stays **technology/project-agnostic** —
  the grounding is discovered per run, nothing is hardcoded.
- **Uses web search** (`WebSearch`/`WebFetch` — net-new tools for this plugin) to act on the *latest*
  reality (current package versions, official docs, maintenance status, alternatives), citing every
  source URL with the date checked; if web tools are unavailable it marks currency claims unverified
  rather than inventing them.
- **Documents everything**: options explored, **discarded paths with the explicit reason**,
  trade-offs, risks/unknowns, open questions, a recommendation, and a References section — all links
  preserved.
- **Asks clarifying questions** (`AskUserQuestion`, batched explicit either/ors — the D44 sparring
  pattern) for ambiguities, contradictions with the codebase, or scope gaps, *before* going deep so
  answers steer the research.

**Output location** is configurable via a new `research.dir` key in `.claude/aind.settings.json`
(mapped to `AIND_RESEARCH_DIR` by `aind-common.sh`), **default `.aind/research`**, always markdown,
one file per topic (`<YYYY-MM-DD>-<slug>.md`). The default in-repo dir is **gitignored** (local
scratch, like `.aind/usage/`); onboarding/kickstart append the line when the default is used. The
directory is resolved off the **main checkout** (`git --git-common-dir`), so it is worktree-safe.

Scope-wise it **suggests, never asserts**: the findings are a DRAFT the human owns; the command
recommends an approach and points at story authoring (`/aind:new-item` or the tracker) as the next
step, but never creates a story or starts the flow.

New artifacts: `commands/research.md`, `scripts/aind-research.sh` (`dir` / `path` verbs — the only
deterministic mechanics, keeping the command thin). No new script beyond path resolution.

## Rationale
The flow's earliest phase was **intake**, which scores a story that *already exists* — there was no
step that helps a developer decide *what* to build or *how* to approach it before the story is
written. Teams did that research ad hoc, ungrounded, and undocumented. Seating it as an optional
pre-flow aid (the same slot as onboarding/kickstart, which are likewise not flow nodes) captures the
exploration as durable, linked documentation that feeds better stories — without adding a gate or
otherwise touching the flow.

Warm was the right packaging: like intake/plan/coder, this authors an artifact a human reviews, so
there is nothing to stay independent *from* (the D19→D20 rule — coldness is reserved for the
independent checks). Web search is essential because approach research rests on *current* versions
and docs, which stale model memory gets wrong. Grounding-in-the-codebase is what keeps the research
relevant (no researching an Angular approach for a React app) while leaving the plugin stack-agnostic.
Gitignoring the default output matches how other `.aind/` scratch areas are treated and keeps
research churn out of the repo history; a config key lets a team redirect (or commit) it if they
prefer. This is a config/packaging-side addition on the same side of the D1–D15 line as onboarding.
