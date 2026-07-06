#!/usr/bin/env bash
# aind-review-pr.sh <phase> <pr-number> [args]
# PR-review mechanics for the build-phase code reviewer. The cold reviewer subagent and the warm
# coder both drive the code PR through this one script, so a fresh subagent context is covered by
# the project's single Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/*) allow-rule and is not re-prompted
# per raw `gh` call.
#
# Phases:
#   fetch  <pr>                     Re-ground in ONE call: print the PR title, body, the parsed
#                                   AIND-LINKS block (work-item URL, plan path, plan-PR URL), and the
#                                   full diff. Keeps the reviewer off raw `gh pr view/diff`.
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
# Every posted comment/thread/reply is signed with the agent name (aind_gh_signature), so a PR
# comment is attributed to its author even though the coder and reviewer share one GitHub identity.
#
# The <pr> argument is kept on every phase for a uniform interface even where the underlying GraphQL
# needs only the thread id. The reviewer never checks out or pushes anything — it reports only.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

PHASE="${1:-}"
PR="${2:-}"
[[ -n "$PHASE" && -n "$PR" ]] \
  || aind_die "usage: aind-review-pr.sh <fetch|digest|summary|thread|resolve|reply> <pr-number> [args]"
aind_require_env AIND_GH_REPO
aind_require_cmd gh

# Print all review threads (state, node id, file:line, comments) then top-level PR comments.
print_digest() {
  local owner="${AIND_GH_REPO%%/*}" repo="${AIND_GH_REPO##*/}"
  echo "--- Review threads (blocking findings + replies) ---"
  gh api graphql -f owner="$owner" -f repo="$repo" -F pr="$PR" -f query='
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
  echo "--- Top-level PR comments ---"
  gh pr view "$PR" --repo "$AIND_GH_REPO" --json comments \
    --jq '.comments[] | "[\(.author.login)] \(.body)"' 2>/dev/null || true
}

case "$PHASE" in
  fetch)
    title="$(gh pr view "$PR" --repo "$AIND_GH_REPO" --json title --jq .title)"
    body="$(gh pr view "$PR" --repo "$AIND_GH_REPO" --json body --jq .body)"
    echo "===== PR #$PR — $title ====="
    echo "--- BODY ---"
    printf '%s\n' "$body"
    echo
    echo "--- AIND-LINKS ---"
    printf '%s\n' "$body" | bash "$SCRIPT_DIR/aind-links.sh" parse
    echo
    echo "--- DIFF ---"
    gh pr diff "$PR" --repo "$AIND_GH_REPO"
    echo "====================================================================================="
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
    BODY="${BODY}$(aind_gh_signature "$AGENT")"
    printf '%s\n' "$BODY" | gh pr comment "$PR" --repo "$AIND_GH_REPO" --body-file -
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
    gh api graphql -f threadId="$TID" -f query='
      mutation($threadId:ID!){
        resolveReviewThread(input:{threadId:$threadId}){ thread{ isResolved } }
      }' --jq '.data.resolveReviewThread.thread.isResolved' >/dev/null
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
    BODY="${BODY}$(aind_gh_signature "$AGENT")"
    gh api graphql -f threadId="$TID" -f body="$BODY" -f query='
      mutation($threadId:ID!,$body:String!){
        addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId, body:$body}){
          comment{ url }
        }
      }' --jq '.data.addPullRequestReviewThreadReply.comment.url'
    echo "aind: posted signed $AGENT reply to thread $TID on PR #$PR (not resolved)"
    ;;

  *)
    aind_die "unknown phase '$PHASE' (use: fetch | digest | summary | thread | resolve | reply)"
    ;;
esac
