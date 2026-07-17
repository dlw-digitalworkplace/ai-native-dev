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
#   <id> rebase [pr]        Rebase the PR head branch onto the integration branch — the way to clear a
#                           merge conflict the reviewer flagged (another PR moved integration under
#                           this one). Checks out the PR head fresh from origin, fetches integration,
#                           and rebases. A CLEAN rebase leaves the branch ready to `push`; a CONFLICT
#                           leaves the working tree in the rebase state and lists the conflicted files
#                           (the coder resolves them in-context, `git add`, `git rebase --continue`,
#                           then `push`) and exits 3. Never aborts the rebase for you. Needs
#                           AIND_INTEGRATION_BRANCH.
#   <id> push [summary]     Push the current (code) branch to the SAME PR — the coder makes its own
#                           logical commits first. If [summary] is given, also post it as a PR comment.
#                           Force-with-lease-aware: if a rebase rewrote history so the remote branch is
#                           no longer an ancestor of HEAD, pushes with --force-with-lease (safe — it
#                           refuses if origin moved unexpectedly); otherwise a plain fast-forward push.
#                           Does NOT create a PR and NEVER resolves threads (resolution is the human's
#                           merge gate). Thread replies reuse `aind-review-pr.sh reply`.
#   <id> deviation <pr> <human-cite> <text>
#                           Record ONE human-directed deviation — a change the human steered on the PR
#                           that adds to or diverges from the merged plan (new scope, a removed item, a
#                           changed contract) — into a `## Directed deviations` block in the PR body
#                           (idempotent: creates the block, or appends within it). <human-cite> is the
#                           handle the reviewer can verify in the steering digest — a `thread=<id>`
#                           (preferred) or a short reference to the human's PR comment. The reviewer
#                           treats these as authoritative addenda to the plan (so the added work is NOT
#                           scope creep) after confirming the cited source is human-authored.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-forge.sh
source "$SCRIPT_DIR/aind-forge.sh"

ID="${1:-}"
PHASE="${2:-}"
[[ -n "$ID" && -n "$PHASE" ]] || aind_die "usage: aind-revise-code-pr.sh <work-item-id> <status|begin|rebase|push|deviation> [args]"
[[ "$ID" =~ ^[0-9]+$ ]] || aind_die "work-item id must be numeric, got '$ID'"
aind_require_cmd git
forge_require

# Resolve the single OPEN code PR for <id> (or the explicit [pr] if given and OPEN). On success sets
# R_NUM/R_URL/R_HEAD and returns 0. Returns 1 (none) or 2 (more than one OPEN) without output, so the
# caller can phrase its own message.
resolve_open() {
  local explicit="${1:-}" line st cands open n
  if [[ -n "$explicit" ]]; then
    [[ "$explicit" =~ ^[0-9]+$ ]] || aind_die "pr-number must be numeric, got '$explicit'"
    # forge_pr_meta returns: number \t url \t head \t state
    if ! line="$(forge_pr_meta "$explicit" 2>/dev/null)"; then
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
    rc=0; resolve_open "$PR" || rc=$?
    case "$rc" in
      1) aind_die "no open code PR for work item $ID — nothing to revise (build one with /aind:implement first)" ;;
      2) aind_die "more than one OPEN code PR matches AB#$ID — pass the PR number: aind-revise-code-pr.sh begin $ID <pr>" ;;
    esac
    # With worktrees enabled, revise in the item's implement worktree (reuse the one the build run
    # made; create it on the PR head if this is a fresh session). The cd is in this subprocess only.
    WT_NOTE=""
    if bash "$SCRIPT_DIR/aind-worktree.sh" enabled >/dev/null 2>&1; then
      WT="$(bash "$SCRIPT_DIR/aind-worktree.sh" ensure "$ID" impl "$R_HEAD" "origin/$R_HEAD")" \
        || aind_die "could not prepare the implement worktree for $ID"
      cd "$WT"
      WT_NOTE=" — worktree $WT (treat it as your project root)"
    fi
    if ! git diff --quiet || ! git diff --cached --quiet; then
      aind_die "working tree has uncommitted changes — commit or stash before revising the code PR"
    fi
    git fetch origin "$R_HEAD" --quiet
    git checkout -B "$R_HEAD" "origin/$R_HEAD" >/dev/null 2>&1 \
      || aind_die "could not check out code branch $R_HEAD (PR #$R_NUM)"

    echo "aind: on code branch $R_HEAD (PR #$R_NUM)${WT_NOTE} — apply ONLY the human-directed changes, reply on each acted thread, then run: push"
    echo
    echo "===== STEERING — the human's instructions on the PR (comments + threads). Act only on these. ====="
    bash "$SCRIPT_DIR/aind-review-pr.sh" digest "$R_NUM"
    echo "================================================================================="
    ;;

  rebase)
    PR="${3:-}"
    aind_require_env AIND_INTEGRATION_BRANCH
    rc=0; resolve_open "$PR" || rc=$?
    case "$rc" in
      1) aind_die "no open code PR for work item $ID — nothing to rebase (build one with /aind:implement first)" ;;
      2) aind_die "more than one OPEN code PR matches AB#$ID — pass the PR number: aind-revise-code-pr.sh rebase $ID <pr>" ;;
    esac
    # With worktrees enabled, rebase in the item's implement worktree (same subprocess-only cd as
    # begin/push). Create it on the PR head if this is a fresh session.
    WT_NOTE=""
    if bash "$SCRIPT_DIR/aind-worktree.sh" enabled >/dev/null 2>&1; then
      WT="$(bash "$SCRIPT_DIR/aind-worktree.sh" ensure "$ID" impl "$R_HEAD" "origin/$R_HEAD")" \
        || aind_die "could not prepare the implement worktree for $ID"
      cd "$WT"
      WT_NOTE=" — worktree $WT (treat it as your project root)"
    fi
    if ! git diff --quiet || ! git diff --cached --quiet; then
      aind_die "working tree has uncommitted changes — commit or stash before rebasing the code PR"
    fi
    git fetch origin "$R_HEAD" "$AIND_INTEGRATION_BRANCH" --quiet
    git checkout -B "$R_HEAD" "origin/$R_HEAD" >/dev/null 2>&1 \
      || aind_die "could not check out code branch $R_HEAD (PR #$R_NUM)"
    echo "aind: rebasing $R_HEAD onto origin/$AIND_INTEGRATION_BRANCH (PR #$R_NUM)${WT_NOTE}"
    if git rebase "origin/$AIND_INTEGRATION_BRANCH"; then
      echo "aind: clean rebase — no conflicts. Now run: push  (it force-with-leases the rewritten history)"
    else
      echo "aind: REBASE CONFLICT on PR #$R_NUM — resolve these files, then 'git add' them and 'git rebase --continue':" >&2
      git diff --name-only --diff-filter=U | sed 's/^/  - /' >&2
      echo "aind: when 'git rebase --continue' reports the rebase complete, run: push  (do NOT 'git rebase --abort' unless you are giving up on the resolution)" >&2
      exit 3
    fi
    ;;

  push)
    SUMMARY="${3:-}"
    if bash "$SCRIPT_DIR/aind-worktree.sh" enabled >/dev/null 2>&1; then
      WT="$(bash "$SCRIPT_DIR/aind-worktree.sh" path "$ID" impl)"
      [[ -f "$WT/.git" ]] || aind_die "implement worktree $WT missing — run 'begin' first"
      cd "$WT"
    fi
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
    [[ -n "$branch" && "$branch" != "HEAD" ]] || aind_die "not on a branch — run 'begin' first to check out the code PR branch"
    # Refresh the remote-tracking ref, then choose the push mode. If the remote branch is no longer an
    # ancestor of HEAD, a rebase (to resolve a conflict) rewrote history and a plain push would be
    # rejected non-fast-forward — force safely with --force-with-lease (refuses if origin moved since
    # this fetch). Otherwise a normal fast-forward push.
    git fetch origin "$branch" --quiet 2>/dev/null || true
    if git rev-parse --verify -q "origin/$branch" >/dev/null 2>&1 \
       && ! git merge-base --is-ancestor "origin/$branch" HEAD 2>/dev/null; then
      git push origin "$branch" --force-with-lease --quiet
    else
      git push origin "$branch" --quiet
    fi
    if [[ -n "$SUMMARY" ]]; then
      rc=0; resolve_open "" || rc=$?
      if [[ "$rc" -eq 0 ]]; then
        SUMMARY="${SUMMARY}$(aind_pr_signature coder)"   # revise mode is always the warm coder
        _tmp="$(mktemp)"; printf '%s\n' "$SUMMARY" > "$_tmp"
        forge_comment "$R_NUM" "$_tmp"; rm -f "$_tmp"
      else
        echo "aind: [WARN] pushed, but could not resolve a single open PR to post the summary comment — skipped" >&2
      fi
    fi
    echo "aind: revised code pushed to branch $branch${R_URL:+ (PR $R_URL)}"
    ;;

  deviation)
    DPR="${3:-}"; CITE="${4:-}"; TEXT="${5:-}"
    [[ -n "$DPR" && -n "$CITE" && -n "$TEXT" ]] \
      || aind_die "usage: aind-revise-code-pr.sh <id> deviation <pr> <human-cite> <text>  (cite = thread=<id> or a ref to the human's PR comment)"
    [[ "$DPR" =~ ^[0-9]+$ ]] || aind_die "pr-number must be numeric, got '$DPR'"
    START='<!-- AIND-DEVIATIONS:START -->'
    END='<!-- AIND-DEVIATIONS:END -->'
    body="$(forge_pr_field "$DPR" body 2>/dev/null | tr -d '\r')" \
      || aind_die "could not read PR #$DPR body"
    line="- ${TEXT} (human: ${CITE})"
    if printf '%s' "$body" | grep -qF "$START"; then
      # Block exists — insert the new line immediately before the END marker.
      new="$(printf '%s' "$body" | awk -v ln="$line" -v end="$END" '$0==end{print ln} {print}')"
    else
      # No block yet — append a fresh one.
      new="$(printf '%s\n\n## Directed deviations\n<!-- Human-directed changes on this PR, each citing the human thread/comment that authorised it. The reviewer treats these as authoritative addenda to the merged plan. -->\n%s\n%s\n%s\n' \
        "$body" "$START" "$line" "$END")"
    fi
    tmp="$(mktemp)"; printf '%s\n' "$new" > "$tmp"
    forge_pr_edit_body "$DPR" "$tmp" \
      || { rm -f "$tmp"; aind_die "could not update PR #$DPR body with the deviation"; }
    rm -f "$tmp"
    echo "aind: recorded directed deviation on PR #$DPR (cite: $CITE)"
    ;;

  *)
    aind_die "unknown phase '$PHASE' (use: status | begin | rebase | push | deviation)"
    ;;
esac
