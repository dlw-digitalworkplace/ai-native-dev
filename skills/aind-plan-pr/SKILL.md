---
name: aind-plan-pr
description: Open the plan PR for a story and post assumptions/open questions as resolvable review threads. Use when the AIND planner has written plans/<id>/plan.md and needs to deliver it as a reviewable GitHub PR.
allowed-tools: Bash
---

# Open the plan PR and post assumption threads

The plan is delivered as its own GitHub PR that merges to the integration branch *before any
code branch exists* (D10), with assumptions recorded as resolvable threads that gate the
merge (D5). Use these scripts in order — write `plans/<id>/plan.md` first.

**1. Open the PR** (branches, commits the plan, pushes, opens a PR with `AB#<id>` native
linking + the `AIND-LINKS` block). Capture the printed PR URL/number:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-open-plan-pr.sh" "<work-item-id>" "<story title>"
```

**2. Post each assumption / open question as its own resolvable thread**, anchored to its
line in the plan diff (so "require conversation resolution before merging" gates each one):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-thread.sh" "<pr-number>" "plans/<id>/plan.md" "<line>" "<assumption + the question to resolve>"
```

Anchor each thread to the line in the **Assumptions & open questions** section where you
wrote that item, so the thread and the document entry line up.

Requires `AIND_ADO_ORG`, `AIND_ADO_PROJECT`, `AIND_GH_REPO`, `AIND_INTEGRATION_BRANCH` (and
`AZURE_DEVOPS_EXT_PAT`). Branch naming is project-controlled via `AIND_PLAN_BRANCH_PREFIX`.
