---
name: aind-workitem
description: Fetch a work item (title, description, acceptance criteria, state, dependencies, links) as normalized JSON. Use when an AIND agent needs to ground itself in a story before scoring or planning it. Works with whichever tracker the project uses (Azure DevOps Boards or local markdown files).
allowed-tools: Bash
---

# Fetch a work item

Run the helper to fetch the work item as **normalized JSON**, then read the fields you need:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-workitem.sh" "<work-item-id>"
```

Output keys (the same shape regardless of tracker):

- `id`, `title`
- `description`, `acceptanceCriteria` — the story text. On the Azure DevOps tracker these are **HTML**
  (read through the markup); in the file tracker they are **markdown**.
- `state` — the current AIND state (e.g. `Ready for intake`, `Intake approved`), or empty if none set.
- `dependsOn` — array of the ids this story depends on.
- `links` — array of related URLs (e.g. its PRs).

Notes:
- The tracker backend is selected by config (`AIND_TRACKER`, default `ado`); the ADO backend needs
  `AIND_ADO_ORG` + `AZURE_DEVOPS_EXT_PAT`, the file backend needs the item store (`AIND_TRACKER_DIR`).
  These are auto-loaded from the project's `.claude/` config — you normally don't set them by hand.
- This is read-only; it never modifies the story (the human owns the story text).
