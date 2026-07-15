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
# shellcheck source=aind-forge.sh
source "$SCRIPT_DIR/aind-forge.sh"

ID="${1:-}"
PHASE="${2:-}"
[[ -n "$ID" && -n "$PHASE" ]] || aind_die "usage: aind-revise-plan-pr.sh <work-item-id> <status|begin|reply|push|cleanup> [args]"
aind_require_cmd git
forge_require

BRANCH="$(aind_plan_branch "$ID")"

# Print the number of the open plan PR for this work item (empty if none).
pr_number() {
  local row
  row="$(forge_pr_list open "$BRANCH")"; row="${row%%$'\n'*}"
  printf '%s' "$row" | cut -f2
}

case "$PHASE" in
  status)
    n="$(pr_number)"
    [[ -n "$n" ]] || { echo "aind: no open plan PR for work item $ID (branch $BRANCH)"; exit 9; }
    url="$(forge_pr_meta "$n" | cut -f2)"
    echo "$n $url"
    ;;

  begin)
    n="$(pr_number)"
    [[ -n "$n" ]] || aind_die "no open plan PR for work item $ID — open one with aind-open-plan-pr.sh first"
    # With worktrees enabled, revise the plan in its dedicated worktree (reuse the one the create run
    # made; create it on the PR branch if this is a fresh session). The cd is in this subprocess, so
    # the session's cwd is untouched.
    PLAN_LOC="plans/${ID}/plan.md"
    if bash "$SCRIPT_DIR/aind-worktree.sh" enabled >/dev/null 2>&1; then
      WT="$(bash "$SCRIPT_DIR/aind-worktree.sh" ensure "$ID" plan "$BRANCH" "origin/$BRANCH")" \
        || aind_die "could not prepare the plan worktree for $ID"
      cd "$WT"
      PLAN_LOC="$WT/plans/${ID}/plan.md"
    fi
    if ! git diff --quiet || ! git diff --cached --quiet; then
      aind_die "working tree has uncommitted changes — commit or stash before revising the plan"
    fi
    git fetch origin "$BRANCH" --quiet
    git checkout -B "$BRANCH" "origin/$BRANCH" >/dev/null 2>&1 \
      || aind_die "could not check out plan branch $BRANCH"

    echo "aind: on plan branch $BRANCH (PR #$n) — current plan at $PLAN_LOC"
    echo
    echo "===== REVIEW FEEDBACK — address each [OPEN] item in the plan, reply on its thread (clarify or 'addressed'), then run: push ====="
    echo "--- PR comments ---"
    forge_comment_list "$n"
    echo
    echo "--- Review threads (assumptions / inline comments) ---"
    forge_thread_list "$n"
    echo
    echo "================================================================================="
    ;;

  push)
    SUMMARY="${3:-}"
    if bash "$SCRIPT_DIR/aind-worktree.sh" enabled >/dev/null 2>&1; then
      WT="$(bash "$SCRIPT_DIR/aind-worktree.sh" path "$ID" plan)"
      [[ -f "$WT/.git" ]] || aind_die "plan worktree $WT missing — run /aind:plan (revise 'begin') first"
      cd "$WT"
    fi
    git add "plans/${ID}/"
    if git diff --cached --quiet; then
      aind_die "no changes to plans/${ID}/ — edit the plan before pushing a revision"
    fi
    git commit -m "Revise plan for AB#${ID} per review" --quiet
    git push origin "$BRANCH" --quiet
    n="$(pr_number)"
    if [[ -n "$SUMMARY" && -n "$n" ]]; then
      SUMMARY="${SUMMARY}$(aind_pr_signature planner)"   # plan revision is always the planner
      _tmp="$(mktemp)"; printf '%s\n' "$SUMMARY" > "$_tmp"
      forge_comment "$n" "$_tmp"; rm -f "$_tmp"
    fi
    url=""
    [[ -n "$n" ]] && url="$(forge_pr_meta "$n" | cut -f2 2>/dev/null || true)"
    echo "aind: revised plan pushed to PR ${n:+#$n} ${url}"
    ;;

  reply)
    THREAD_ID="${3:-}"
    [[ -n "$THREAD_ID" ]] || aind_die "usage: aind-revise-plan-pr.sh <id> reply <thread-id> [message]  (thread-id = the thread=<id> printed by 'begin'; message via arg or stdin)"
    BODY="${4:-}"
    [[ -n "$BODY" ]] || BODY="$(cat)"
    [[ -n "$BODY" ]] || aind_die "empty reply body"
    BODY="${BODY}$(aind_pr_signature planner)"   # plan-PR thread replies are always the planner
    n="$(pr_number)"
    _tmp="$(mktemp)"; printf '%s\n' "$BODY" > "$_tmp"
    forge_reply "${n:-0}" "$THREAD_ID" "$_tmp"; rm -f "$_tmp"
    echo "aind: replied to thread $THREAD_ID (not resolved — resolution is the human's gate)"
    ;;

  cleanup)
    row="$(forge_pr_list all "$BRANCH")"; row="${row%%$'\n'*}"
    [[ -n "$row" ]] || aind_die "no plan PR found for $BRANCH — refusing to delete the branch (nothing proves it was merged)"
    st="$(printf '%s' "$row" | cut -f1)"; num="$(printf '%s' "$row" | cut -f2)"
    [[ "$st" == "MERGED" ]] || aind_die "plan PR #$num for $BRANCH is '$st', not MERGED — refusing to delete the plan branch (merge it first)"
    echo "aind: plan PR #$num is MERGED — cleaning up $BRANCH"
    if git push origin --delete "$BRANCH" --quiet 2>/dev/null; then
      echo "aind: deleted remote branch $BRANCH"
    else
      echo "aind: remote branch $BRANCH already gone or not deletable — skipped"
    fi

    if bash "$SCRIPT_DIR/aind-worktree.sh" enabled >/dev/null 2>&1; then
      # Worktree mode: the plan branch lives in the plan worktree, not the main checkout. Remove the
      # worktree first (frees the branch), then delete the local branch, then fast-forward the main
      # checkout's integration branch so this session ends on main with the latest code.
      bash "$SCRIPT_DIR/aind-worktree.sh" remove "$ID" plan || \
        echo "aind: [WARN] could not remove the plan worktree — run 'aind-worktree.sh prune' from the main checkout" >&2
      if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
        git branch -D "$BRANCH" >/dev/null 2>&1 && echo "aind: deleted local branch $BRANCH" || true
      fi
      if [[ -n "${AIND_INTEGRATION_BRANCH:-}" ]]; then
        git fetch origin "$AIND_INTEGRATION_BRANCH" --prune --quiet 2>/dev/null || true
        cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
        if [[ "$cur" == "$AIND_INTEGRATION_BRANCH" ]] && git diff --quiet && git diff --cached --quiet; then
          git merge --ff-only "origin/$AIND_INTEGRATION_BRANCH" >/dev/null 2>&1 \
            && echo "aind: fast-forwarded $AIND_INTEGRATION_BRANCH to include the merged plan" \
            || echo "aind: [WARN] could not fast-forward $AIND_INTEGRATION_BRANCH — pull manually" >&2
        fi
      fi
    else
      current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
      if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
        if [[ "$current" == "$BRANCH" ]]; then
          echo "aind: local branch $BRANCH is checked out — switch away, then 'git branch -D $BRANCH' to remove it"
        else
          git branch -D "$BRANCH" >/dev/null 2>&1 && echo "aind: deleted local branch $BRANCH" || true
        fi
      fi
    fi
    ;;

  *)
    aind_die "unknown phase '$PHASE' (use: status | begin | reply | push | cleanup)"
    ;;
esac
