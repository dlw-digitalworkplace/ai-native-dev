# <Project> — AIND project rules

> Copy this file to `.claude/CLAUDE.md` in your project and fill in the blanks.
> It layers on top of the installed **aind** plugin (commands, agents, skills, hooks).

## AIND configuration

The AIND scripts read these from the environment. Set them before running AIND commands —
e.g. `source .claude/aind.env` (copy `aind.env.sample`, keep the PAT out of git):

| Variable | Value for this project |
|---|---|
| `AIND_ADO_ORG` | `https://dev.azure.com/<your-ado-org>` |
| `AIND_ADO_PROJECT` | `<your-ado-project>` |
| `AIND_CODE_HOST` | `github` (default) \| `ado` — where code + PRs live |
| `AIND_GH_REPO` | `<owner>/<repo>` (when `AIND_CODE_HOST=github`) |
| `AIND_ADO_REPO` | `<your-ado-repo>` (when `AIND_CODE_HOST=ado`) |
| `AIND_INTEGRATION_BRANCH` | `<main \| develop \| …>` |
| `AIND_PLAN_BRANCH_PREFIX` | `aind/plan/` (optional override) |
| `AIND_LESSONS_BRANCH` | `aind/lessons` (optional override; dreaming-phase exhaust branch) |
| `AZURE_DEVOPS_EXT_PAT` | *(a PAT with Work Items r/w + Code r/w — never commit)* |

## AIND operational rules (apply to every agent run here)

- **One status tag.** A work item carries exactly one `AIND status - <state>` tag. Only ever
  change it via the `aind-status` skill (atomic swap). Never add/remove status tags by hand.
- **Sign every post.** Post ADO comments only via the `aind-comment` skill — it signs by agent
  name. Direct comment calls are blocked by a hook.
- **Plan location.** Plans live at `/plans/<work-item-id>/plan.md` and are permanent living
  documentation — never delete them after the code ships.
- **Reach branches through PRs.** Never construct or assume a branch name to find an artifact;
  resolve via the PR and the `AIND-LINKS` block. The work-item ID is the join value.
- **Don't author stories.** Intake suggests fixes; the human owns the story text.

## Parallel work with worktrees (optional)

To work several stories at once from one clone (e.g. implement one while planning the next), opt into
git worktrees: copy `aind-worktree.config.sample.json` to `.claude/aind-worktree.config.json`. Its
presence turns the feature on; deleting it turns everything back to single-tree behaviour.

```json
{ "worktreeRoot": ".claude/worktrees",
  "copyFiles": [".claude/aind.env", ".claude/settings.local.json"],
  "symlinkDirs": ["node_modules"] }
```

- `worktreeRoot` — where per-phase worktrees are created (default `.claude/worktrees`, repo-relative).
  **Add it to `.gitignore`** (e.g. `.claude/worktrees/`).
- `copyFiles` — gitignored files **or folders** a fresh worktree would lack, copied in at creation:
  e.g. `aind.env` (config), `settings.local.json` (permission allowlist), a runtime file like `.env`,
  or a whole folder like `.vscode/` or `certs/`. Each entry is a repo-relative path (a file is copied,
  a directory is copied recursively) and is removed again before the worktree is torn down.
- `symlinkDirs` (optional) — heavyweight gitignored **directories** a worktree should **share** with
  the main checkout rather than re-populate (chiefly `node_modules`; also `.next/cache`, a Python
  `.venv`, build caches). Each is *linked* into the worktree at creation — a directory **junction** on
  Windows (no admin needed) or a symlink on macOS/Linux — so one install serves every worktree. Omit
  it or leave it `[]` to share nothing.

**Front-end note (`node_modules`).** Sharing is a real convenience but it's genuinely *shared* state:
a branch that adds/changes a dependency must run an install (which updates the one shared store), and
a `npm install` running in one worktree can disturb a build in another. If you need true per-branch
dependency isolation, prefer **pnpm** — its global content-addressable store makes each worktree's
own `pnpm install` near-instant and hardlinked, with no shared-state hazard and nothing to configure
here. Use `symlinkDirs` when pnpm isn't an option (npm/yarn projects) and the shared trade-off is
acceptable.

Run it: launch each session in the **main checkout** (it stays on the integration branch).
`/aind:plan` and `/aind:implement` create and drive a worktree per story; `/aind:approve-plan` and
`/aind:complete` retire it — **run those close-out commands from the main checkout**, not from inside
a worktree (a session can't remove its own working directory). Parallelism comes from opening more
than one terminal in the main checkout, each driving a different story.

## Project rules

<!-- One @import per rule file in .claude/rules/. There is NO fixed list of domains —
     import exactly the rule files that fit THIS codebase. /aind:onboard generates them from
     the code across three lenses: technical layers present, cross-cutting concerns with a
     notable approach (e.g. a custom auth scheme), and functional/domain architecture. See
     rules/_TEMPLATE.md. Evidence-only: no test framework -> no testing rule, etc.

     The lines below are PLACEHOLDERS — replace them with your real rule files: -->

@rules/<area-1>.md
@rules/<area-2>.md

<!-- Add project-specific guidance below: build/run/test commands, branch naming strategy,
     architecture notes, etc. Project-specific *skills* (how to run the app) go in
     .claude/skills/. -->
