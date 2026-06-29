#!/usr/bin/env bash
# aind-revise-plan-pr.sh <work-item-id> <phase> [summary]
# Drives the plan-revision loop on an EXISTING plan PR — the re-run / feedback path that lets the
# planner fold reviewer comments back into the SAME PR instead of opening a new one.
#
# Phases:
#   status            Detect mode. Prints "<pr-number> <pr-url>" and exits 0 if an OPEN plan PR
#                     exists for <id>; exits 9 (no PR) otherwise. No side effects — lets /aind:plan
#                     choose create vs revise mode.
#   begin             Get ready to revise: refuse if the working tree is dirty, then fetch and
#                     check out the existing plan branch (so plans/<id>/plan.md in the tree is the
#                     PR's current state), and print a digest of ALL review feedback — top-level PR
#                     comments and every review thread, each tagged [OPEN]/[RESOLVED] with its
#                     file:line — for the planner to incorporate.
#   reply <tid> [msg] Reply to review thread <tid> (the thread=<id> printed by `begin`): a
#                     clarifying question when the feedback is unclear, or an "addressed — please
#                     resolve" note when the revision handled it. Message via arg or stdin. NEVER
#                     resolves the thread — resolution stays the human's merge gate.
#   push [summary]    Commit plans/<id>/ on the current (plan) branch and push to the SAME PR. Does
#                     NOT create a PR. If [summary] is given, also post it as a PR comment.
#   cleanup           Post-merge hygiene (used by /aind:approve-plan): delete the plan branch
#                     (remote + local). ONLY proceeds after re-confirming the PR is MERGED, so an
#                     unmerged plan is never dropped; idempotent if the branch is already gone.
#
# Branch: ${AIND_PLAN_BRANCH_PREFIX:-aind/plan/}<id>. Uses gh's built-in --jq, so no external jq is
# needed for the GitHub path. The planner deliberately does NOT resolve threads — resolution is the
# human's merge gate.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

ID="${1:-}"
PHASE="${2:-}"
[[ -n "$ID" && -n "$PHASE" ]] || aind_die "usage: aind-revise-plan-pr.sh <work-item-id> <status|begin|reply|push|cleanup> [args]"
aind_require_env AIND_GH_REPO
aind_require_cmd git gh

BRANCH="${AIND_PLAN_BRANCH_PREFIX:-aind/plan/}${ID}"

# Print the number of the open plan PR for this work item (empty if none).
pr_number() {
  gh pr list --repo "$AIND_GH_REPO" --head "$BRANCH" --state open \
    --json number --jq '.[0].number // empty'
}

case "$PHASE" in
  status)
    n="$(pr_number)"
    [[ -n "$n" ]] || { echo "aind: no open plan PR for work item $ID (branch $BRANCH)"; exit 9; }
    url="$(gh pr view "$n" --repo "$AIND_GH_REPO" --json url --jq .url)"
    echo "$n $url"
    ;;

  begin)
    n="$(pr_number)"
    [[ -n "$n" ]] || aind_die "no open plan PR for work item $ID — open one with aind-open-plan-pr.sh first"
    if ! git diff --quiet || ! git diff --cached --quiet; then
      aind_die "working tree has uncommitted changes — commit or stash before revising the plan"
    fi
    git fetch origin "$BRANCH" --quiet
    git checkout -B "$BRANCH" "origin/$BRANCH" >/dev/null 2>&1 \
      || aind_die "could not check out plan branch $BRANCH"

    echo "aind: on plan branch $BRANCH (PR #$n) — current plan at plans/${ID}/plan.md"
    echo
    echo "===== REVIEW FEEDBACK — address each [OPEN] item in the plan, reply on its thread (clarify or 'addressed'), then run: push ====="
    echo "--- PR comments ---"
    gh pr view "$n" --repo "$AIND_GH_REPO" --json comments \
      --jq '.comments[] | "[\(.author.login)] \(.body)"' 2>/dev/null || true
    echo
    echo "--- Review threads (assumptions / inline comments) ---"
    owner="${AIND_GH_REPO%%/*}"; repo="${AIND_GH_REPO##*/}"
    gh api graphql -f owner="$owner" -f repo="$repo" -F pr="$n" -f query='
      query($owner:String!,$repo:String!,$pr:Int!){
        repository(owner:$owner,name:$repo){
          pullRequest(number:$pr){
            reviewThreads(first:100){ nodes{
              id
              isResolved
              path
              line
              comments(first:50){ nodes{ author{login} body } }
            }}
          }
        }
      }' --jq '
      .data.repository.pullRequest.reviewThreads.nodes[]
      | (if .isResolved then "[RESOLVED]" else "[OPEN]" end) as $state
      | "\($state) thread=\(.id) \(.path):\(.line // "?")\n"
        + ([.comments.nodes[] | "    \(.author.login): \(.body)"] | join("\n"))
      ' 2>/dev/null || echo "(could not read review threads)"
    echo
    echo "================================================================================="
    ;;

  push)
    SUMMARY="${3:-}"
    git add "plans/${ID}/"
    if git diff --cached --quiet; then
      aind_die "no changes to plans/${ID}/ — edit the plan before pushing a revision"
    fi
    git commit -m "Revise plan for AB#${ID} per review" --quiet
    git push origin "$BRANCH" --quiet
    n="$(pr_number)"
    if [[ -n "$SUMMARY" && -n "$n" ]]; then
      printf '%s\n' "$SUMMARY" | gh pr comment "$n" --repo "$AIND_GH_REPO" --body-file -
    fi
    url=""
    [[ -n "$n" ]] && url="$(gh pr view "$n" --repo "$AIND_GH_REPO" --json url --jq .url 2>/dev/null || true)"
    echo "aind: revised plan pushed to PR ${n:+#$n} ${url}"
    ;;

  reply)
    THREAD_ID="${3:-}"
    [[ -n "$THREAD_ID" ]] || aind_die "usage: aind-revise-plan-pr.sh <id> reply <thread-id> [message]  (thread-id = the thread=<id> printed by 'begin'; message via arg or stdin)"
    BODY="${4:-}"
    [[ -n "$BODY" ]] || BODY="$(cat)"
    [[ -n "$BODY" ]] || aind_die "empty reply body"
    gh api graphql -f threadId="$THREAD_ID" -f body="$BODY" -f query='
      mutation($threadId:ID!,$body:String!){
        addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId, body:$body}){
          comment{ url }
        }
      }' --jq '.data.addPullRequestReviewThreadReply.comment.url'
    echo "aind: replied to thread $THREAD_ID (not resolved — resolution is the human's gate)"
    ;;

  cleanup)
    info="$(gh pr list --repo "$AIND_GH_REPO" --head "$BRANCH" --state all --json number,state --jq '.[0] // empty | "\(.number) \(.state)"' 2>/dev/null || true)"
    [[ -n "$info" ]] || aind_die "no plan PR found for $BRANCH — refusing to delete the branch (nothing proves it was merged)"
    num="${info%% *}"; st="${info##* }"
    [[ "$st" == "MERGED" ]] || aind_die "plan PR #$num for $BRANCH is '$st', not MERGED — refusing to delete the plan branch (merge it first)"
    echo "aind: plan PR #$num is MERGED — cleaning up $BRANCH"
    if git push origin --delete "$BRANCH" --quiet 2>/dev/null; then
      echo "aind: deleted remote branch $BRANCH"
    else
      echo "aind: remote branch $BRANCH already gone or not deletable — skipped"
    fi
    current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
    if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
      if [[ "$current" == "$BRANCH" ]]; then
        echo "aind: local branch $BRANCH is checked out — switch away, then 'git branch -D $BRANCH' to remove it"
      else
        git branch -D "$BRANCH" >/dev/null 2>&1 && echo "aind: deleted local branch $BRANCH" || true
      fi
    fi
    ;;

  *)
    aind_die "unknown phase '$PHASE' (use: status | begin | reply | push | cleanup)"
    ;;
esac
