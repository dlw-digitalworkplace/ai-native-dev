#!/usr/bin/env bash
# aind-thread.sh <pr-number> <path> <line> [message]
# Posts a single RESOLVABLE review thread on a plan PR, anchored to a line of the diff
# (design-log D5). Resolvable review threads — not plain issue comments — are what the
# "require conversation resolution before merging" branch rule gates on, so each assumption /
# open question must be cleared by the human before the plan can merge.
#
# Anchor each assumption to its line in plans/<id>/plan.md. Message via 4th arg or stdin.
#
# Usage: aind-thread.sh 42 "plans/123/plan.md" 31 "Assumed Postgres; confirm vs MySQL?"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

PR="${1:-}"
PATH_IN_DIFF="${2:-}"
LINE="${3:-}"
[[ -n "$PR" && -n "$PATH_IN_DIFF" && -n "$LINE" ]] || aind_die "usage: aind-thread.sh <pr-number> <path> <line> [message]"
aind_require_env AIND_GH_REPO
aind_require_cmd gh

if [[ $# -ge 4 ]]; then BODY="$4"; else BODY="$(cat)"; fi
[[ -n "$BODY" ]] || aind_die "empty thread message"

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
