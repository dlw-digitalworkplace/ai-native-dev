---
name: aind-status
description: Set the single AIND status tag on an Azure DevOps work item (atomic remove-old-add-new). Use whenever an AIND agent needs to transition a story's phase (e.g. to Intake approved, Generating plan, Plan ready for review, Needs attention).
allowed-tools: Bash
---

# Set the AIND status tag

A work item carries **exactly one** `AIND status - <state>` tag (design-log D4). This script
swaps it atomically — it strips any existing AIND status tag and adds the new one while
preserving all other tags. Always use it rather than editing tags by hand.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-status.sh" "<work-item-id>" "<new-state>"
```

Valid states:
`Ready for intake`, `Intake declined`, `Intake approved`, `Generating plan`,
`Plan ready for review`, `Ready for implementation`, `In implementation`,
`Implementation complete`, `Needs attention`.

Who sets what (D4): agents set the intake/plan states, `In implementation`, and
`Needs attention`; humans set `Ready for intake` and `Ready for implementation`.

Requires `AIND_ADO_ORG` and `AZURE_DEVOPS_EXT_PAT` in the environment.
