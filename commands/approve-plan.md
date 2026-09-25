---
description: Mark an approved plan as Ready for implementation (AIND Phase 2 close-out).
argument-hint: <work-item-id>
allowed-tools: Bash, AskUserQuestion
---

# /approve-plan — Phase 2 close-out

Human-run helper for after you have **approved** the plan for a story. Approval is a human act; this
only records the resulting status transition. **How the plan was reviewed depends on the flow mode:**
in the default **`pr`** flow you approved and **merged the plan PR** in GitHub/ADO; in the **`local`**
same-branch flow you reviewed `plans/<id>/plan.md` **locally in your editor** and there is no plan PR
— the command asks you to confirm the review before it records approval.

Work item: **$ARGUMENTS** (the work-item id).

## Writing style

Before you write anything a human reads, load the project's writing guide and follow it for this
whole run — every comment and confirmation question, and your own console messages (end the run with its **Done / Needs you / Next** block):
```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-writing.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}"
```
It sets the reading level. It never blocks the run; if it prints only a
warning, apply its short fallback rules.

## 0. Resolve the flow mode
```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-flowmode.sh"' _ "${CLAUDE_PLUGIN_ROOT}"
```
Prints `pr` or `local`. **`pr`** → follow every step as written. **`local`** → apply the two
local-flow deltas noted inline in steps 1 and 3 (ask the human to confirm the local review; skip
plan-branch cleanup); steps 0-worktree, 2, and 4 are unchanged.

## Procedure

**First — in worktree mode, return this session to the main checkout.** A prior `/aind:plan` run may
have left this shell's working directory inside the item's plan worktree. Close-out must run from the
main checkout: a session cannot remove its own worktree, and the branch cleanup + integration
fast-forward must act on the main tree. If worktrees are enabled, `cd` there before anything else (a
no-op when they're off):
```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-worktree.sh" "$@" >/dev/null 2>&1' _ "${CLAUDE_PLUGIN_ROOT}" enabled \
  && cd "$(bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-worktree.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" main-root)"
```

**Then stamp the phase start (telemetry).** Best-effort usage telemetry — records nothing unless the
project opted in, and never blocks close-out:
```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-usage.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" begin "$ARGUMENTS" approver
```

1. **Confirm the plan is approved.**
   - **`pr` flow — confirm the plan PR is merged.** The plan PR's branch protection requires every
     assumption/open-question thread to be resolved before merge, so a merged PR structurally
     guarantees each assumption was addressed. If it is not yet merged, stop — resolve the threads and
     merge first.
   - **`local` flow — ask the human to confirm the local review.** There is no plan PR; the plan was
     committed to the story branch and reviewed in the working tree. Because that review has no
     structural merge gate, **ask the user with `AskUserQuestion`** to confirm they have reviewed
     `plans/<id>/plan.md` (including its *Assumptions & open questions*) before you set the tag — e.g.
     *"Approve the local plan for AB#<id>? You're confirming you've reviewed `plans/<id>/plan.md` and
     its open questions."* with options **Approve** / **Not yet**. Proceed to step 2 **only** on
     Approve; on **Not yet** (or if the tool is unavailable and the user doesn't clearly confirm),
     **stop** and tell them to finish reviewing the plan and re-run. Do **not** set the tag without an
     explicit confirmation.

2. **Set the status:**
   ```bash
   bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-status.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" "$ARGUMENTS" "Ready for implementation"
   ```

3. **Clean up the plan branch.** *(`pr` flow only — **skip this entire step in the `local` flow**: there
   is no `aind/plan/<id>` branch, and the story branch must live on into `/aind:implement`. Running
   the cleanup below in local mode would error, since it looks for a merged plan PR that never
   existed.)* The plan now lives on the integration branch as permanent documentation, so the
   `aind/plan/<id>` branch is redundant. Delete it (remote, and local if present). The script
   **re-confirms the PR is MERGED first**, so an unmerged plan is never dropped, and it's a no-op if
   your repo already auto-deletes merged branches:
   ```bash
   bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-revise-plan-pr.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" "$ARGUMENTS" cleanup
   ```
   Run this **after** the tag write (above) — branch hygiene last, so a cleanup hiccup never
   affects the committed status. **In worktree mode** this step also retires the plan worktree and
   fast-forwards the main checkout to include the merged plan. Because the first step above returned
   this session to the main checkout, the worktree removes cleanly. If it *still* warns that the
   worktree couldn't be removed (e.g. another shell is sitting inside it), run
   `bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-worktree.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" prune` from the main checkout as a fallback.

4. **Record consumption (telemetry).** Best-effort — records this phase's token breakdown (a per-model
   JSON attachment on the work item) and its wall-clock time (to the configured duration field); a
   silent no-op when the project hasn't opted in. Never fails close-out:
   ```bash
   bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-usage.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" report "$ARGUMENTS" approver
   ```

This completes the plan phase; the build phase (out of scope for this iteration) begins from
`Ready for implementation`.

## Notes
- Approving the plan also ratifies the planner's **test strategy** recorded in the plan (whether to
  test, at what altitude, and the must-cover cases) — this drives the build phase later.
- Approving also ratifies that **every story acceptance criterion is either covered by the plan or a
  consciously-accepted narrowing**. In the `pr` flow each narrowing was an open-question thread you
  resolved before merging; in the `local` flow the narrowings are prose in the plan's *Assumptions &
  open questions* section, which your confirmation attests you read. Either way the plan's *AC coverage*
  map records which.
- If plan review instead surfaced a **story-level** problem, do not approve: reroute the item to
  `Ready for intake` so the story can be fixed and re-scored (in the `pr` flow, close the plan PR too;
  in the `local` flow, discard the story branch).
