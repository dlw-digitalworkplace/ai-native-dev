#!/usr/bin/env bash
# aind-review-pr.sh <phase> <pr-number> [args]
# PR-review mechanics for the build-phase code reviewer. The cold reviewer subagent and the warm
# coder both drive the code PR through this one script, so a fresh subagent context is covered by
# the project's single Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/*) allow-rule and is not re-prompted
# per raw `gh` call.
#
# Phases:
#   fetch  <pr>                     Re-ground in ONE call: print the PR title, body, the parsed
#                                   AIND-LINKS block (work-item URL, plan path, plan-PR URL), the PR's
#                                   MERGEABILITY against the integration branch, and the full diff.
#                                   Keeps the reviewer off raw `gh pr view/diff`.
#   mergeability <pr>               Print MERGEABILITY: MERGEABLE|CONFLICTING|UNKNOWN — whether the PR
#                                   head merges cleanly into the integration branch. Both hosts compute
#                                   this asynchronously, so this polls briefly while UNKNOWN before
#                                   giving up (a transient UNKNOWN is not a conflict). When CONFLICTING
#                                   it also prints INTEGRATION-BRANCH: <name> so the coder knows what to
#                                   rebase onto. A pure read — no checkout, so the cold reviewer stays
#                                   read-only (resolving the conflict is the coder's job).
#   digest <pr>                     Print every review thread (each tagged [OPEN]/[RESOLVED] with its
#                                   file:line and thread=<node-id>) plus top-level PR comments — what
#                                   a re-pass reviewer and the coder read to see prior findings and
#                                   rebuttals. Reuses gh's built-in --jq (no external jq needed).
#   summary <pr> <agent> [body]     Post the review summary as a top-level PR comment (the overall
#                                   verdict + the non-blocking SUGGESTION list), signed by <agent>.
#                                   Body via arg or stdin. A plain comment — NOT a GitHub "approve"
#                                   review, because in local mode the reviewer runs as the same user
#                                   as the coder and GitHub refuses a self-approval; loop termination
#                                   is driven by the reviewer's returned verdict, not GitHub review state.
#   thread <pr> <path> <line> <agent> [body]  Post ONE resolvable inline review thread for a blocking
#                                   (CRITICAL/WARNING) finding, anchored to file:line, signed by
#                                   <agent>. Delegates to aind-thread.sh (shared head-SHA anchoring +
#                                   signing). Body via arg or stdin.
#   resolve <pr> <thread-id>        Mark a review thread resolved (the reviewer, on a re-pass, when
#                                   the coder addressed it). <thread-id> is the thread=<node-id> from
#                                   `digest`.
#   reply  <pr> <thread-id> <agent> [body]  Reply on a review thread — the coder's rebuttal, or a
#                                   reviewer note — signed by <agent>. Body via arg or stdin. Does NOT
#                                   resolve the thread.
#
# Every posted comment/thread/reply is signed with the agent name (aind_pr_signature), so a PR
# comment is attributed to its author even though the coder and reviewer share one GitHub identity.
#
# The <pr> argument is kept on every phase for a uniform interface even where the underlying GraphQL
# needs only the thread id. The reviewer never checks out or pushes anything — it reports only.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-forge.sh
source "$SCRIPT_DIR/aind-forge.sh"

PHASE="${1:-}"
PR="${2:-}"
[[ -n "$PHASE" && -n "$PR" ]] \
  || aind_die "usage: aind-review-pr.sh <fetch|mergeability|digest|summary|thread|resolve|reply> <pr-number> [args]"
forge_require

# Read the PR's mergeability against the integration branch as one canonical token. With "poll",
# retry while UNKNOWN (both hosts compute it asynchronously — e.g. right after a push — so a single
# UNKNOWN is "not ready yet", not a verdict). Echoes MERGEABLE | CONFLICTING | UNKNOWN.
read_mergeability() {
  local poll="${1:-}" v i
  v="$(forge_pr_mergeable "$PR")"
  if [[ "$poll" == "poll" ]]; then
    for i in 1 2 3 4; do
      [[ "$v" != "UNKNOWN" ]] && break
      sleep 2
      v="$(forge_pr_mergeable "$PR")"
    done
  fi
  echo "$v"
}

# Print all review threads (state, opaque id, file:line, comments) then top-level PR comments.
print_digest() {
  echo "--- Review threads (blocking findings + replies) ---"
  forge_thread_list "$PR"
  echo
  echo "--- Top-level PR comments ---"
  forge_comment_list "$PR"
}

case "$PHASE" in
  fetch)
    title="$(forge_pr_field "$PR" title)"
    body="$(forge_pr_field "$PR" body)"
    echo "===== PR #$PR — $title ====="
    echo "--- BODY ---"
    printf '%s\n' "$body"
    echo
    echo "--- AIND-LINKS ---"
    printf '%s\n' "$body" | bash "$SCRIPT_DIR/aind-links.sh" parse
    echo
    echo "--- MERGEABILITY ---"
    merge="$(read_mergeability)"   # quick read; the `mergeability` phase polls if you need it settled
    echo "MERGEABILITY: $merge"
    [[ "$merge" == "CONFLICTING" && -n "${AIND_INTEGRATION_BRANCH:-}" ]] \
      && echo "INTEGRATION-BRANCH: $AIND_INTEGRATION_BRANCH"
    echo
    echo "--- DIFF ---"
    forge_pr_diff "$PR"
    echo "====================================================================================="
    ;;

  mergeability)
    merge="$(read_mergeability poll)"
    echo "MERGEABILITY: $merge"
    [[ "$merge" == "CONFLICTING" && -n "${AIND_INTEGRATION_BRANCH:-}" ]] \
      && echo "INTEGRATION-BRANCH: $AIND_INTEGRATION_BRANCH"
    ;;

  digest)
    echo "===== CODE-PR REVIEW STATE — PR #$PR ====="
    print_digest
    echo "========================================="
    ;;

  summary)
    AGENT="${3:-}"
    [[ -n "$AGENT" ]] || aind_die "usage: aind-review-pr.sh summary <pr> <agent> [body]  (body via arg or stdin)"
    BODY="${4:-}"
    [[ -n "$BODY" ]] || BODY="$(cat)"
    [[ -n "$BODY" ]] || aind_die "empty summary body"
    BODY="${BODY}$(aind_pr_signature "$AGENT")"
    _tmp="$(mktemp)"; printf '%s\n' "$BODY" > "$_tmp"
    forge_comment "$PR" "$_tmp"; rm -f "$_tmp"
    echo "aind: posted signed $AGENT review summary comment on PR #$PR"
    ;;

  thread)
    P="${3:-}"; L="${4:-}"; AGENT="${5:-}"
    [[ -n "$P" && -n "$L" && -n "$AGENT" ]] \
      || aind_die "usage: aind-review-pr.sh thread <pr> <path> <line> <agent> [body]  (body via arg or stdin)"
    if [[ $# -ge 6 ]]; then
      exec bash "$SCRIPT_DIR/aind-thread.sh" "$PR" "$P" "$L" "$AGENT" "$6"
    else
      exec bash "$SCRIPT_DIR/aind-thread.sh" "$PR" "$P" "$L" "$AGENT"
    fi
    ;;

  resolve)
    TID="${3:-}"
    [[ -n "$TID" ]] || aind_die "usage: aind-review-pr.sh resolve <pr> <thread-id>  (thread-id = thread=<id> from digest)"
    forge_resolve "$PR" "$TID"
    echo "aind: resolved review thread $TID on PR #$PR"
    ;;

  reply)
    TID="${3:-}"
    [[ -n "$TID" ]] || aind_die "usage: aind-review-pr.sh reply <pr> <thread-id> <agent> [body]  (body via arg or stdin)"
    AGENT="${4:-}"
    [[ -n "$AGENT" ]] || aind_die "usage: aind-review-pr.sh reply <pr> <thread-id> <agent> [body]  (body via arg or stdin)"
    BODY="${5:-}"
    [[ -n "$BODY" ]] || BODY="$(cat)"
    [[ -n "$BODY" ]] || aind_die "empty reply body"
    BODY="${BODY}$(aind_pr_signature "$AGENT")"
    _tmp="$(mktemp)"; printf '%s\n' "$BODY" > "$_tmp"
    forge_reply "$PR" "$TID" "$_tmp"; rm -f "$_tmp"
    echo "aind: posted signed $AGENT reply to thread $TID on PR #$PR (not resolved)"
    ;;

  *)
    aind_die "unknown phase '$PHASE' (use: fetch | mergeability | digest | summary | thread | resolve | reply)"
    ;;
esac
