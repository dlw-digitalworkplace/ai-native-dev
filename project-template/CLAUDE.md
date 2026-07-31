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

- **One status.** A work item carries exactly one AIND status. Only ever change it via the
  `aind-status` skill. Never edit the status by hand (on the ADO tracker that means never adding or
  removing the `AIND status - <state>` tag directly).
- **Sign every post.** Post work-item comments only via the `aind-comment` skill — it signs by agent
  name. On the ADO tracker, direct comment calls are blocked by a hook.
- **Plan location.** Plans live at `/plans/<work-item-id>/plan.md` and are permanent living
  documentation — never delete them after the code ships.
- **Reach branches through PRs.** Never construct or assume a branch name to find an artifact;
  resolve via the PR and the `AIND-LINKS` block. The work-item ID is the join value.
- **Don't author stories.** Intake suggests fixes; the human owns the story text.

### AIND configuration

Config lives in **two files** under `.claude/`, both auto-loaded (no manual `source` needed):

- **`.claude/aind.settings.json`** — shared, **checked in**. Source of truth for the work-item
  tracker (`tracker`: `ado` or `file`, + `trackerDir` for the file backend), ADO org/project (ADO
  tracker), code host + repo, integration branch, and the optional `worktree` / `telemetry` blocks.
  See `aind.settings.sample.json` for every key and its meaning.
- **`.claude/aind.env`** — secrets + per-user overrides, **gitignored**. Holds `AZURE_DEVOPS_EXT_PAT`
  (needed for the ADO tracker and/or the ADO code host) and optional `AIND_ACTOR`.

`/aind:onboard` (or `/aind:kickstart`) creates both and adds the gitignore line(s). For the **ADO
tracker** the only manual step is pasting your PAT into `.claude/aind.env`; the **file tracker** needs
no work-item PAT (create stories with `aind-tracker.sh new "<title>"` under `trackerDir`).

**Work-item tracker.** `tracker: "ado"` keeps stories in Azure DevOps Boards. `tracker: "file"` keeps
one **markdown file per work item** under `trackerDir` (default `.aind/items`, may be an absolute path
outside the repo) — for projects with no ADO backlog / code-only access. Each item is a machine-owned
front-matter block (`state`, `dependsOn`, `links`, telemetry) plus human-owned `## Description` /
`## Acceptance Criteria` / `## Comments` sections; AIND updates the metadata and appends comments but
never edits your prose.

**Optional features** (all off by default, all configured in `aind.settings.json` — see
GETTING-STARTED and the sample settings file for details):
- **Worktrees** (`worktree.enabled: true`) — work several stories in parallel from one clone.
- **Usage telemetry** (`telemetry.enabled: true`) — per-phase raw token/time recorded onto the work
  item (raw numbers only; pricing done offline).
- **Native-State mirror** (`stateMap`, **ADO tracker only**) — mirror AIND status onto the work
  item's built-in ADO State so the board follows the flow; filled by `/aind:map-states` (off = `{}`
  or absent). Not applicable to the file tracker (its `state` field *is* the status).
