#!/usr/bin/env bash
# aind-thread.sh <pr-number> <path> <line> <agent> [message]
# Posts a single RESOLVABLE review thread on a plan/code PR, anchored to a line of the diff, ALWAYS
# appending the agent signature. Resolvable review threads — not plain issue comments — are what the
# "require conversation resolution before merging" branch rule gates on, so each assumption /
# open question must be cleared by the human before the plan can merge.
#
# <agent> attributes the thread to its author (planner assumptions, reviewer findings, …) because in
# local mode every agent posts under one GitHub identity — same rule as ADO comments (aind-comment.sh).
#
# Anchor each assumption to its line in plans/<id>/plan.md. Message via 5th arg or stdin.
#
# Usage: aind-thread.sh 42 "plans/123/plan.md" 31 planner "Assumed Postgres; confirm vs MySQL?"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-forge.sh
source "$SCRIPT_DIR/aind-forge.sh"

PR="${1:-}"
PATH_IN_DIFF="${2:-}"
LINE="${3:-}"
AGENT="${4:-}"
[[ -n "$PR" && -n "$PATH_IN_DIFF" && -n "$LINE" && -n "$AGENT" ]] || aind_die "usage: aind-thread.sh <pr-number> <path> <line> <agent> [message]"
forge_require

if [[ $# -ge 5 ]]; then BODY="$5"; else BODY="$(cat)"; fi
[[ -n "$BODY" ]] || aind_die "empty thread message"
BODY="${BODY}$(aind_pr_signature "$AGENT")"

# Post via the forge adapter (it anchors to the PR head commit on the current diff, host-specifically).
TMP_BODY="$(mktemp)"; trap 'rm -f "$TMP_BODY"' EXIT
printf '%s' "$BODY" > "$TMP_BODY"
forge_thread "$PR" "$PATH_IN_DIFF" "$LINE" "$TMP_BODY" >/dev/null

echo "aind: posted resolvable review thread on PR $PR ($PATH_IN_DIFF:$LINE)"
