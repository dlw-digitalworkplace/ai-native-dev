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
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

PR="${1:-}"
PATH_IN_DIFF="${2:-}"
LINE="${3:-}"
AGENT="${4:-}"
[[ -n "$PR" && -n "$PATH_IN_DIFF" && -n "$LINE" && -n "$AGENT" ]] || aind_die "usage: aind-thread.sh <pr-number> <path> <line> <agent> [message]"
aind_require_env AIND_GH_REPO
aind_require_cmd gh

if [[ $# -ge 5 ]]; then BODY="$5"; else BODY="$(cat)"; fi
[[ -n "$BODY" ]] || aind_die "empty thread message"
BODY="${BODY}$(aind_gh_signature "$AGENT")"

# Anchor to the PR head commit so the comment lands on the current diff.
SHA="$(gh pr view "$PR" --repo "$AIND_GH_REPO" --json headRefOid -q .headRefOid)"
[[ -n "$SHA" ]] || aind_die "could not resolve head commit for PR $PR"

gh api "repos/${AIND_GH_REPO}/pulls/${PR}/comments" \
  -f body="$BODY" \
  -f commit_id="$SHA" \
  -f path="$PATH_IN_DIFF" \
  -F line="$LINE" \
  -f side=RIGHT >/dev/null

echo "aind: posted resolvable review thread on PR $PR ($PATH_IN_DIFF:$LINE)"
