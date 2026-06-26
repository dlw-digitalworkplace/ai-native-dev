---
description: Mark an approved+merged plan as Ready for implementation (AIND Phase 2 close-out).
argument-hint: <work-item-id>
allowed-tools: Bash
---

# /approve-plan — Phase 2 close-out

Human-run helper for after you have **approved and merged** the plan PR for story `$1` in
GitHub. Approval is a human act (D5); this only records the resulting status transition.

Work item: **$1**

## Procedure

1. **Confirm the plan PR is merged.** The plan PR's branch protection requires every
   assumption/open-question thread to be resolved before merge (D5), so a merged PR
   structurally guarantees each assumption was addressed. If it is not yet merged, stop —
   resolve the threads and merge first.

2. **Set the status:**
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-status.sh" "$1" "Ready for implementation"
   ```

This completes the plan phase; the build phase (out of scope for this iteration) begins from
`Ready for implementation`.

## Notes
- Approving the plan also ratifies the planner's two testing recommendations (spec-level D8,
  live/E2E D9) recorded in the plan — these drive the build phase later.
- If plan review instead surfaced a **story-level** problem, do not approve: close the plan PR
  and reroute the item to `Ready for intake` so the story can be fixed and re-scored (D1).
