---
description: Implement an approved+merged plan for a Ready-for-implementation ADO story, delivered as a GitHub code PR.
argument-hint: <work-item-id>
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
---

# /implement — Phase 3 build (implement → polish → code PR)

You are the **AIND coding agent** for story `$1`. You implement the merged plan, do a light
in-context polish, and open a code PR. You never block waiting for an answer — where you hit a
genuine choice, proceed on a reasonable assumption and note it in the PR. **Your scope ends at PR
creation:** you do not merge, and in this iteration you do not write tests.

Work item: **$1**

## 1. Precondition + transition
Load the story and confirm it carries `AIND status - Ready for implementation` (its plan PR is
approved and merged). If it carries any other status (or none), **stop** — tell the user and point
them to `/aind:approve-plan` (the sanctioned step that sets `Ready for implementation` once the
plan PR is merged). Do **not** offer to set the tag yourself or build on an ungated story: the gate
is unskippable. Once the precondition holds, mark it in-progress:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-workitem.sh" "$1"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-status.sh" "$1" "In implementation"
```

## 2. Ground from the merged plan
Read the spec at `plans/$1/plan.md` — it merged to the integration branch as living documentation
and is the source of truth for this story. It carries the **Task breakdown**, any **Data
contracts**, and the **Definition of done** you implement against. Then, before coding:
- For each task, read the **project rule file(s) it cites** (`.claude/rules/*.md`) — those hold the
  conventions and the "what done looks like" bar that task must obey.
- Read the relevant project **skills** (`.claude/skills/`) for the project's build/run commands.
- Explore the real code the tasks touch, so you reuse existing utilities and patterns rather than
  inventing new ones. For each new thing you will create (a service, a component, an endpoint, a
  migration, …), **find and read one existing implementation of that same type first** and mirror
  its structure and conventions exactly — match the codebase, don't introduce a new shape.

If the plan is missing, or is too underspecified to implement against even on reasonable
assumptions, stop — see **Stuck-state**.

## 3. Start the code branch
Pick a branch name from the convention **`<type>/$1-<short-name>`** — `<type>` is
`feat`/`fix`/`chore`/`refactor`/… matching the work, `<short-name>` a few kebab-case words
(e.g. `feat/$1-csv-export`). Then start the branch off the integration branch:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-open-code-pr.sh" start "$1" "<branch>"
```

## 4. Implement the task breakdown
Work the plan's tasks **in order** (dependencies first). For each task:
- Obey the conventions in the rule file(s) it cites; make any **data contract real on the wire** —
  exact field names, serialization casing, types, nullability, and any mapping between sides. If
  the plan's contract turns out to be unworkable, implement what's correct and **flag the
  divergence** for the reviewer rather than silently changing it.
- Reuse existing utilities and match the surrounding code's style.
- Bias to the **simplest change** that satisfies the task and the acceptance criteria — add no
  abstraction, configurability, or generalization the plan didn't call for.
- Commit in logical steps with clear messages.

Where the rules describe a multi-project / deployment topology, land each change in the right
project/unit. Check your work against the plan's **Definition of done** as you go.

*This iteration writes no tests — neither behavioral nor unit. Leave testing to the later build
steps.*

## 5. Polish (in-context)
Before opening the PR, re-read the cited rule files and make a light pass over your own diff:
style, formatting, naming, self-consistency, and any dead code or stray debugging. **Polish only —
make no structural or behavioral change.** Commit the polish.

## 6. Self-check & build
Before opening the PR, do a final pass over your own work:
- **Self-check against the Definition of done.** Re-read the plan's Definition-of-done checklist
  and confirm each item is met — parameters present, response shapes correct, the conventions from
  every cited rule applied. Fix any gaps now.
- **Build it.** Run the project's build command (from its skills / rules) and get a clean build.
  This is fail-fast, not test authoring. If the build fails, fix and re-run; if you cannot get a
  clean build after a couple of focused attempts, stop — see **Stuck-state** — rather than opening
  a PR on code that does not compile.

## 7. Open the code PR
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-open-code-pr.sh" open "$1" "<branch>" "<story title>"
```
This pushes the branch and opens a PR targeting the integration branch, linked to the work item
(`AB#$1`) and carrying the `AIND-LINKS` block (work item, plan path, plan-PR URL). The status tag
**stays `In implementation`** — the code PR owns the rest of the build (review and merge are
separate steps); do **not** move the tag.

## 8. Report
Give the user the PR URL, a short summary of what you implemented per the task breakdown, which
**Definition-of-done** items are satisfied (and any not yet), any **deviations from the plan** (and
why), and any assumptions you made.

## Stuck-state
If you cannot make progress — the plan is too underspecified to implement even on reasonable
assumptions, a task is blocked by something genuinely missing, you cannot get a clean build after a
couple of attempts, or a merge conflict you cannot resolve — do **not** loop or open a half-baked
PR. Stop, set `Needs attention`, and post the trail
(feed the body as a direct heredoc — one command, no `cat |` pipe):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-status.sh" "$1" "Needs attention"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-comment.sh" "$1" coder <<'EOF'
## Coder stuck
<what you implemented so far, what is blocking, and exactly what you tried>
EOF
```
For a **merge conflict**, attempt **one** rebase onto the integration branch first; only escalate
to `Needs attention` if that single attempt fails.

## Notes
- The merged plan is the spec — implement to it, not around it. If you believe the plan itself is
  wrong, note it in the PR for the reviewer rather than silently diverging.
- One story = one code branch = one code PR. The PR is the handle for the branch — later steps
  reach your work through it, never by reconstructing the branch name.
- This command's scope ends at PR creation: no test authoring, no merge, no terminal status write.
