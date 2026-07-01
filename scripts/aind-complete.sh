#!/usr/bin/env bash
# aind-complete.sh verify  <work-item-id> [pr-number]
# aind-complete.sh cleanup <work-item-id> <pr-number>
#
# Build-phase close-out mechanics (the GitHub-flow twin of aind-revise-plan-pr.sh's cleanup, for the
# code PR). Human-gated: the person merges the code PR in GitHub; this script only CONFIRMS the merge
# and tidies up — it never merges anything itself.
#
#   verify  : resolve the story's code PR and confirm it is MERGED. On success prints ONE line:
#               <pr-number> <pr-url> <head-ref> <merge-commit-sha>
#             and exits 0. Otherwise it refuses (nonzero) with the fix to take. The code branch is
#             coder-generated and never reconstructed, so the PR is found by SEARCH on the work-item
#             id — matched against this flow's own markers (a title ending "(AB#<id>)", or an
#             AIND-LINKS work-item URL ending "/edit/<id>") — requiring exactly one MERGED match. An
#             explicit [pr-number] skips the search (the caller vouches for identity). Refuses on:
#             no match, a match that is not MERGED ("merge it first"), or >1 MERGED match (ambiguous).
#
#   cleanup : post-merge hygiene. Re-confirms PR #<pr-number> is MERGED, then tidies its head branch:
#             deletes the remote branch IF it still exists (a no-op when the merge auto-deleted it),
#             prunes the stale origin/<head-ref> ref, and deletes the LOCAL branch — switching to the
#             integration branch first if that branch is checked out AND the working tree is clean
#             (never stashes/discards; a dirty tree is left for the human). Finally, if we end up on
#             the integration branch with a clean tree, fast-forwards it to include the merge (ff-only;
#             a diverged local branch is left for a manual pull). Idempotent.
#
# Usage:
#   aind-complete.sh verify  123
#   aind-complete.sh verify  123 45
#   aind-complete.sh cleanup 123 45

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

MODE="${1:-}"
ID="${2:-}"
[[ -n "$MODE" && -n "$ID" ]] || aind_die "usage: aind-complete.sh verify|cleanup <work-item-id> [pr-number]"
[[ "$ID" =~ ^[0-9]+$ ]] || aind_die "work-item id must be numeric, got '$ID'"
aind_require_env AIND_GH_REPO
aind_require_cmd gh

# Print "<number> <url> <head-ref>" for PR <n>, only if it is MERGED; otherwise die with its state.
# Used by the explicit-[pr-number] path and re-used by cleanup's merge re-confirmation.
merged_pr_line() {
  local n="$1" line state
  line="$(gh pr view "$n" --repo "$AIND_GH_REPO" --json number,url,state,headRefName \
    --jq '[(.number|tostring),.url,.headRefName,.state] | @tsv' 2>/dev/null)" \
    || aind_die "could not read PR #$n from $AIND_GH_REPO (does it exist?)"
  state="$(printf '%s' "$line" | cut -f4)"
  [[ "$state" == "MERGED" ]] \
    || aind_die "PR #$n is '$state', not MERGED — merge the code PR first, then re-run"
  printf '%s' "$line" | cut -f1-3    # number \t url \t head-ref
}

case "$MODE" in
  verify)
    PR="${3:-}"
    if [[ -n "$PR" ]]; then
      [[ "$PR" =~ ^[0-9]+$ ]] || aind_die "pr-number must be numeric, got '$PR'"
      read -r num url head < <(merged_pr_line "$PR")   # dies unless MERGED
    else
      # Resolve by marker-search (shared helper), then require a single MERGED match.
      cands="$(aind_find_code_prs "$ID")"
      [[ -n "${cands//[$'\n\t ']/}" ]] \
        || aind_die "no code PR found for AB#$ID in $AIND_GH_REPO — pass the PR number explicitly: aind-complete.sh verify $ID <pr>"
      merged="$(printf '%s\n' "$cands" | awk -F'\t' '$1=="MERGED"')"
      mcount="$(printf '%s\n' "$merged" | awk 'NF{c++} END{print c+0}')"
      if (( mcount == 0 )); then
        aind_die $'a code PR for AB#'"$ID"$' exists but is not MERGED — merge it first, then re-run:\n'"$(printf '%s\n' "$cands" | awk -F'\t' 'NF{printf "  #%s [%s] %s\n",$2,$1,$3}')"
      elif (( mcount > 1 )); then
        aind_die $'more than one MERGED PR matches AB#'"$ID"$' — pass the PR number explicitly (aind-complete.sh verify '"$ID"$' <pr>):\n'"$(printf '%s\n' "$merged" | awk -F'\t' 'NF{printf "  #%s %s\n",$2,$3}')"
      fi
      IFS=$'\t' read -r _ num url head <<< "$merged"
    fi

    # Authoritative merge-commit SHA for the completion note (empty if the field is unavailable).
    sha="$(gh pr view "$num" --repo "$AIND_GH_REPO" --json mergeCommit --jq '.mergeCommit.oid // ""' 2>/dev/null || true)"
    printf '%s %s %s %s\n' "$num" "$url" "$head" "$sha"
    ;;

  cleanup)
    PR="${3:-}"
    [[ -n "$PR" ]] || aind_die "usage: aind-complete.sh cleanup <work-item-id> <pr-number>"
    [[ "$PR" =~ ^[0-9]+$ ]] || aind_die "pr-number must be numeric, got '$PR'"
    aind_require_env AIND_INTEGRATION_BRANCH
    aind_require_cmd git

    read -r num url head < <(merged_pr_line "$PR")     # dies unless MERGED
    echo "aind: PR #$num is MERGED — cleaning up code branch $head"

    # Remote: delete only if it still exists (merge usually auto-deletes it — then this is a no-op).
    if git ls-remote --exit-code --heads origin "$head" >/dev/null 2>&1; then
      git push origin --delete "$head" --quiet && echo "aind: deleted remote branch $head" \
        || echo "aind: could not delete remote branch $head (check permissions) — skipped"
    else
      echo "aind: remote branch $head already gone (auto-deleted on merge) — skipped"
    fi

    # Prune the now-stale remote-tracking ref so origin/$head doesn't dangle.
    git fetch origin --prune --quiet 2>/dev/null || true

    # Local: the dev's copy of the code branch usually lingers from the implement run.
    if git show-ref --verify --quiet "refs/heads/$head"; then
      current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
      if [[ "$current" == "$head" ]]; then
        if git diff --quiet && git diff --cached --quiet; then
          git checkout "$AIND_INTEGRATION_BRANCH" >/dev/null 2>&1 \
            || git checkout -B "$AIND_INTEGRATION_BRANCH" "origin/$AIND_INTEGRATION_BRANCH" >/dev/null 2>&1 \
            || aind_die "could not switch to $AIND_INTEGRATION_BRANCH — switch away, then 'git branch -D $head' manually"
          git branch -D "$head" >/dev/null 2>&1 && echo "aind: switched to $AIND_INTEGRATION_BRANCH and deleted local branch $head"
        else
          echo "aind: local branch $head is checked out with uncommitted changes — commit/stash, switch away, then 'git branch -D $head' manually"
        fi
      else
        git branch -D "$head" >/dev/null 2>&1 && echo "aind: deleted local branch $head" || true
      fi
    else
      echo "aind: no local branch $head — nothing to clean up locally"
    fi

    # Leave the developer on an up-to-date integration branch: if we're now on it (we switched here
    # above, or you were already on it) and the tree is clean, fast-forward it to include the merge
    # (origin/<integration> is current from the prune fetch above). Fast-forward ONLY — if the local
    # branch has diverged, warn and leave it for a manual pull rather than creating a merge.
    current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
    if [[ "$current" == "$AIND_INTEGRATION_BRANCH" ]]; then
      if git diff --quiet && git diff --cached --quiet; then
        if git merge --ff-only "origin/$AIND_INTEGRATION_BRANCH" >/dev/null 2>&1; then
          echo "aind: fast-forwarded $AIND_INTEGRATION_BRANCH to include the merge"
        else
          echo "aind: [WARN] could not fast-forward $AIND_INTEGRATION_BRANCH (local commits diverge?) — pull manually" >&2
        fi
      else
        echo "aind: working tree not clean — skipped updating $AIND_INTEGRATION_BRANCH (pull manually)"
      fi
    else
      echo "aind: on '$current' (not $AIND_INTEGRATION_BRANCH) — skipped updating the integration branch"
    fi
    ;;

  *)
    aind_die "usage: aind-complete.sh verify|cleanup <work-item-id> [pr-number]"
    ;;
esac
