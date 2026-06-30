#!/usr/bin/env bash
# check-claude-comment.sh — Claude Code PreToolUse(Bash) hook. (Copilot's equivalent is
# check-copilot-comment.{ps1,sh}; the two tools use different hook formats.)
# Enforces that ADO work-item comments go through aind-comment.sh (which always signs).
# A direct comment-posting call that bypasses the signing script is BLOCKED (exit 2).
#
# Reads the tool call as JSON on stdin: { "tool_input": { "command": "..." } }.
# Decision rule:
#   - command routes through aind-comment.sh        -> allow (exit 0)
#   - command looks like a direct ADO comment POST  -> block (exit 2)
#   - anything else                                 -> allow (exit 0)

set -euo pipefail

INPUT="$(cat)"

# Extract the command. Prefer jq; fall back to a permissive grep on the raw payload.
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
else
  CMD="$INPUT"
fi

# Sanctioned path — always allowed.
if printf '%s' "$CMD" | grep -q 'aind-comment\.sh'; then
  exit 0
fi

# Patterns that indicate a direct ADO comment write, bypassing the signer.
#  - REST: .../_apis/wit/workItems/<id>/comments
#  - az devops invoke against the wit "comments" resource
if printf '%s' "$CMD" | grep -Eq '_apis/wit/work[Ii]tems/[^/]+/comments|--resource[[:space:]]+comments|--area[[:space:]]+wit[[:space:]].*comments'; then
  echo "BLOCKED: post ADO work-item comments via the aind-comment skill/script, which signs them by agent name. Direct comment calls bypass signing and are not allowed. Use: \${CLAUDE_PLUGIN_ROOT}/scripts/aind-comment.sh <work-item-id> <agent-name>" >&2
  exit 2
fi

exit 0
