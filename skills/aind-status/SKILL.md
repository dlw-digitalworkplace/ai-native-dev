---
name: aind-status
description: Set the AIND status on a work item. Use whenever an AIND agent needs to transition a story's phase (e.g. to Intake approved, Generating plan, Plan ready for review, Needs attention). Works with whichever tracker the project uses (Azure DevOps Boards or local markdown files).
allowed-tools: Bash
---

# Set the AIND status

A work item carries **exactly one** AIND status. Always change it with this script rather than by
hand:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-status.sh" "<work-item-id>" "<new-state>"
```

How it is stored depends on the tracker (handled for you): on **Azure DevOps** it is the single
`AIND status - <state>` tag, swapped atomically (strip any old AIND tag, add the new one, preserve
other tags) and optionally mirrored onto the native State; in the **file** tracker it is the scalar
`state:` field in the item's front-matter.

Valid states:
`Ready for intake`, `Intake declined`, `Intake approved`, `Generating plan`,
`Plan ready for review`, `Ready for implementation`, `In implementation`,
`Implementation complete`, `Needs attention`.

Who sets what: agents set the intake/plan states, `In implementation`, and
`Needs attention`; humans set `Ready for intake` and `Ready for implementation`.

Config (tracker credentials / item store) is auto-loaded from the project's `.claude/`.
