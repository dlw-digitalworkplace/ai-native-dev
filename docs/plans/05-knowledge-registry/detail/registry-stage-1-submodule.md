# PR-05 — Wire the shared-skills submodule into onboarding and preflight

_Status: planned. Depends on WS-00 (the registry repo must exist). Realizes the D25 companion-
knowledge idea via the registry design (v2) instead of a second plugin. New D-entry required
(should note its relationship to D25: same goal, git-submodule delivery instead of a plugin)._

## Context
The registry design fixes consumption: `aind-knowledge` is a git submodule at
`.claude/skills/shared/` in every harness project; the host's native frontmatter scan discovers
shared skills; the pin is the submodule SHA. This PR teaches the harness to set that up and check
it — the flow itself needs no change to *consume* (progressive disclosure is native); the wiring
is onboarding + preflight + the Copilot-side scan rule.

## Keep it simple (non-goals)
- No install/update tooling. Updating the pin is `git submodule update --remote` + commit, done by
  a human (or proposed by the planner — PR-06, not here).
- The submodule is **optional**: a project without `AIND_KNOWLEDGE_REPO` configured behaves
  exactly as today. No hard dependency of the flow on the registry.
- **Worktree mode (D37/D39):** a fresh per-phase worktree does not initialize submodules by default,
  and `copyFiles`/`symlinkDirs` don't cover them — so a worktree needing `shared/` skills must run
  `git submodule update --init` at setup (in `aind-worktree.sh ensure`), else the pin is effectively
  absent for that worktree.

## Task breakdown
1. `project-template/aind.settings.sample.json` — add optional `knowledgeRepo` (URL), and extend the
   `aind-common.sh` settings→env loader to surface it as **`AIND_KNOWLEDGE_REPO`** (per D41 shared
   config lives in `aind.settings.json`, not `aind.env`). Keep in `project-template/CLAUDE.md` only
   the **operational** line for the Copilot host: when looking for capabilities, scan
   `.claude/skills/shared/**/SKILL.md` frontmatter (Claude Code needs nothing — native scan).
2. `commands/onboard.md` + `commands/kickstart.md` — a new late step: if the human provides the
   registry URL (ask once via `AskUserQuestion`; skippable), **write `knowledgeRepo` into
   `aind.settings.json`** (D41 ask-and-write, not a `.sample` copy), run
   `git submodule add <url> .claude/skills/shared` and report the pinned SHA. Evidence/decision-gated
   like everything else they do; never silently.
3. `scripts/aind-preflight.sh` — new probe rows: submodule present? initialized? reachable
   (fetch)? — `[OK]/[MANUAL]`, never `[FAIL]`-blocking (the registry is optional).
4. `GETTING-STARTED.md` — a short "shared skills" section: what the submodule is, how to update
   the pin, that skill bodies load on demand.
5. `design-log/` — D-entry: submodule-as-distribution (why not a plugin: D25's standards-plugin
   shape is superseded by the registry for org knowledge; plugins remain for *flow*), SHA-pin
   semantics, optionality.

## Assumptions & open questions
- Submodule path `.claude/skills/shared/` assumes the host scans nested skill dirs — verify on
  both hosts during live validation; fallback is a scan rule line on the Claude side too.
- Private-repo auth for the submodule on fresh clones (HTTPS + credential manager vs SSH):
  document, don't solve.

## Definition of done
- [ ] A project onboarded with the registry URL gets the submodule, pinned; skills from
      `shared/` are discoverable by description in a live session on **both hosts**.
- [ ] A project without the config is byte-identical to today; preflight reports the absence as
      `[MANUAL]` guidance, not failure.
- [ ] D-entry recorded (incl. the D25 relationship).

## Files affected
`project-template/aind.settings.sample.json`, `project-template/CLAUDE.md` (Copilot scan line only),
`scripts/aind-common.sh` (map `knowledgeRepo` → `AIND_KNOWLEDGE_REPO`), `commands/onboard.md`,
`commands/kickstart.md`, `scripts/aind-preflight.sh` (+ submodule-init in `aind-worktree.sh ensure`),
`GETTING-STARTED.md`, `design-log/`.
