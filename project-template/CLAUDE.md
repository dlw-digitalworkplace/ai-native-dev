# <Project>

> Project guidance for AI agents in this repo, loaded automatically by the **aind** plugin. Keep
> this file about the *project*; the AIND workflow config sits below as a compact operational layer.

## Project context

<!-- 2–5 sentences: what this repo is, its main surfaces/layers (e.g. .NET Azure Functions backend
     + React/Vite admin portal), the domain in one line, and where the docs live.
     /aind:onboard fills this in from the codebase. -->

## Project rules

<!-- One @import per rule file in .claude/rules/. There is NO fixed list of domains — import exactly
     the rule files that fit THIS codebase, across three lenses: technical layers present;
     cross-cutting concerns with a notable approach (auth, docs conventions, …); functional/domain
     architecture. See rules/_TEMPLATE.md. Evidence-only: no test framework -> no testing rule.
     Replace the placeholders below with your real rule files. -->

@rules/<area-1>.md
@rules/<area-2>.md

## Project-specific guidance

<!-- Anything agents must respect that isn't a full rule file: build/run/test entrypoints (the
     actual commands live as project *skills* in .claude/skills/), branch naming, key gotchas. -->

---

## AIND workflow layer

The sections below configure the **aind** plugin — operational scaffolding. Keep them, but the
project content above is the primary guidance.

### AIND operational rules (apply to every agent run here)

- **One status tag.** A work item carries exactly one `AIND status - <state>` tag. Only ever
  change it via the `aind-status` skill (atomic swap). Never add/remove status tags by hand.
- **Sign every post.** Post ADO comments only via the `aind-comment` skill — it signs by agent
  name. Direct comment calls are blocked by a hook.
- **Plan location.** Plans live at `/plans/<work-item-id>/plan.md` and are permanent living
  documentation — never delete them after the code ships.
- **Reach branches through PRs.** Never construct or assume a branch name to find an artifact;
  resolve via the PR and the `AIND-LINKS` block. The work-item ID is the join value.
- **Don't author stories.** Intake suggests fixes; the human owns the story text.

### AIND configuration

Config lives in **two files** under `.claude/`, both auto-loaded (no manual `source` needed):

- **`.claude/aind.settings.json`** — shared, **checked in**. Source of truth for ADO org/project,
  code host + repo, integration branch, and the optional `worktree` / `telemetry` blocks. See
  `aind.settings.sample.json` for every key and its meaning.
- **`.claude/aind.env`** — secrets + per-user overrides, **gitignored**. Holds `AZURE_DEVOPS_EXT_PAT`
  (Work Items r/w + Code r/w) and optional `AIND_ACTOR`.

`/aind:onboard` (or `/aind:kickstart`) creates both and adds the gitignore line; the only manual step
is pasting your PAT into `.claude/aind.env`.

**Optional features** (all off by default, all configured in `aind.settings.json` — see
GETTING-STARTED and the sample settings file for details):
- **Worktrees** (`worktree.enabled: true`) — work several stories in parallel from one clone.
- **Usage telemetry** (`telemetry.enabled: true`) — per-phase raw token/time recorded onto the ADO
  work item (raw numbers only; pricing done offline).
- **Native-State mirror** (`stateMap`) — mirror AIND status onto the work item's built-in ADO State
  so the board follows the flow; filled by `/aind:map-states` (off = `{}` or absent).
