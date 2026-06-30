#!/usr/bin/env bash
# aind-open-code-pr.sh start <work-item-id> <branch>
# aind-open-code-pr.sh open  <work-item-id> <branch> [pr-title]
#
# The GitHub-flow twin of aind-open-plan-pr.sh, for the build phase.
#
#   start : branch off the integration branch and check it out, so the coder implements on a
#           fresh branch. Refuses if a code PR for that branch already exists (no clobber).
#   open  : push the (already-committed) branch and open a code PR that targets the integration
#           branch, mentions AB#<id> (native Boards<->GitHub linking) and carries the AIND-LINKS
#           block — including the plan-PR URL, so an agent re-grounding from the PR alone can reach
#           the spec. The PR is created AFTER the push, so a failure leaves a real, discoverable
#           branch rather than a dangling pointer (create-link-after-push ordering).
#
# The coding agent chooses the branch name from a fixed convention: <type>/<id>-<short-name>
# (e.g. feat/123-new-component, fix/456-typo). The framework never reaches the branch by deriving
# its name — every later step finds it through the code PR.
#
# Usage:
#   aind-open-code-pr.sh start 123 feat/123-csv-export
#   aind-open-code-pr.sh open  123 feat/123-csv-export "Add CSV export to the reports page"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

MODE="${1:-}"
ID="${2:-}"
BRANCH="${3:-}"
[[ -n "$MODE" && -n "$ID" && -n "$BRANCH" ]] \
  || aind_die "usage: aind-open-code-pr.sh start|open <work-item-id> <branch> [pr-title]"

aind_require_cmd git gh

# Enforce the branch convention: <type>/<id>-<short-name>. Keeping the id in the branch makes it
# traceable; the type prefix matches conventional branch naming. (The framework still reaches the
# branch through the PR, not by reconstructing this name.)
[[ "$BRANCH" =~ ^[a-z]+/${ID}-[A-Za-z0-9._-]+$ ]] \
  || aind_die "branch '$BRANCH' must follow <type>/${ID}-<short-name> (e.g. feat/${ID}-new-component)"

# A code PR already open for this branch means a re-run — code-revision is not supported in this
# iteration (a re-run would conflict on push / gh pr create).
code_pr_exists() {
  [[ -n "$(gh pr list --repo "$AIND_GH_REPO" --head "$BRANCH" --state open --json number --jq '.[0].number // empty')" ]]
}

case "$MODE" in
  start)
    aind_require_env AIND_GH_REPO AIND_INTEGRATION_BRANCH
    code_pr_exists && aind_die "a code PR already exists for $BRANCH — code-revision is not supported in this iteration"
    # Don't clobber a dirty working tree: branching off integration with uncommitted tracked
    # changes would drag them onto the new branch. Refuse and let the developer decide — never
    # stash automatically. (Untracked files are fine; they're carried along harmlessly.)
    if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
      aind_die "working tree has uncommitted changes — commit or stash them before starting (this command won't stash for you)"
    fi
    git fetch origin "$AIND_INTEGRATION_BRANCH" --quiet
    git checkout -B "$BRANCH" "origin/$AIND_INTEGRATION_BRANCH" >/dev/null 2>&1 \
      || git checkout -B "$BRANCH" "$AIND_INTEGRATION_BRANCH"
    echo "aind: on branch $BRANCH (off $AIND_INTEGRATION_BRANCH) — implement, commit, then run 'open'"
    ;;

  open)
    TITLE="${4:-}"
    aind_require_env AIND_ADO_ORG AIND_ADO_PROJECT AIND_GH_REPO AIND_INTEGRATION_BRANCH
    [[ -n "$TITLE" ]] || TITLE="Implementation for work item ${ID}"

    code_pr_exists && aind_die "a code PR already exists for $BRANCH — code-revision is not supported in this iteration"

    # There must be implementation to review.
    git fetch origin "$AIND_INTEGRATION_BRANCH" --quiet
    if [[ "$(git rev-list --count "origin/${AIND_INTEGRATION_BRANCH}..${BRANCH}")" == "0" ]]; then
      aind_die "no commits on $BRANCH beyond $AIND_INTEGRATION_BRANCH — implement and commit before opening the PR"
    fi

    git push -u origin "$BRANCH" --quiet

    # Resolve the (now merged) plan PR URL so the code PR's AIND-LINKS can point back to the spec.
    PLAN_BRANCH="${AIND_PLAN_BRANCH_PREFIX:-aind/plan/}${ID}"
    PLAN_PR_URL="$(gh pr list --repo "$AIND_GH_REPO" --head "$PLAN_BRANCH" --state all --json url --jq '.[0].url // empty')"

    LINKS_BLOCK="$(bash "$SCRIPT_DIR/aind-links.sh" write "$ID" "$PLAN_PR_URL")"
    BODY_FILE="$(mktemp)"
    trap 'rm -f "$BODY_FILE"' EXIT
    cat > "$BODY_FILE" <<EOF
Implementation for **AB#${ID}** — ${TITLE}.

Implements the merged plan at \`plans/${ID}/plan.md\` — see that plan for the task breakdown, any
data contracts, and the definition of done this PR is validated against.

${LINKS_BLOCK}
EOF

    PR_URL="$(gh pr create \
      --repo "$AIND_GH_REPO" \
      --base "$AIND_INTEGRATION_BRANCH" \
      --head "$BRANCH" \
      --title "Implement: ${TITLE} (AB#${ID})" \
      --body-file "$BODY_FILE")"

    echo "aind: opened code PR for work item $ID"
    echo "$PR_URL"
    ;;

  *)
    aind_die "usage: aind-open-code-pr.sh start|open <work-item-id> <branch> [pr-title]"
    ;;
esac
