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
tiebreak is needed:** you do not merge (that is `/aind:complete`).

Work item: **$1**

> **Worktrees (parallel work).** If this project opts into worktrees (check with
> `bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-worktree.sh" enabled` — on when
> `.claude/aind.settings.json` sets `worktree.enabled: true`), the implement phase runs in its
> own git worktree so other items proceed in parallel. The build commands print the worktree path
> (`aind: worktree <path>` from `start`; a `worktree <path>` note from `begin`), and **that directory
> is your project root for this story**:
> - Run **every** shell command with `cd "<worktree>"` first (build, test, lint, git, all of it). It
>   is fine for this shell to remain inside the worktree for the rest of the phase — the close-out
>   commands (`/aind:approve-plan`, `/aind:complete`) return the session to the main checkout on their
>   own before they tear a worktree down.
> - Read/Edit/Write/Grep/Glob using **`<worktree>`-rooted absolute paths** — never bare relative
>   paths (those would hit the main checkout, the wrong tree).
> - When you spawn the reviewer, pass it the worktree path too, so it reviews the right tree.
>
> **Guard:** the main checkout must stay clean. If at any point `git -C "<main-repo>" status
> --porcelain` shows changes you didn't intend there, you edited the wrong tree — stop and move the
> work into the worktree. (Commits/pushes go through the worktree, so a stray main-tree edit would be
> silently *missing* from the PR — catch it early.) If worktrees are **not** enabled, ignore this box
> and work in the main checkout as before.

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
contracts**, the **Testing recommendations** (the test strategy — whether to test, at what altitude,
and the must-cover list with each case's expected outcome), and the **Definition of done** you
implement against. Then, before coding:
- For each task, read the **project rule file(s) it cites** (`.claude/rules/*.md`) — those hold the
  conventions and the "what done looks like" bar that task must obey.
- Read the relevant project **skills** (`.claude/skills/`) for the project's build/test/run commands.
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
In worktree mode this prints `aind: worktree <path>` — **capture that path; it is your project root
for everything below** (see the Worktrees box: `cd` there in every shell, use its absolute paths).

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

**Author the tests the plan's test strategy calls for.** If the plan recommended tests, write them
in-context at the stated altitude, covering **every must-cover case** with an assertion tied to that
case's **expected outcome from the plan** — never to whatever the code currently happens to return.
A test-first rhythm works well where it fits: write the test for a must-cover case, watch it fail,
implement, watch it pass. Do **not** pad the suite with tautological or framework-testing tests to
inflate the count — the cold reviewer judges the tests' coverage *and* fidelity against the plan, and
a green test that asserts the wrong thing is a blocking finding. If the plan recommended **no** tests
(the project has no test practice), write none and do not bootstrap a framework.

### A5. Polish (in-context)
Before opening the PR, re-read the cited rule files and make a light pass over your own diff:
style, formatting, naming, self-consistency, and any dead code or stray debugging. **Polish only —
make no structural or behavioral change.** Commit the polish.

### A6. Self-check & build
Before opening the PR, do a final pass over your own work:
- **Self-check against the Definition of done.** Re-read the plan's Definition-of-done checklist
  and confirm each item is met — parameters present, response shapes correct, the conventions from
  every cited rule applied, and (where the strategy called for tests) a test for every must-cover
  case. Fix any gaps now.
- **Build it and run the tests.** Run the project's build command (from its skills / rules) and get
  a clean build; then, where you authored tests, run the project's test command and get the suite
  **green**. If the build or a test fails, fix and re-run; if you cannot get a clean build and
  passing tests after a couple of focused attempts, stop — see **Stuck-state** — rather than opening
  a PR on code that does not compile or whose tests fail. (Fixing a failing test means correcting the
  *code* or a genuinely wrong test — never weakening an assertion to make a real failure disappear.)

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
first. **In worktree mode** it works in the item's implement worktree and prints its path (`… —
worktree <path>`) — treat that as your project root (see the Worktrees box).

### B2. Apply ONLY the human-directed changes
Read the digest (and any instruction the user gave at the CLI), then make **exactly** the changes the
human asked for:
- **Tiebreak verdict** — for each open thread, execute the human's decision: implement their chosen
  fix, or, if they upheld your rebuttal, leave the code as-is.
- **A picked suggestion / touch-up** — make that one change.

Do **not** sweep up undirected reviewer SUGGESTIONs (the human chose to leave those) and do **not**
re-implement beyond what was asked — the human decides *what* changes; you execute. Obey the cited
rules and keep any data contract real on the wire, exactly as in build mode. Commit in logical steps.

### B3. Reply on each acted thread — and record scope-changing deviations
Reply on each thread you addressed, using its `thread=<id>` from the digest — **never resolve it**
(resolution is the human's merge gate):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-review-pr.sh" reply "<pr-number>" "<thread-id>" coder <<'EOF'
Applied: <what you changed>. Please resolve if this looks right.
EOF
```
If a directed change is **unclear**, ask a clarifying question on the thread instead and leave that
point unchanged until it's answered.

**If a directed change adds to or diverges from the merged plan** — new scope the plan didn't call
for (e.g. a test/E2E suite the human asked for on the PR), a removed item, or a changed contract —
**record it as a directed deviation** so the cold reviewer treats it as authoritative and does not
flag it as scope creep. A fix *within* the plan needs no deviation; only record real divergences:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-revise-code-pr.sh" "$1" deviation "<pr-number>" "<thread=id-from-digest>" "<what changed, one line>"
```
Cite the **`thread=<id>`** the instruction came from (preferred — the reviewer verifies it in the
digest); if the human directed it in a top-level PR comment with no thread, cite a short reference to
that comment instead. Do **not** record undirected changes as deviations — a deviation must trace to
something the human actually asked for.

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
   prompt that passes **only**: `work-item id: $1` and `PR number: <n>` (and, in worktree mode, the
   `worktree path` so any full-file reads reflect the branch under review — it still reviews the diff,
   not your reasoning). Nothing about how you built the code. **Spawn it as a blocking, foreground Task and wait for its returned verdict inline — do
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
     never block. When you have addressed every ordinary (code) blocking finding, **push** (no rebase,
     so a plain push fast-forwards):
     ```bash
     git push
     ```

     **Merge-conflict finding (`merge:integration`) — handle it LAST, after the push above.** If the
     reviewer's `BLOCKING` list contains a `merge:integration` finding, the PR no longer merges cleanly
     into the integration branch — another PR merged under yours (common in parallel work). Resolve it
     by **rebasing onto integration**, not by editing a file. **Push your code fixes first** (the step
     above): the rebase re-syncs the branch from the remote, so any unpushed local commits would be
     lost. Then rebase:
     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-revise-code-pr.sh" "$1" rebase
     ```
     On a **clean** rebase you are done — go straight to the force-with-lease push below. On a
     **conflict** it lists the conflicted files and leaves the tree mid-rebase; resolve each conflict
     in-context (preserve both the integration change and your change), then finish the rebase:
     ```bash
     git add <resolved files>
     git rebase --continue
     ```
     A rebase rewrites history, so its push must be a **force-with-lease** (a plain `git push` would be
     rejected as non-fast-forward):
     ```bash
     git push --force-with-lease
     ```
     (In worktree mode, run every command here in the item's implement worktree, like all the others.)

     Once every blocking finding is addressed and pushed, start the next pass (a fresh reviewer
     re-reads the updated diff, re-checks mergeability, and reads your rebuttals).
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

## Emit lessons (dreaming phase)
Before reporting, record what this run taught — the raw signal the cold dreamer later synthesises.
**Emit concrete lessons only; skip if there is genuinely nothing reusable.** Each is one command with
the Observation on stdin: state **what happened and why** (the cause), never a proposed fix.

- **Coder self-report** (`observation`) — a recurring friction building to the plan: a skill or build
  command that was wrong/missing, a rule that conflicted with the codebase, a pattern the plan
  assumed that didn't exist:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-emit-lesson.sh" "$1" coder observation self-report "<.claude/… if known>" <<'EOF'
  <what happened + why>
  EOF
  ```
- **On the reviewer's behalf** (`observation`) — the cold reviewer never writes, so if the review
  exposed a reusable signal (a class of finding that recurred, a rule/skill gap it kept citing),
  emit it as agent `reviewer`, sourced to the PR:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-emit-lesson.sh" "$1" reviewer observation "<pr-url>" "<.claude/…>" <<'EOF'
  <the recurring finding + why it recurs>
  EOF
  ```
- **Human steering (revise mode)** — the highest-value signal: when a human corrected you (a tiebreak
  verdict, a rejected approach, a directed change), emit a `correction` (or `suggestion` for an
  accepted nice-to-have), sourced to the thread/comment:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-emit-lesson.sh" "$1" coder correction "<pr-thread-url>" "<.claude/…>" <<'EOF'
  <what the human decided and why — the call you'd want captured for next time>
  EOF
  ```

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
assumptions, a task is blocked by something genuinely missing, you cannot get a clean build or the
tests passing after a couple of attempts, a merge conflict you cannot resolve, or the **reviewer
returns `CANNOT-REVIEW`**
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
For a **merge conflict** (a reviewer `merge:integration` finding, or one you hit directly), attempt
**one** rebase onto the integration branch first — `aind-revise-code-pr.sh "$1" rebase`, resolve,
`git rebase --continue`, then `git push --force-with-lease` — and re-review. Only escalate to
`Needs attention` if that single attempt genuinely can't be resolved.

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
- This command's scope ends at reviewer approval (or a human tiebreak): no merge, no terminal tag —
  merging and `Implementation complete` are `/aind:complete`. (You author the tests the plan called
  for; you do not merge.)
