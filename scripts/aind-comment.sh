#!/usr/bin/env bash
# aind-comment.sh <work-item-id> <agent-name> [message]
# Posts a comment to a work item, ALWAYS appending an agent signature (every agent post is signed by
# the agent name; mitigates the "everything under one identity" limitation in local mode).
#
# The message may be passed as the 3rd arg OR piped on stdin (preferred for multi-line markdown):
#   echo "## Verdict ..." | aind-comment.sh 123 intake
#
# The tracker backend (AIND_TRACKER) decides the carrier: on Azure DevOps the comments field is HTML
# rich-text (the markdown subset is converted and the signature marker is a display:none span, since
# ADO strips HTML comments); in the file backend the markdown is appended verbatim to the item's
# `## Comments` section with an `<!-- AIND-AGENT: <name> -->` marker. This script is the ONLY
# sanctioned path for posting work-item comments — the signing PreToolUse hook blocks raw ADO comment
# calls that bypass it.
#
# Usage: aind-comment.sh 123 intake "Looks good."
#        cat report.md | aind-comment.sh 123 planner

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-tracker.sh
source "$SCRIPT_DIR/aind-tracker.sh"

ID="${1:-}"
AGENT="${2:-}"
[[ -n "$ID" && -n "$AGENT" ]] || aind_die "usage: aind-comment.sh <work-item-id> <agent-name> [message]"

# Body: 3rd arg if present, else stdin. Marshal into a temp file for the tracker verb.
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT
if [[ $# -ge 3 ]]; then printf '%s' "$3" > "$BODY_FILE"; else cat > "$BODY_FILE"; fi
[[ -s "$BODY_FILE" ]] || aind_die "empty comment message"

tracker_require
tracker_comment "$ID" "$AGENT" "$BODY_FILE"
