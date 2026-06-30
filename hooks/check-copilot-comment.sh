#!/usr/bin/env bash
# Copilot CLI preToolUse signing-enforcement hook (bash; used on Linux/macOS/CI).
# Mirror of check-copilot-comment.ps1 for Copilot's `bash` hook key.
#
# Copilot contract:
#   stdin  = JSON object { sessionId, timestamp, cwd, toolName, toolArgs(JSON string) }
#   stdout = JSON { "permissionDecision": "allow"|"deny"|"ask", "permissionDecisionReason": "..." }
# Fails OPEN (allow) on any parse error so a hook bug cannot block every tool call.

INPUT="$(cat)"
CMD=""

if command -v jq >/dev/null 2>&1; then
  # toolArgs is a JSON *string*; parse it, then read .command (fall back to the raw string).
  CMD="$(printf '%s' "$INPUT" | jq -r '(.toolArgs // "") as $a | ($a | (try (fromjson.command) catch .)) // ""' 2>/dev/null || true)"
else
  CMD="$INPUT"
fi

# Sanctioned path — always allowed.
if printf '%s' "$CMD" | grep -q 'aind-comment\.sh'; then
  echo '{"permissionDecision":"allow"}'
  exit 0
fi

# Direct ADO comment write that bypasses the signer — block.
if printf '%s' "$CMD" | grep -Eq '_apis/wit/work[Ii]tems/[^/]+/comments|devops[[:space:]]+invoke.*comment'; then
  printf '%s' '{"permissionDecision":"deny","permissionDecisionReason":"Post ADO work-item comments via the aind-comment script, which signs them by agent name. Direct comment calls bypass signing and are not allowed. Use scripts/aind-comment.sh <work-item-id> <agent-name>."}'
  exit 0
fi

echo '{"permissionDecision":"allow"}'
exit 0
