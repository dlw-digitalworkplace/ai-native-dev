#!/usr/bin/env bash
# check-claude-reviewer.sh — Claude Code PreToolUse(Bash) hook.
# Enforces the AIND reviewer's read-only contract. The cold reviewer subagent (agent_type
# "aind-reviewer") reviews by READING the diff; its ONLY sanctioned Bash is the plugin's
# aind-review-pr.sh. Any other Bash command from the reviewer — editing files, `git commit`/`push`,
# or running the project's build/lint/test/run commands — is BLOCKED (exit 2).
#
# Scoping is by agent identity: the hook is session-wide, but it acts ONLY when the calling agent is
# the reviewer. It FAILS OPEN — if the caller is any other agent (the warm coder, the main session)
# or the agent cannot be determined, the command is ALLOWED. So this hook never constrains the coder,
# who legitimately edits/commits/pushes.
#
# Reads the tool call as JSON on stdin: { "agent_type": "...", "tool_input": { "command": "..." } }.
# NOTE: `agent_type` carrying the subagent name is load-bearing. Confirm it is present in a live
# `claude --plugin-dir … --debug` session; until then this hook is a no-op for everyone (fail-open).

set -euo pipefail

INPUT="$(cat)"

if command -v jq >/dev/null 2>&1; then
  AGENT="$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)"
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
else
  # No jq: only act if we can positively read the reviewer agent_type; otherwise fail open.
  AGENT="$(printf '%s' "$INPUT" \
    | grep -oE '"agent_type"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
    | sed -E 's/.*"agent_type"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || true)"
  CMD="$INPUT"
fi

# Fail open for anyone who is not the reviewer.
[[ "$AGENT" == "aind-reviewer" ]] || exit 0

# Reviewer: allow only the sanctioned review script; block everything else.
if printf '%s' "$CMD" | grep -q 'aind-review-pr\.sh'; then
  exit 0
fi

echo "BLOCKED: the AIND reviewer is read-only — it reviews by reading the diff and may run only aind-review-pr.sh. Do not edit files, commit, push, or run build/lint/test/run commands; report issues as findings (file:line) for the coder to fix." >&2
exit 2
