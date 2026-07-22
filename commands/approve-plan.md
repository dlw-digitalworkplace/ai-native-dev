---
description: Mark an approved+merged plan as Ready for implementation (AIND Phase 2 close-out).
argument-hint: <work-item-id>
allowed-tools: Bash
---

# /approve-plan — Phase 2 close-out

Human-run helper for after you have **approved and merged** the plan PR for story `$1` in
GitHub. Approval is a human act; this only records the resulting status transition.

Work item: **$1**

## Procedure

**First — in worktree mode, return this session to the main checkout.** A prior `/aind:plan` run may
have left this shell's working directory inside the item's plan worktree. Close-out must run from the
main checkout: a session cannot remove its own worktree, and the branch cleanup + integration
fast-forward must act on the main tree. If worktrees are enabled, `cd` there before anything else (a
no-op when they're off):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-worktree.sh" enabled >/dev/null 2>&1 \
  && cd "$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-worktree.sh" main-root)"
```

1. **Confirm the plan PR is merged.** The plan PR's branch protection requires every
   assumption/open-question thread to be resolved before merge, so a merged PR
   structurally guarantees each assumption was addressed. If it is not yet merged, stop —
   resolve the threads and merge first.

2. **Set the status:**
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-status.sh" "$1" "Ready for implementation"
   ```

3. **Clean up the plan branch.** The plan now lives on the integration branch as permanent
   documentation, so the `aind/plan/$1` branch is redundant. Delete it (remote, and local if
   present). The script **re-confirms the PR is MERGED first**, so an unmerged plan is never
   dropped, and it's a no-op if your repo already auto-deletes merged branches:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-revise-plan-pr.sh" "$1" cleanup
   ```
   Run this **after** the tag write (above) — branch hygiene last, so a cleanup hiccup never
   affects the committed status. **In worktree mode** this step also retires the plan worktree and
   fast-forwards the main checkout to include the merged plan. Because the first step above returned
   this session to the main checkout, the worktree removes cleanly. If it *still* warns that the
   worktree couldn't be removed (e.g. another shell is sitting inside it), run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-worktree.sh" prune` from the main checkout as a fallback.

This completes the plan phase; the build phase (out of scope for this iteration) begins from
`Ready for implementation`.

## Notes
- Approving the plan also ratifies the planner's **test strategy** recorded in the plan (whether to
  test, at what altitude, and the must-cover cases) — this drives the build phase later.
- Approving also ratifies that **every story acceptance criterion is either covered by the plan or a
  consciously-accepted narrowing** — each narrowing having been an open-question thread you resolved
  before merging. The plan's *AC coverage* map records which; a merged plan means you accepted it.
- If plan review instead surfaced a **story-level** problem, do not approve: close the plan PR
  and reroute the item to `Ready for intake` so the story can be fixed and re-scored.
