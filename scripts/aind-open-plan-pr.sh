#!/usr/bin/env bash
# aind-open-plan-pr.sh <work-item-id> [pr-title]
# Opens the plan PR for a story (design-log D5/D10/D17). Assumes the plan markdown already
# exists at plans/<id>/plan.md (the /plan command writes it first, then calls this).
#
# Steps: branch off the integration branch -> commit the plan -> push -> open a PR that
# targets the integration branch, mentions AB#<id> (native Boards<->GitHub linking) and
# carries the AIND-LINKS block. The PR/link is created AFTER the push so a failure leaves a
# real, discoverable branch rather than a dangling pointer (D13/D17 ordering).
#
# Branch naming is a project concern (D10/D17) — override the prefix with
# AIND_PLAN_BRANCH_PREFIX (default: aind/plan/). The framework reaches the branch through
# the PR, never by deriving its name.
#
# Usage: aind-open-plan-pr.sh 123 "Add CSV export to the reports page"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

ID="${1:-}"
TITLE="${2:-}"
[[ -n "$ID" ]] || aind_die "usage: aind-open-plan-pr.sh <work-item-id> [pr-title]"
aind_require_env AIND_ADO_ORG AIND_ADO_PROJECT AIND_GH_REPO AIND_INTEGRATION_BRANCH
aind_require_cmd git gh

PLAN_PATH="plans/${ID}/plan.md"
[[ -f "$PLAN_PATH" ]] || aind_die "plan not found at $PLAN_PATH — write the plan before opening the PR"

BRANCH="${AIND_PLAN_BRANCH_PREFIX:-aind/plan/}${ID}"
[[ -n "$TITLE" ]] || TITLE="Plan for work item ${ID}"

# Branch off the latest integration branch.
git fetch origin "$AIND_INTEGRATION_BRANCH" --quiet
git checkout -B "$BRANCH" "origin/$AIND_INTEGRATION_BRANCH" >/dev/null 2>&1 \
  || git checkout -B "$BRANCH" "$AIND_INTEGRATION_BRANCH"

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
documentation (D10). Assumptions and open questions are posted as resolvable review threads
and must be resolved before merge (D5).

${LINKS_BLOCK}
EOF

PR_URL="$(gh pr create \
  --repo "$AIND_GH_REPO" \
  --base "$AIND_INTEGRATION_BRANCH" \
  --head "$BRANCH" \
  --title "Plan: ${TITLE} (AB#${ID})" \
  --body-file "$BODY_FILE")"

echo "aind: opened plan PR for work item $ID"
echo "$PR_URL"
