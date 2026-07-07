---
description: Dreaming phase — synthesise accumulated lessons-learned into proposed .claude improvements, human-gated as one PR.
argument-hint: (none)
allowed-tools: Bash, Read, Glob, Grep, Task
---

# /dream — dreaming phase (continuous improvement)

You orchestrate one **dream cycle**: read the flow's accumulated *lessons-learned* exhaust, have a
**cold dreamer** cluster it into recurring patterns, let the **human curate those clusters**, then
turn the approved ones into **one PR against the project's `.claude` config**. You are the warm
orchestrator; the judgment lives in the cold dreamer and the two human gates. Two rules frame the
whole run: **the dreamer proposes only to the config layer, never the flow**, and **nothing changes
config without a human merging the PR**.

## 0. Gather the exhaust
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-dream.sh" digest
```
- Prints the unprocessed lessons (`.aind/lessons/new/*.md`). Keep the output — the dreamer needs it.
- Exits 9 ("nothing to dream on") → **stop** and tell the user there are no unprocessed lessons yet.

## 1. Spawn the cold dreamer — analysis pass (Gate 1 input)
Spawn the **`aind-dreamer`** agent as a **blocking, foreground Task** (do not background it, do not
poll). Give it **only** artifacts — the digest from step 0 — and `MODE: analyze`. It re-grounds from
the lessons + the current `.claude` config, clusters them, judges each with the
severity/recurrence/factualness rubric, and returns a structured `CLUSTERS:` + `PARKING-LOT:` list.
**Do not** hand it any of your own reasoning; its coldness is the point.

## 2. Human curation of the clusters (Gate 1)
Present the dreamer's clusters to the user in a compact, readable form — for each: title, the
lessons behind it, severity/recurrence/factualness, the dreamer's **confidence**, and the proposed
change (or that it's a **parking-lot** / flow concern). Then ask the user to **approve, adjust, or
reject each cluster** (and to confirm the parking-lot items). This is the curation gate you designed
in: the human prunes before anything is authored, now *with* the pattern view in front of them.

Record, for the rest of the run:
- **approved** clusters (with any human adjustments) → will be authored + their lessons archived;
- **rejected** clusters → their lessons rejected;
- **parking-lot** items the human kept → recorded as notes (§5), their lessons archived;
- clusters the user neither approved nor rejected → **left untouched** in `new/` (they stay in the
  pool for a future cycle).

If **no cluster** is approved for a change, skip §3–§4 (no config PR); still do §5–§6 and report.

## 3. Author the approved changes on a dream branch
Only if at least one cluster was approved for a change:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-dream.sh" start "aind/dream/$(date -u +%Y%m%d-%H%M)"
```
This branches off the integration branch (refuses on a dirty tree — relay that if so). Then spawn the
**`aind-dreamer`** agent again (blocking Task) with `MODE: author` and the **approved (adjusted)
clusters** from §2. It edits only the named `.claude` files and returns an `EDITED:` / `SKIPPED:`
list — it does **not** commit. Review that it stayed inside the config boundary; then commit:
```bash
git add -A .claude
git commit -m "dream: apply approved lessons-learned improvements"
```

## 4. Open the config PR (Gate 2)
Feed the summary as a direct heredoc (one command, no `cat |` pipe):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-dream.sh" open-pr "<dream-branch>" "Dreaming: <short theme>" <<'EOF'
## Proposed improvements
| Change | Files | From lessons | Confidence |
|---|---|---|---|
| <what changed + why> | `.claude/…` | <lesson ids> | <high\|medium\|low> |

## Parking lot (flow-level — for a human, not changed here)
- <structural concern, or "none">
EOF
```
It pushes the branch and opens the PR against the integration branch with an `AIND-DREAM` marker,
and prints the PR URL. This PR is Gate 2 — the human accepts/adjusts/rejects each change before merge.

## 5. Record any parking-lot notes
For each flow-level concern the user kept in §2, record it durably (one command each; body on stdin):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-dream.sh" note <<'EOF'
<the structural concern, and which lessons raised it>
EOF
```

## 6. Consume the processed lessons
Move the lessons you acted on out of `new/` so the next cycle sees only fresh exhaust. **Archive** the
lessons behind approved-change clusters and behind kept parking-lot items; **reject** the lessons
behind rejected clusters. Lesson ids are the `lessons:` values from the dreamer's clusters (the
filename stems). Leave everything else in `new/`.
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-dream.sh" consume archive <lesson-id> [<lesson-id> …]
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-dream.sh" consume reject  <lesson-id> [<lesson-id> …]
```

## 7. Report
Tell the user: the PR URL (if one was opened) and what it proposes, how many lessons were archived vs
rejected vs left in the pool, and any parking-lot notes recorded. Remind them the PR is theirs to
accept/adjust/reject — merging it is what actually changes any agent's behavior.

## Notes
- **Config layer only, never the flow.** The dreamer edits project rules, skills, the intake rubric,
  and project agent prompts — never the status model, the gates, or the AIND operational rules. A
  suspected flow problem is a parking-lot note, never a diff. If the author pass reports it `SKIPPED`
  a cluster because it needed a flow change, that becomes a parking-lot note too.
- **The human gate is permanent.** This is the highest-blast-radius write in the system — the config
  every agent reads on every run — so it gets the strictest controls, not the loosest: a cold
  synthesiser, curation of the clusters, and a mergeable PR where each change is individually
  reviewable and revertible. Never merge the dream PR yourself.
- **One dream cycle = one PR.** Don't fold several unrelated cycles into one branch.
