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
# shellcheck source=aind-forge.sh
source "$SCRIPT_DIR/aind-forge.sh"

MODE="${1:-}"
ID="${2:-}"
BRANCH="${3:-}"
[[ -n "$MODE" && -n "$ID" && -n "$BRANCH" ]] \
  || aind_die "usage: aind-open-code-pr.sh start|open <work-item-id> <branch> [pr-title]"

aind_require_cmd git
forge_require

# Enforce the branch convention: <type>/<id>-<short-name>. Keeping the id in the branch makes it
# traceable; the type prefix matches conventional branch naming. (The framework still reaches the
# branch through the PR, not by reconstructing this name.)
[[ "$BRANCH" =~ ^[a-z]+/${ID}-[A-Za-z0-9._-]+$ ]] \
  || aind_die "branch '$BRANCH' must follow <type>/${ID}-<short-name> (e.g. feat/${ID}-new-component)"

# A code PR already open for this branch means a re-run of the CREATE path, which would conflict on
# push / PR creation. Revising an open PR is a separate flow: re-run /aind:implement, which detects
# the open PR and enters revise mode (aind-revise-code-pr.sh) instead of opening a second PR.
code_pr_exists() {
  [[ -n "$(forge_pr_list open "$BRANCH")" ]]
}

case "$MODE" in
  start)
    aind_require_env AIND_INTEGRATION_BRANCH
    code_pr_exists && aind_die "a code PR already exists for $BRANCH — to change it, re-run /aind:implement (it enters revise mode) instead of opening a new PR"
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
    aind_require_env AIND_ADO_ORG AIND_ADO_PROJECT AIND_INTEGRATION_BRANCH
    [[ -n "$TITLE" ]] || TITLE="Implementation for work item ${ID}"

    code_pr_exists && aind_die "a code PR already exists for $BRANCH — to change it, re-run /aind:implement (it enters revise mode) instead of opening a new PR"

    # There must be implementation to review.
    git fetch origin "$AIND_INTEGRATION_BRANCH" --quiet
    if [[ "$(git rev-list --count "origin/${AIND_INTEGRATION_BRANCH}..${BRANCH}")" == "0" ]]; then
      aind_die "no commits on $BRANCH beyond $AIND_INTEGRATION_BRANCH — implement and commit before opening the PR"
    fi

    git push -u origin "$BRANCH" --quiet

    # Resolve the (now merged) plan PR URL so the code PR's AIND-LINKS can point back to the spec.
    PLAN_BRANCH="${AIND_PLAN_BRANCH_PREFIX:-aind/plan/}${ID}"
    PLAN_PR_ROW="$(forge_pr_list all "$PLAN_BRANCH")"; PLAN_PR_ROW="${PLAN_PR_ROW%%$'\n'*}"
    PLAN_PR_URL="$(printf '%s' "$PLAN_PR_ROW" | cut -f3)"

    LINKS_BLOCK="$(bash "$SCRIPT_DIR/aind-links.sh" write "$ID" "$PLAN_PR_URL")"
    BODY_FILE="$(mktemp)"
    trap 'rm -f "$BODY_FILE"' EXIT
    cat > "$BODY_FILE" <<EOF
Implementation for **AB#${ID}** — ${TITLE}.

Implements the merged plan at \`plans/${ID}/plan.md\` — see that plan for the task breakdown, any
data contracts, and the definition of done this PR is validated against.

${LINKS_BLOCK}
EOF

    PR_URL="$(forge_pr_create "$AIND_INTEGRATION_BRANCH" "$BRANCH" "Implement: ${TITLE} (AB#${ID})" "$BODY_FILE" "$ID")"

    echo "aind: opened code PR for work item $ID"
    echo "$PR_URL"
    ;;

  *)
    aind_die "usage: aind-open-code-pr.sh start|open <work-item-id> <branch> [pr-title]"
    ;;
esac
