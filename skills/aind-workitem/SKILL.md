---
name: aind-workitem
description: Fetch an Azure DevOps work item (title, description, acceptance criteria, tags, relations) as JSON. Use when an AIND agent needs to ground itself in a story before scoring or planning it.
allowed-tools: Bash
---

# Fetch an ADO work item

Run the helper script to fetch the work item as JSON, then read the fields you need
(`System.Title`, `System.Description`, `Microsoft.VSTS.Common.AcceptanceCriteria`,
`System.Tags`, and `relations` for linked PRs):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-workitem.sh" "<work-item-id>"
```

Notes:
- Requires `AIND_ADO_ORG` and `AZURE_DEVOPS_EXT_PAT` in the environment (see the project's
  `.claude/CLAUDE.md`).
- The description and acceptance criteria are HTML — read through the markup for the text.
- This is read-only; it never modifies the story (the human owns the story text).
