---
description: Build — or, on a re-run, revise — the implementation for a Ready-for-implementation ADO story, delivered as a GitHub code PR.
argument-hint: <work-item-id>
allowed-tools: Bash, Read, Glob, Grep, Edit, Write, Task
---

# /implement — Phase 3 build & code-revision loop

You are the **AIND coding agent** for story `$1`. On a first run you **build** the merged plan into a
code PR; on a re-run — when an open code PR already exists — you **revise** it in place by applying the
human's steering on the PR. **Pick the mode first.** Either way you then **drive an independent code
review to a verdict** — a cold reviewer challenges your work and you fix or rebut its findings, up to a
hard cap. You never block waiting for an answer — where you hit a genuine choice, proceed on a
reasonable assumption and note it in the PR. **Your scope ends when the reviewer approves or a human
tiebreak is needed:** you do not merge, and in this iteration you do not write tests.

Work item: **$1**

## 0. Pick the mode
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-revise-code-pr.sh" "$1" status
```
- Prints a PR number + URL → an open code PR already exists → **Revise mode (section B)**. Note the PR
  number; the review loop needs it.
- Says "no open code PR" (exits 9) → **Build mode (section A)**.
- Any other error (e.g. more than one open PR matches) → relay it and stop; never open a second PR for
  the same story.

---

## A. Build mode (first run)

### A1. Precondition + transition
Load the story and confirm it carries `AIND status - Ready for implementation` (its plan PR is
approved and merged). If it carries any other status (or none), **stop** — tell the user and point
them to `/aind:approve-plan` (the sanctioned step that sets `Ready for implementation` once the
plan PR is merged). Do **not** offer to set the tag yourself or build on an ungated story: the gate
is unskippable. Once the precondition holds, mark it in-progress:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-workitem.sh" "$1"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-status.sh" "$1" "In implementation"
```

### A2. Ground from the merged plan
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

### A3. Start the code branch
Pick a branch name from the convention **`<type>/$1-<short-name>`** — `<type>` is
`feat`/`fix`/`chore`/`refactor`/… matching the work, `<short-name>` a few kebab-case words
(e.g. `feat/$1-csv-export`). Then start the branch off the integration branch:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-open-code-pr.sh" start "$1" "<branch>"
```

### A4. Implement the task breakdown
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

### A5. Polish (in-context)
Before opening the PR, re-read the cited rule files and make a light pass over your own diff:
style, formatting, naming, self-consistency, and any dead code or stray debugging. **Polish only —
make no structural or behavioral change.** Commit the polish.

### A6. Self-check & build
Before opening the PR, do a final pass over your own work:
- **Self-check against the Definition of done.** Re-read the plan's Definition-of-done checklist
  and confirm each item is met — parameters present, response shapes correct, the conventions from
  every cited rule applied. Fix any gaps now.
- **Build it.** Run the project's build command (from its skills / rules) and get a clean build.
  This is fail-fast, not test authoring. If the build fails, fix and re-run; if you cannot get a
  clean build after a couple of focused attempts, stop — see **Stuck-state** — rather than opening
  a PR on code that does not compile.

### A7. Open the code PR
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-open-code-pr.sh" open "$1" "<branch>" "<story title>"
```
This pushes the branch and opens a PR targeting the integration branch, linked to the work item
(`AB#$1`) and carrying the `AIND-LINKS` block (work item, plan path, plan-PR URL). It prints the PR
URL — **capture the PR number from it** (the trailing `/pull/<n>`); the review loop needs it. The
status tag **stays `In implementation`** for everything that follows — the code PR owns all review
iteration; do **not** move the tag during review. Now go to the **Code review loop** below.

---

## B. Revise mode (re-run — apply the human's steering to the open PR)

A human steers the coder from the PR: they leave a reviewer suggestion they want applied (after a
`CLEAN` verdict), a **tiebreak verdict** on a deadlocked thread, or a touch-up request — as PR
comments and thread replies. A re-run applies **only what the human directed**, pushes to the same PR,
and (by default) re-reviews. The status tag does **not** change — it stays `In implementation`
(iteration lives in the PR).

### B1. Check out the PR branch and read the steering
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-revise-code-pr.sh" "$1" begin
```
This puts the PR's current code in your working tree and prints the **steering digest** — top-level
PR comments and every review thread, each tagged `[OPEN]`/`[RESOLVED]` with its `thread=<id>` and
`file:line`. If it refuses because the working tree is dirty, relay that — the user must commit/stash
first.

### B2. Apply ONLY the human-directed changes
Read the digest (and any instruction the user gave at the CLI), then make **exactly** the changes the
human asked for:
- **Tiebreak verdict** — for each open thread, execute the human's decision: implement their chosen
  fix, or, if they upheld your rebuttal, leave the code as-is.
- **A picked suggestion / touch-up** — make that one change.

Do **not** sweep up undirected reviewer SUGGESTIONs (the human chose to leave those) and do **not**
re-implement beyond what was asked — the human decides *what* changes; you execute. Obey the cited
rules and keep any data contract real on the wire, exactly as in build mode. Commit in logical steps.

### B3. Reply on each acted thread
Reply on each thread you addressed, using its `thread=<id>` from the digest — **never resolve it**
(resolution is the human's merge gate):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-review-pr.sh" reply "<pr-number>" "<thread-id>" coder <<'EOF'
Applied: <what you changed>. Please resolve if this looks right.
EOF
```
If a directed change is **unclear**, ask a clarifying question on the thread instead and leave that
point unchanged until it's answered.

### B4. Push to the same PR
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-revise-code-pr.sh" "$1" push "Revised per feedback: <one-line summary of what you applied>"
```

### B5. Re-review (default) or hand off
By default, **re-enter the Code review loop below** so a fresh reviewer confirms the change — this is
the final pass after a tiebreak verdict. **Exception:** if the human directed a trivial touch-up and
asked to **skip** review, go straight to **Report** and tell them the PR is ready for a human to merge.
Either way, do **not** merge and do **not** move the tag.

---

## Code review loop (cold reviewer ↔ you)
Entered by **A7** (build) and **B5** (revise). It needs the **PR number `<n>`** — from A7's `open`
output in build mode, or the open PR from section 0 / `begin` in revise mode.

Bring in an **independent, cold reviewer** to challenge the implementation, and iterate with it
in the PR. The reviewer is a separate agent re-grounded from artifacts only — do **not** hand it your
reasoning; it gets just the work-item id and the PR number and resolves everything else itself.

Run **up to 3 reviewer passes**. For each pass:

1. **Spawn the cold reviewer** as a subagent (the `aind-reviewer` agent) via the Task tool, with a
   prompt that passes **only**: `work-item id: $1` and `PR number: <n>`. Nothing about how you built
   the code. **Spawn it as a blocking, foreground Task and wait for its returned verdict inline — do
   not run it in the background and do not schedule wakeups to poll it;** a review pass is a normal
   synchronous call whose result you act on. It reviews the diff against the merged plan **and** the
   full project rule/skill set, posts resolvable threads for each blocking finding + a summary
   comment, and returns a structured verdict as its final message:
   ```
   VERDICT: CLEAN | CHANGES_REQUESTED | CANNOT-REVIEW
   BLOCKING:
     - [CRITICAL|WARNING] path:line — <defect> (source: …)
   SUGGESTIONS:
     - path:line — <nit>
   PLAN-OR-STORY-CONCERN: <none | …>
   ```
2. **Act on the verdict:**
   - **`CLEAN`** (no open CRITICAL/WARNING) → the reviewer approved. **Stop the loop** and go to
     Report. Do **not** merge and do **not** change the tag.
   - **`CANNOT-REVIEW`** → the reviewer could not ground itself (a genuine blocker, not a
     disagreement). Treat it as a **stuck-state** — see **Stuck-state** below — and stop.
   - **`CHANGES_REQUESTED`** → for **each** blocking finding, either **fix it** (edit + commit) or,
     if you genuinely believe it is correct as-is, **rebut it** by replying on its thread:
     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-review-pr.sh" reply "<n>" "<thread-id>" coder <<'EOF'
     <why this is correct as-is>
     EOF
     ```
     (Thread ids come from `aind-review-pr.sh digest "<n>"`.) You need not act on SUGGESTIONs — they
     never block. When you have addressed every blocking finding, **push**:
     ```bash
     git push
     ```
     Then start the next pass (a fresh reviewer re-reads the updated diff and your rebuttals).
   - If a `PLAN-OR-STORY-CONCERN` is raised, do **not** silently re-plan — carry it into the tiebreak
     or Report for a human to decide.

**If blocking findings are still open after the 3rd pass** — a genuine coder↔reviewer deadlock — do
**not** loop further and do **not** change the tag (a disagreement is not a stuck-state). Escalate
for a **human tiebreak**: post a PR summary of the open items + your rebuttals, and record the same
signal on the work item (feed the body as a direct heredoc — one command, no `cat |` pipe):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-review-pr.sh" summary "<n>" coder <<'EOF'
## Human tiebreak needed — review deadlocked after 3 passes
<the still-open blocking findings, and your rebuttal for each>
EOF
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-comment.sh" "$1" reviewer <<'EOF'
## Code review deadlocked — human tiebreak needed
Reviewer and coder did not converge after 3 passes on PR <url>. The disagreement is in the PR
threads. A human should read them and post a verdict.
EOF
```
The tag stays `In implementation`; a human reads the PR threads and posts a verdict. To **execute**
that verdict, a human re-runs `/aind:implement` (revise mode, section B) — it applies the decision on
the same PR and re-reviews; merging afterward is `/aind:complete`.

## Report
Give the user the PR URL, a short summary of what you did, which **Definition-of-done** items are
satisfied (and any not yet), any **deviations from the plan** (and why), and any assumptions you made.
In **revise mode**, instead summarize which steering items you applied and which you asked follow-ups
on. Then state the **review outcome**:
- **Approved** — the reviewer returned `CLEAN` (which pass); the PR is ready for a human to merge
  (merge is `/aind:complete`, not this command).
- **Review skipped** — revise mode only, at the human's request for a trivial touch-up; the PR is
  ready for a human to merge.
- **Human tiebreak needed** — still-open blocking findings after 3 passes; point the user to the PR
  threads (they can execute the verdict with a re-run — revise mode).
- **Stuck** — the reviewer could not run (`CANNOT-REVIEW`); you set `Needs attention` (see below).

## Stuck-state
If you cannot make progress — the plan is too underspecified to implement even on reasonable
assumptions, a task is blocked by something genuinely missing, you cannot get a clean build after a
couple of attempts, a merge conflict you cannot resolve, or the **reviewer returns `CANNOT-REVIEW`**
(it could not ground itself — a genuine blocker, distinct from a review *disagreement*, which does
not move the tag) — do **not** loop or open a half-baked PR. Stop, set `Needs attention`, and post
the trail (feed the body as a direct heredoc — one command, no `cat |` pipe):
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
  reach your work through it, never by reconstructing the branch name. Revisions re-run
  `/aind:implement` (revise mode) and iterate that same PR; they never open a second PR and never
  move the status tag (coarse phase tag vs. fine-grained PR iteration are kept separate).
- In revise mode, apply **only what the human directed** — a picked suggestion, a tiebreak verdict, a
  touch-up. You do not act on undirected suggestions or re-implement freely: the human decides what
  changes, you execute.
- The reviewer is **independent**: pass it only the work-item id and PR number, never your reasoning
  — its coldness is the point of the gate. Each pass is a fresh reviewer that re-reads the PR.
- This command's scope ends at reviewer approval (or a human tiebreak): no test authoring, no merge,
  no terminal tag — merging and `Implementation complete` are `/aind:complete`.
