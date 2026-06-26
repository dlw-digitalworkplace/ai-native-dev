---
name: aind-comment
description: Post a signed comment to an Azure DevOps work item. Use whenever an AIND agent needs to record reasoning, a verdict, advisory notes, or a stuck-state trail on a story. This is the ONLY sanctioned way to comment — a hook blocks raw ADO comment calls.
allowed-tools: Bash
---

# Post a signed ADO comment

Every AIND agent comment must be **signed by the agent name**. This script always appends
the signature — a visible attribution line plus a hidden `<span style="display:none">AIND-AGENT:
<name></span>` marker (ADO strips HTML comments, so the marker is a display:none span: invisible
when rendered, still greppable as `AIND-AGENT: <name>` in the stored text). You never write the
signature yourself. A PreToolUse hook blocks any direct ADO comment call that bypasses this script.

ADO work-item comments are an **HTML** field, not markdown. The script converts a limited
markdown subset for you — headings, `-`/`1.` lists, `**bold**`, `` `code` ``, paragraphs, and
**GitHub-style pipe tables** (`| a | b |` with a `|---|` separator row) — so write those; avoid
nested lists and links (they won't render reliably).

Prefer piping multi-line markdown on stdin:

```bash
cat <<'EOF' | bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-comment.sh" "<work-item-id>" "<agent-name>"
## Verdict: Intake declined

**Objective results**
- O1 Title present — PASS
- O2 ≥1 acceptance criterion — FAIL: no acceptance criteria found.
...
EOF
```

Or pass a short message as the third argument:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-comment.sh" "<work-item-id>" "<agent-name>" "short note"
```

`<agent-name>` is the lowercase role: `intake`, `planner` (later: `coder`, `reviewer`, …).
Needs `AIND_ADO_ORG`, `AIND_ADO_PROJECT`, and `AZURE_DEVOPS_EXT_PAT` — auto-sourced from the
project's `.claude/aind.env` if present, so you normally don't set them by hand. On failure the
script prints the HTTP status and ADO's error message.
