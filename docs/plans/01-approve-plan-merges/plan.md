# PR-01 — /approve-plan approves and merges the plan PR

_Status: planned (re-based 2026-07-28 onto v0.18.0 / D42). Supersedes part of the current
`/approve-plan` design (and the D27-mirrored "verify-then-tag, never command-merges" shape **for
the plan PR only**). New design-log entry required (D43+)._

## Context
Today `/approve-plan` is a recorder: the human must approve + merge the plan PR in the GitHub UI,
then run the command, which only verifies the merge and writes `Ready for implementation`. That is
double work and a drift window (repo says merged, ADO still says review). Decision: the command IS
the approval. The dev's decision is the invocation; the deterministic side-effects (merge + state)
are scripted and atomic — consistent with "what can be scripted should be scripted."

## Keep it simple (non-goals)
- `/aind:complete` is NOT changed. The code-PR merge stays a human act in the UI (the review
  happened *on* that PR; merging it there is natural). Only the plan PR — whose review happened in
  the sparring session and whose threads are the gate — gets command-merge.
- No merge-method configuration surface. Use the code host's default merge method (through the
  forge adapter, below); branch-protection / branch-policy conflicts surface as the command refusing
  with the host's error.
- No auto-run of `/implement` afterward.

## Implementation approach
Invert the gate: instead of "refuse until merged," the command becomes "refuse to merge until every
thread is resolved, then merge."

## Task breakdown
1. **Forge verbs first** (`scripts/aind-forge.sh`): D36 built the code-host adapter but it exposes
   **no approve/merge verb**, so add `forge_pr_approve` and `forge_pr_merge`, each dispatching on
   `AIND_CODE_HOST` to a `_gh_*` impl (`gh pr review --approve`; `gh pr merge`, repo default method)
   and an `_ado_*` impl (`az repos pr set-vote --vote approve`; `az repos pr update --status
   completed`, the ADO complete-with-merge path). This keeps the merge path host-agnostic. Then in
   `scripts/aind-revise-plan-pr.sh` (already forge-based) add a `merge` phase: resolve the open plan
   PR for `<id>`; list review threads via the existing forge digest plumbing; **refuse (exit
   non-zero, name the open threads) if any thread is `[OPEN]`**; else print the plan's diffstat +
   resolved-thread count and require one explicit human confirm; then `forge_pr_approve` — **this is
   what preserves the audit trail**: the host-native approval record lands under the invoker's
   identity (skip gracefully where the host rejects self-approval) — and `forge_pr_merge`, printing
   the merge SHA. Reuse the forge verbs + `aind_find_*` helpers; add no host-specific calls.
2. `commands/approve-plan.md` — rewrite the procedure, **layering onto its current D40 shape** (it
   already starts by returning to the main checkout via `aind-worktree.sh main-root` in worktree
   mode, and its `cleanup` phase retires the plan worktree + fast-forwards integration): (1) run
   `merge` (relay a refusal verbatim — resolving threads stays the human's job), (2) on success
   `aind-status.sh "Ready for implementation"`, (3) the existing worktree-aware `cleanup` phase
   unchanged. Keep the Notes about ratifying the test strategy and AC coverage; keep the
   story-level-problem reroute path.
3. `scripts/aind-preflight.sh` + `GETTING-STARTED.md` — branch protection is a **named
   prerequisite** (the D5 pattern): document the plan-branch settings command-merge requires
   (thread resolution; any required checks/reviewers must be compatible with approve-then-merge
   under the invoker's identity), and probe what is probeable. "Works on some repos, mysteriously
   fails on others" is prevented by contract, not by defensive merge logic.
4. `design-log/` — new D-entry: what changed, why (drift window + double work), and explicitly
   why the plan PR gets command-merge while the code PR (D27) does not: the plan gate is
   *thread resolution* (machine-checkable), the code gate is *human acceptance of the work*
   (not machine-checkable), so verify-then-tag remains correct there. Record the audit-trail
   property (approve-then-merge keeps the host-native record) and the failure-kind argument:
   merge-first-then-tag leaves a loud, transient, re-runnable state — what this PR eliminates is
   the *silent, indefinite* drift of merged-in-UI-but-command-never-run.
5. `design-doc.md` / `docs/index.html` — update the phase-2 close-out description.

## Assumptions & open questions
- Merge method: host default via `forge_pr_merge` with no flags, **or** always squash for plan
  PRs (one plan = one commit on integration)? Recommend host default; squash is a project policy
  (and must map across both `gh` and `az repos`).
- Multi-approver repos (approval required from someone other than the invoker): out of v0 scope —
  the plan reviewer *is* the dev who sparred; revisit when automation/service identity reopens Q7.

## Definition of done
- [ ] `merge` phase refuses with the open-thread list when any thread is unresolved.
- [ ] Happy path: one command run → PR merged → status `Ready for implementation` → branch cleaned.
- [ ] A failed status write after a successful merge leaves a re-runnable state (merge-first
      ordering preserved; re-run converges).
- [ ] D-entry recorded; design-doc + diagram updated.

## Files affected
`commands/approve-plan.md`, `scripts/aind-forge.sh` (new `forge_pr_approve` / `forge_pr_merge`
verbs), `scripts/aind-revise-plan-pr.sh`, `scripts/aind-common.sh` (maybe), `design-log/`,
`design-doc.md`, `docs/index.html`.
