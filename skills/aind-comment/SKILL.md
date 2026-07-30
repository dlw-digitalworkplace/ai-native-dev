---
name: aind-comment
description: Post a signed comment to a work item. Use whenever an AIND agent needs to record reasoning, a verdict, advisory notes, or a stuck-state trail on a story. This is the ONLY sanctioned way to comment. Works with whichever tracker the project uses (Azure DevOps Boards or local markdown files).
allowed-tools: Bash
---

# Post a signed comment

Every AIND agent comment must be **signed by the agent name** — the script always appends the
signature (a visible attribution line plus a greppable `AIND-AGENT: <name>` marker); you never write
the signature yourself. This is the only sanctioned comment path (on Azure DevOps a PreToolUse hook
blocks any raw comment call that bypasses it).

The carrier depends on the tracker (handled for you): on **Azure DevOps** the comments field is HTML
rich-text, so the script converts a limited markdown subset — headings, `-`/`1.` lists, `**bold**`,
`` `code` ``, paragraphs, and **GitHub-style pipe tables** (`| a | b |` with a `|---|` separator row)
— and hides the marker in a `display:none` span (ADO strips HTML comments). In the **file** tracker
the markdown is appended verbatim to the item's `## Comments` section with an `<!-- AIND-AGENT: <name> -->`
marker. Write in that markdown subset either way; avoid nested lists and links.

Feed multi-line markdown via a **direct heredoc** (not a `cat | bash` pipeline — a pipeline makes the
harness re-prompt for permission on the `cat` half):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-comment.sh" "<work-item-id>" "<agent-name>" <<'EOF'
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

`<agent-name>` is the lowercase role: `intake`, `planner`, `coder`, `reviewer`, …. Config (tracker
credentials / item store) is auto-loaded from the project's `.claude/`. On failure the script prints
what went wrong (for ADO, the HTTP status and error message).
