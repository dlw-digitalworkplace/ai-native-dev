#!/usr/bin/env bash
# aind-revise-code-pr.sh <work-item-id> <phase> [args]
#
# Drives the code-revision loop on an EXISTING open code PR — the re-entry path that lets the warm
# coder apply human steering (a reviewer suggestion the human picked, a tiebreak verdict, a touch-up)
# and push to the SAME PR. The twin of aind-revise-plan-pr.sh (same <id> <phase> shape), but the code
# branch is coder-generated and never reconstructed, so the PR is resolved by marker-search
# (aind_find_code_prs), not a derivable branch name.
#
# Phases:
#   <id> status [pr]        Detect mode. Prints "<pr-number> <pr-url>" (exit 0) when a single OPEN code
#                           PR matches <id> ([pr] forces a specific one); prints "no open code PR" and
#                           exits 9 when there is none; dies (exit 1) if more than one OPEN PR matches.
#                           No side effects — lets /aind:implement choose build vs revise mode.
#   <id> begin [pr]         Refuse if the working tree is dirty; resolve the open code PR, fetch +
#                           check out its head branch (so the tree is the PR's current state), then
#                           print the STEERING DIGEST — delegates to `aind-review-pr.sh digest`
#                           (review threads tagged [OPEN]/[RESOLVED] with thread=<id> + file:line, and
#                           top-level PR comments) for the coder to act on.
#   <id> push [summary]     Push the current (code) branch to the SAME PR — the coder makes its own
#                           logical commits first. If [summary] is given, also post it as a PR comment.
#                           Does NOT create a PR and NEVER resolves threads (resolution is the human's
#                           merge gate). Thread replies reuse `aind-review-pr.sh reply`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

ID="${1:-}"
PHASE="${2:-}"
[[ -n "$ID" && -n "$PHASE" ]] || aind_die "usage: aind-revise-code-pr.sh <work-item-id> <status|begin|push> [args]"
[[ "$ID" =~ ^[0-9]+$ ]] || aind_die "work-item id must be numeric, got '$ID'"
aind_require_env AIND_GH_REPO
aind_require_cmd git gh

# Resolve the single OPEN code PR for <id> (or the explicit [pr] if given and OPEN). On success sets
# R_NUM/R_URL/R_HEAD and returns 0. Returns 1 (none) or 2 (more than one OPEN) without output, so the
# caller can phrase its own message.
resolve_open() {
  local explicit="${1:-}" line st cands open n
  if [[ -n "$explicit" ]]; then
    [[ "$explicit" =~ ^[0-9]+$ ]] || aind_die "pr-number must be numeric, got '$explicit'"
    if ! line="$(gh pr view "$explicit" --repo "$AIND_GH_REPO" \
        --json number,url,state,headRefName --jq '[(.number|tostring),.url,.headRefName,.state]|@tsv' 2>/dev/null)"; then
      return 1
    fi
    st="$(printf '%s' "$line" | cut -f4)"
    [[ "$st" == "OPEN" ]] || return 1
    IFS=$'\t' read -r R_NUM R_URL R_HEAD _ <<< "$line"
    return 0
  fi
  cands="$(aind_find_code_prs "$ID")"
  open="$(printf '%s\n' "$cands" | awk -F'\t' '$1=="OPEN"')"
  n="$(printf '%s\n' "$open" | awk 'NF{c++} END{print c+0}')"
  [[ "$n" -eq 0 ]] && return 1
  [[ "$n" -gt 1 ]] && return 2
  IFS=$'\t' read -r _ R_NUM R_URL R_HEAD <<< "$open"
  return 0
}

case "$PHASE" in
  status)
    PR="${3:-}"
    rc=0; resolve_open "$PR" || rc=$?
    case "$rc" in
      0) echo "$R_NUM $R_URL" ;;
      2) aind_die "more than one OPEN code PR matches AB#$ID — pass the PR number: /aind:implement handles a single code PR" ;;
      *) echo "aind: no open code PR for work item $ID"; exit 9 ;;
    esac
    ;;

  begin)
    PR="${3:-}"
    if ! git diff --quiet || ! git diff --cached --quiet; then
      aind_die "working tree has uncommitted changes — commit or stash before revising the code PR"
    fi
    rc=0; resolve_open "$PR" || rc=$?
    case "$rc" in
      1) aind_die "no open code PR for work item $ID — nothing to revise (build one with /aind:implement first)" ;;
      2) aind_die "more than one OPEN code PR matches AB#$ID — pass the PR number: aind-revise-code-pr.sh begin $ID <pr>" ;;
    esac
    git fetch origin "$R_HEAD" --quiet
    git checkout -B "$R_HEAD" "origin/$R_HEAD" >/dev/null 2>&1 \
      || aind_die "could not check out code branch $R_HEAD (PR #$R_NUM)"

    echo "aind: on code branch $R_HEAD (PR #$R_NUM) — apply ONLY the human-directed changes, reply on each acted thread, then run: push"
    echo
    echo "===== STEERING — the human's instructions on the PR (comments + threads). Act only on these. ====="
    bash "$SCRIPT_DIR/aind-review-pr.sh" digest "$R_NUM"
    echo "================================================================================="
    ;;

  push)
    SUMMARY="${3:-}"
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
    [[ -n "$branch" && "$branch" != "HEAD" ]] || aind_die "not on a branch — run 'begin' first to check out the code PR branch"
    git push origin "$branch" --quiet
    if [[ -n "$SUMMARY" ]]; then
      rc=0; resolve_open "" || rc=$?
      if [[ "$rc" -eq 0 ]]; then
        printf '%s\n' "$SUMMARY" | gh pr comment "$R_NUM" --repo "$AIND_GH_REPO" --body-file -
      else
        echo "aind: [WARN] pushed, but could not resolve a single open PR to post the summary comment — skipped" >&2
      fi
    fi
    echo "aind: revised code pushed to branch $branch${R_URL:+ (PR $R_URL)}"
    ;;

  *)
    aind_die "unknown phase '$PHASE' (use: status | begin | push)"
    ;;
esac
