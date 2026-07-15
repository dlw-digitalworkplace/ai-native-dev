#!/usr/bin/env bash
# aind-open-plan-pr.sh <work-item-id> [pr-title]
# Opens the plan PR for a story. Assumes the plan markdown already
# exists at plans/<id>/plan.md (the /plan command writes it first, then calls this).
#
# Steps: branch off the integration branch -> commit the plan -> push -> open a PR that
# targets the integration branch, mentions AB#<id> (native Boards<->GitHub linking) and
# carries the AIND-LINKS block. The PR/link is created AFTER the push so a failure leaves a
# real, discoverable branch rather than a dangling pointer (create-link-after-push ordering).
#
# Branch naming is a project concern — override the prefix with
# AIND_PLAN_BRANCH_PREFIX (default: aind/plan/). The framework reaches the branch through
# the PR, never by deriving its name.
#
# Usage: aind-open-plan-pr.sh 123 "Add CSV export to the reports page"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-forge.sh
source "$SCRIPT_DIR/aind-forge.sh"

ID="${1:-}"
TITLE="${2:-}"
[[ -n "$ID" ]] || aind_die "usage: aind-open-plan-pr.sh <work-item-id> [pr-title]"
aind_require_env AIND_ADO_ORG AIND_ADO_PROJECT AIND_INTEGRATION_BRANCH
aind_require_cmd git
forge_require

BRANCH="$(aind_plan_branch "$ID")"
[[ -n "$TITLE" ]] || TITLE="Plan for work item ${ID}"

# Refuse to clobber an existing plan PR — revisions iterate the same PR via
# aind-revise-plan-pr.sh, never a second open. (Re-running create here would conflict on the
# branch push and fail PR creation.)
if [[ -n "$(forge_pr_list open "$BRANCH")" ]]; then
  aind_die "a plan PR already exists for $BRANCH — iterate it with aind-revise-plan-pr.sh (revise mode), don't re-open"
fi

# Branch off the latest integration branch. With worktrees enabled, this work happens in the item's
# plan worktree (created earlier by /aind:plan via `ensure-plan`, so plans/<id>/plan.md was authored
# there); reuse it — the cd is in this subprocess only, so the session's cwd is untouched. Without
# worktrees, branch in place exactly as before.
if bash "$SCRIPT_DIR/aind-worktree.sh" enabled >/dev/null 2>&1; then
  cd "$(bash "$SCRIPT_DIR/aind-worktree.sh" ensure "$ID" plan "$BRANCH" "origin/$AIND_INTEGRATION_BRANCH")" \
    || aind_die "could not prepare the plan worktree for $ID"
else
  git fetch origin "$AIND_INTEGRATION_BRANCH" --quiet
  git checkout -B "$BRANCH" "origin/$AIND_INTEGRATION_BRANCH" >/dev/null 2>&1 \
    || git checkout -B "$BRANCH" "$AIND_INTEGRATION_BRANCH"
fi

PLAN_PATH="plans/${ID}/plan.md"
[[ -f "$PLAN_PATH" ]] || aind_die "plan not found at $PLAN_PATH — write the plan before opening the PR"

git add "plans/${ID}/"
git commit -m "Add implementation plan for AB#${ID}

${TITLE}" --quiet

git push -u origin "$BRANCH" --quiet

# Build the PR body: a human summary + AB#<id> link trigger + the AIND-LINKS block.
LINKS_BLOCK="$(bash "$SCRIPT_DIR/aind-links.sh" write "$ID")"
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT
cat > "$BODY_FILE" <<EOF
Implementation plan for **AB#${ID}** — ${TITLE}.

The plan lives at \`${PLAN_PATH}\` and merges to \`${AIND_INTEGRATION_BRANCH}\` as living
documentation. Assumptions and open questions are posted as resolvable review threads
and must be resolved before merge.

${LINKS_BLOCK}
EOF

PR_URL="$(forge_pr_create "$AIND_INTEGRATION_BRANCH" "$BRANCH" "Plan: ${TITLE} (AB#${ID})" "$BODY_FILE" "$ID")"

echo "aind: opened plan PR for work item $ID"
echo "$PR_URL"
