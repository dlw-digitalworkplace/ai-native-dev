#!/usr/bin/env bash
# aind-forge.sh — the code-host ("forge") adapter. Sourced by the PR scripts; not run directly.
#
# WHY THIS EXISTS
# The AIND flow stores its plan/code in git and reviews it in pull requests. Git is host-neutral
# (Azure DevOps Repos is plain git), so every git operation the flow performs works against either
# host unchanged. The ONLY host-specific layer is the PR/comment API — creating PRs, listing them,
# posting resolvable review threads, resolving/replying. This file is that layer: one set of
# host-agnostic verbs that dispatch on AIND_CODE_HOST to a GitHub (`_gh_*`) or Azure DevOps
# (`_ado_*`) implementation. Every PR script becomes a thin caller of these verbs, so commands,
# skills, and agents never learn which host they run on.
#
#   AIND_CODE_HOST   github (default) | ado
#   github path uses:  AIND_GH_REPO (owner/repo)              + the `gh` CLI
#   ado    path uses:  AIND_ADO_ORG + AIND_ADO_PROJECT +
#                      AIND_ADO_REPO + AZURE_DEVOPS_EXT_PAT   + `az repos` and the ADO REST API
#
# CANONICAL VOCABULARY (both hosts normalise to this, so callers are host-blind):
#   PR state     : OPEN | MERGED | CLOSED       (GitHub already uses these; ADO maps
#                                                active->OPEN, completed->MERGED, abandoned->CLOSED)
#   thread state : [OPEN] | [RESOLVED]          (GitHub isResolved; ADO active/pending->OPEN, else RESOLVED)
#   thread token : an OPAQUE string `thread=<id>` — a GitHub GraphQL node id OR an ADO threadId.
#                  Callers pass it back verbatim to forge_resolve/forge_reply; they never parse it.
#
# SPIKE (validate live on a real ADO PR, then adjust here — see implementation-plan-ado-code-host.md):
#   - Whether ADO PR markdown preserves HTML comments decides the signature marker (aind_pr_signature)
#     and the AIND-LINKS carrier (aind-links.sh). The ADO defaults below use the display:none span
#     proven for ADO work-item fields; flip to an HTML comment if the spike shows ADO preserves them.
#   - Inline anchoring uses rightFileStart/End line with offset 1; adjust if the spike needs offsets.
#   - forge_resolve marks ADO threads "fixed"; confirm that satisfies the "resolve before merge" policy.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

# ------------------------------------------------------------------------------------------------
# Host selection, config validation, signing
# ------------------------------------------------------------------------------------------------

aind_code_host() { echo "${AIND_CODE_HOST:-github}"; }

# Validate the config + tools the selected host needs. Call once, after sourcing, in each PR script.
forge_require() {
  case "$(aind_code_host)" in
    github) aind_require_env AIND_GH_REPO; aind_require_cmd gh ;;
    ado)    aind_require_env AIND_ADO_ORG AIND_ADO_PROJECT AIND_ADO_REPO AZURE_DEVOPS_EXT_PAT
            aind_require_cmd az curl jq ;;
    *) aind_die "unknown AIND_CODE_HOST '$(aind_code_host)' (use: github | ado)" ;;
  esac
}

# Agent signature for PR comments/threads/replies. Same intent + greppable "AIND-AGENT: <name>"
# contract on both hosts; only the machine-marker carrier differs by host. Callers append the
# returned string to a comment body before posting, exactly as before.
aind_pr_signature() {
  local agent="$1"
  [[ -n "$agent" ]] || aind_die "aind_pr_signature: missing agent name"
  local actor; actor="$(aind_actor)"
  case "$(aind_code_host)" in
    ado)
      # ADO PR comments render markdown and may sanitize HTML comments (SPIKE 7.1). Default to the
      # display:none span proven for ADO work-item fields; still greppable, invisible if honoured.
      printf '\n\n— 🤖 AIND %s Agent (run by %s)<span style="display:none">AIND-AGENT: %s</span>' \
        "${agent^}" "$actor" "$agent"
      ;;
    *)
      # GitHub renders markdown and preserves HTML comments — invisible, greppable.
      printf '\n\n— 🤖 AIND %s Agent (run by %s)\n<!-- AIND-AGENT: %s -->' \
        "${agent^}" "$actor" "$agent"
      ;;
  esac
}

# ------------------------------------------------------------------------------------------------
# ADO REST plumbing (reuses AZURE_DEVOPS_EXT_PAT; UTF-8-safe body-from-file, like aind-comment.sh)
# ------------------------------------------------------------------------------------------------

_ado_base()   { echo "${AIND_ADO_ORG%/}/${AIND_ADO_PROJECT}/_apis/git/repositories/${AIND_ADO_REPO}"; }
_ado_web_pr() { echo "${AIND_ADO_ORG%/}/${AIND_ADO_PROJECT}/_git/${AIND_ADO_REPO}/pullrequest/$1"; }

# _ado_api <METHOD> <url> [json-body-file] -> prints response body; dies with ADO's .message on non-2xx.
# The body goes via --data-binary @file (not an inline -d) so multibyte UTF-8 survives Windows/MSYS.
_ado_api() {
  local method="$1" url="$2" bodyfile="${3:-}" resp code out msg
  local args=(-s -w $'\n%{http_code}' -u ":${AZURE_DEVOPS_EXT_PAT}" -X "$method"
              -H "Content-Type: application/json; charset=utf-8" "$url")
  [[ -n "$bodyfile" ]] && args+=(--data-binary @"$bodyfile")
  resp="$(curl "${args[@]}")" || aind_die "ADO API $method $url: network/curl error"
  code="${resp##*$'\n'}"; out="${resp%$'\n'*}"
  if [[ "$code" != 2* ]]; then
    msg="$(printf '%s' "$out" | jq -r '.message // empty' 2>/dev/null)"
    aind_die "ADO API $method failed (HTTP $code)${msg:+: $msg}"
  fi
  printf '%s' "$out"
}

# ------------------------------------------------------------------------------------------------
# forge_pr_create <base> <head> <title> <body-file> [work-item-id] -> prints PR URL
# ------------------------------------------------------------------------------------------------
_gh_pr_create() {
  # work-item id (5th arg) is intentionally unused on GitHub — AB#<id> in the title/body drives the
  # native Azure Boards<->GitHub link.
  gh pr create --repo "$AIND_GH_REPO" --base "$1" --head "$2" --title "$3" --body-file "$4"
}
_ado_pr_create() {
  local base="$1" head="$2" title="$3" bodyfile="$4" wi="${5:-}" payload resp prid
  payload="$(mktemp)"
  jq -Rs --arg s "refs/heads/$head" --arg t "refs/heads/$base" --arg title "$title" \
    '{sourceRefName:$s, targetRefName:$t, title:$title, description:.}' < "$bodyfile" > "$payload"
  resp="$(_ado_api POST "$(_ado_base)/pullrequests?api-version=7.1" "$payload")"
  rm -f "$payload"
  prid="$(printf '%s' "$resp" | jq -r '.pullRequestId // empty')"
  [[ -n "$prid" ]] || aind_die "ADO PR create: no pullRequestId in response"
  if [[ -n "$wi" ]]; then
    # Native ADO work-item link (same platform — no Boards<->GitHub app needed).
    az repos pr work-item add --id "$prid" --work-items "$wi" --org "$AIND_ADO_ORG" >/dev/null 2>&1 \
      || echo "aind: [WARN] could not link work item $wi to PR $prid — link it manually in ADO" >&2
  fi
  _ado_web_pr "$prid"
}
forge_pr_create() { case "$(aind_code_host)" in ado) _ado_pr_create "$@";; *) _gh_pr_create "$@";; esac; }

# ------------------------------------------------------------------------------------------------
# forge_pr_list <state> [head]  -> TSV rows: state \t number \t url \t head \t title \t body
#   state = open | merged | closed | all   (@tsv escapes newlines/tabs, so each PR is exactly one row)
# ------------------------------------------------------------------------------------------------
_gh_pr_list() {
  local st="$1" head="${2:-}"
  local args=(--repo "$AIND_GH_REPO" --state "$st" --limit 200
              --json number,title,url,state,headRefName,body)
  [[ -n "$head" ]] && args+=(--head "$head")
  gh pr list "${args[@]}" \
    --jq '.[] | [.state,(.number|tostring),.url,.headRefName,.title,.body] | @tsv'
}
_ado_pr_list() {
  local st="$1" head="${2:-}" status url
  case "$st" in open) status=active;; merged) status=completed;; closed) status=abandoned;; *) status=all;; esac
  url="$(_ado_base)/pullrequests?searchCriteria.status=${status}&\$top=200&api-version=7.1"
  [[ -n "$head" ]] && url="${url}&searchCriteria.sourceRefName=refs/heads/${head}"
  _ado_api GET "$url" | jq -r --arg org "${AIND_ADO_ORG%/}" --arg proj "$AIND_ADO_PROJECT" --arg repo "$AIND_ADO_REPO" '
    .value[]
    | [ (if .status=="active" then "OPEN" elif .status=="completed" then "MERGED"
         elif .status=="abandoned" then "CLOSED" else (.status|ascii_upcase) end),
        (.pullRequestId|tostring),
        ($org + "/" + $proj + "/_git/" + $repo + "/pullrequest/" + (.pullRequestId|tostring)),
        (.sourceRefName|ltrimstr("refs/heads/")),
        (.title // ""),
        (.description // "") ]
    | @tsv'
}
forge_pr_list() { case "$(aind_code_host)" in ado) _ado_pr_list "$@";; *) _gh_pr_list "$@";; esac; }

# ------------------------------------------------------------------------------------------------
# forge_pr_meta <pr>  -> TSV: number \t url \t head \t state
# ------------------------------------------------------------------------------------------------
_gh_pr_meta() {
  gh pr view "$1" --repo "$AIND_GH_REPO" --json number,url,headRefName,state \
    --jq '[(.number|tostring),.url,.headRefName,.state] | @tsv'
}
_ado_pr_meta() {
  _ado_api GET "$(_ado_base)/pullrequests/$1?api-version=7.1" \
    | jq -r --arg web "$(_ado_web_pr "$1")" '
      [(.pullRequestId|tostring), $web, (.sourceRefName|ltrimstr("refs/heads/")),
       (if .status=="active" then "OPEN" elif .status=="completed" then "MERGED"
        elif .status=="abandoned" then "CLOSED" else (.status|ascii_upcase) end)] | @tsv'
}
forge_pr_meta() { case "$(aind_code_host)" in ado) _ado_pr_meta "$@";; *) _gh_pr_meta "$@";; esac; }

# ------------------------------------------------------------------------------------------------
# forge_pr_field <pr> <title|body|headsha|mergecommit>  -> the single value
# ------------------------------------------------------------------------------------------------
_gh_pr_field() {
  case "$2" in
    title)       gh pr view "$1" --repo "$AIND_GH_REPO" --json title --jq '.title' ;;
    body)        gh pr view "$1" --repo "$AIND_GH_REPO" --json body  --jq '.body' ;;
    headsha)     gh pr view "$1" --repo "$AIND_GH_REPO" --json headRefOid -q '.headRefOid' ;;
    mergecommit) gh pr view "$1" --repo "$AIND_GH_REPO" --json mergeCommit --jq '.mergeCommit.oid // ""' ;;
    *) aind_die "forge_pr_field: unknown field '$2'" ;;
  esac
}
_ado_pr_field() {
  local j; j="$(_ado_api GET "$(_ado_base)/pullrequests/$1?api-version=7.1")"
  case "$2" in
    title)       printf '%s' "$j" | jq -r '.title // ""' ;;
    body)        printf '%s' "$j" | jq -r '.description // ""' ;;
    headsha)     printf '%s' "$j" | jq -r '.lastMergeSourceCommit.commitId // ""' ;;
    mergecommit) printf '%s' "$j" | jq -r '.lastMergeCommit.commitId // ""' ;;
    *) aind_die "forge_pr_field: unknown field '$2'" ;;
  esac
}
forge_pr_field() { case "$(aind_code_host)" in ado) _ado_pr_field "$@";; *) _gh_pr_field "$@";; esac; }

# ------------------------------------------------------------------------------------------------
# forge_pr_diff <pr>  -> unified diff on stdout
# ------------------------------------------------------------------------------------------------
_gh_pr_diff() { gh pr diff "$1" --repo "$AIND_GH_REPO"; }
_ado_pr_diff() {
  # az repos pr has no clean diff; compute it locally against origin (which points at the ADO repo).
  local j src tgt
  j="$(_ado_api GET "$(_ado_base)/pullrequests/$1?api-version=7.1")"
  src="$(printf '%s' "$j" | jq -r '.sourceRefName|ltrimstr("refs/heads/")')"
  tgt="$(printf '%s' "$j" | jq -r '.targetRefName|ltrimstr("refs/heads/")')"
  git fetch origin "$src" "$tgt" --quiet 2>/dev/null || true
  git diff "origin/${tgt}...origin/${src}"
}
forge_pr_diff() { case "$(aind_code_host)" in ado) _ado_pr_diff "$@";; *) _gh_pr_diff "$@";; esac; }

# ------------------------------------------------------------------------------------------------
# forge_pr_edit_body <pr> <body-file>  -> replaces the PR body/description
# ------------------------------------------------------------------------------------------------
_gh_pr_edit_body() { gh pr edit "$1" --repo "$AIND_GH_REPO" --body-file "$2" >/dev/null; }
_ado_pr_edit_body() {
  local payload; payload="$(mktemp)"
  jq -Rs '{description:.}' < "$2" > "$payload"
  _ado_api PATCH "$(_ado_base)/pullrequests/$1?api-version=7.1" "$payload" >/dev/null
  rm -f "$payload"
}
forge_pr_edit_body() { case "$(aind_code_host)" in ado) _ado_pr_edit_body "$@";; *) _gh_pr_edit_body "$@";; esac; }

# ------------------------------------------------------------------------------------------------
# forge_comment <pr> <body-file>  -> posts a top-level PR comment (body already signed by caller)
# ------------------------------------------------------------------------------------------------
_gh_comment() { gh pr comment "$1" --repo "$AIND_GH_REPO" --body-file "$2"; }
_ado_comment() {
  # A general comment thread (no threadContext, no active status) — does NOT gate merge.
  local payload; payload="$(mktemp)"
  jq -Rs '{comments:[{parentCommentId:0,content:.,commentType:1}]}' < "$2" > "$payload"
  _ado_api POST "$(_ado_base)/pullRequests/$1/threads?api-version=7.1" "$payload" >/dev/null
  rm -f "$payload"
}
forge_comment() { case "$(aind_code_host)" in ado) _ado_comment "$@";; *) _gh_comment "$@";; esac; }

# ------------------------------------------------------------------------------------------------
# forge_comment_list <pr>  -> top-level PR comments, one per line: [author] body
# ------------------------------------------------------------------------------------------------
_gh_comment_list() {
  gh pr view "$1" --repo "$AIND_GH_REPO" --json comments \
    --jq '.comments[] | "[\(.author.login)] \(.body)"' 2>/dev/null || true
}
_ado_comment_list() {
  _ado_api GET "$(_ado_base)/pullRequests/$1/threads?api-version=7.1" 2>/dev/null \
    | jq -r '
      .value[]
      | select((.threadContext // null) == null)
      | .comments[]? | select(.commentType != "system")
      | "[" + (.author.displayName // "?") + "] " + (.content // "")' 2>/dev/null || true
}
forge_comment_list() { case "$(aind_code_host)" in ado) _ado_comment_list "$@";; *) _gh_comment_list "$@";; esac; }

# ------------------------------------------------------------------------------------------------
# forge_thread <pr> <path> <line> <body-file>  -> posts ONE resolvable inline thread (signed by caller)
# ------------------------------------------------------------------------------------------------
_gh_thread() {
  local pr="$1" path="$2" line="$3" bodyfile="$4" sha body
  sha="$(gh pr view "$pr" --repo "$AIND_GH_REPO" --json headRefOid -q .headRefOid)"
  [[ -n "$sha" ]] || aind_die "could not resolve head commit for PR $pr"
  body="$(cat "$bodyfile")"
  gh api "repos/${AIND_GH_REPO}/pulls/${pr}/comments" \
    -f body="$body" -f commit_id="$sha" -f path="$path" -F line="$line" -f side=RIGHT >/dev/null
}
_ado_thread() {
  local pr="$1" path="$2" line="$3" bodyfile="$4" payload
  payload="$(mktemp)"
  jq -Rs --arg p "/${path#/}" --argjson ln "$line" \
    '{comments:[{parentCommentId:0,content:.,commentType:1}], status:"active",
      threadContext:{filePath:$p, rightFileStart:{line:$ln,offset:1}, rightFileEnd:{line:$ln,offset:1}}}' \
    < "$bodyfile" > "$payload"
  _ado_api POST "$(_ado_base)/pullRequests/${pr}/threads?api-version=7.1" "$payload" \
    | jq -r '.id // empty'
  rm -f "$payload"
}
forge_thread() { case "$(aind_code_host)" in ado) _ado_thread "$@";; *) _gh_thread "$@";; esac; }

# ------------------------------------------------------------------------------------------------
# forge_thread_list <pr>  -> resolvable inline threads:
#   [OPEN]|[RESOLVED] thread=<opaque-id> <path>:<line>
#       <author>: <body>
# ------------------------------------------------------------------------------------------------
_gh_thread_list() {
  local pr="$1" owner="${AIND_GH_REPO%%/*}" repo="${AIND_GH_REPO##*/}"
  gh api graphql -f owner="$owner" -f repo="$repo" -F pr="$pr" -f query='
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
}
_ado_thread_list() {
  _ado_api GET "$(_ado_base)/pullRequests/$1/threads?api-version=7.1" 2>/dev/null \
    | jq -r '
      .value[]
      | select(.threadContext.filePath != null)
      | select([.comments[]?.commentType] | index("text") != null)
      | ((.status // "active") as $s
         | (if ($s=="active" or $s=="pending") then "[OPEN]" else "[RESOLVED]" end)) as $state
      | ($state + " thread=" + (.id|tostring) + " "
         + (.threadContext.filePath | ltrimstr("/")) + ":"
         + ((.threadContext.rightFileStart.line // "?")|tostring) + "\n"
         + ([.comments[] | select(.commentType != "system")
             | "    " + (.author.displayName // "?") + ": " + (.content // "")] | join("\n")))
      ' 2>/dev/null || echo "(could not read review threads)"
}
forge_thread_list() { case "$(aind_code_host)" in ado) _ado_thread_list "$@";; *) _gh_thread_list "$@";; esac; }

# ------------------------------------------------------------------------------------------------
# forge_resolve <pr> <thread-id>  -> marks the thread resolved
# ------------------------------------------------------------------------------------------------
_gh_resolve() {
  gh api graphql -f threadId="$2" -f query='
    mutation($threadId:ID!){
      resolveReviewThread(input:{threadId:$threadId}){ thread{ isResolved } }
    }' --jq '.data.resolveReviewThread.thread.isResolved' >/dev/null
}
_ado_resolve() {
  local payload; payload="$(mktemp)"; printf '{"status":"fixed"}' > "$payload"
  _ado_api PATCH "$(_ado_base)/pullRequests/$1/threads/$2?api-version=7.1" "$payload" >/dev/null
  rm -f "$payload"
}
forge_resolve() { case "$(aind_code_host)" in ado) _ado_resolve "$@";; *) _gh_resolve "$@";; esac; }

# ------------------------------------------------------------------------------------------------
# forge_reply <pr> <thread-id> <body-file>  -> replies on a thread (signed by caller); NOT resolved
# ------------------------------------------------------------------------------------------------
_gh_reply() {
  local body; body="$(cat "$3")"
  gh api graphql -f threadId="$2" -f body="$body" -f query='
    mutation($threadId:ID!,$body:String!){
      addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId, body:$body}){
        comment{ url }
      }
    }' --jq '.data.addPullRequestReviewThreadReply.comment.url'
}
_ado_reply() {
  local payload; payload="$(mktemp)"
  jq -Rs '{content:., parentCommentId:1, commentType:1}' < "$3" > "$payload"
  _ado_api POST "$(_ado_base)/pullRequests/$1/threads/$2/comments?api-version=7.1" "$payload" \
    | jq -r '.id // empty' >/dev/null
  rm -f "$payload"
}
forge_reply() { case "$(aind_code_host)" in ado) _ado_reply "$@";; *) _gh_reply "$@";; esac; }

# ------------------------------------------------------------------------------------------------
# Code-PR discovery (host-agnostic: filters forge_pr_list output by this flow's own markers).
# Moved here from aind-common.sh — it is PR-layer logic and the filter stays offline-unit-testable.
# ------------------------------------------------------------------------------------------------
# Emits one TSV line per matching PR: <state>\t<number>\t<url>\t<head>. A PR matches when its title
# ends "(AB#<id>)" (from aind-open-code-pr.sh open) OR its body carries an AIND-LINKS work-item URL
# ending "/edit/<id>". Kept as a separate fn so it is unit-testable offline (feed captured TSV).
aind_filter_code_prs() {
  # stdin: TSV rows "state\tnumber\turl\thead\ttitle\tbody" (body newlines escaped by @tsv).
  awk -F'\t' -v id="$1" '
    {
      state=$1; num=$2; url=$3; head=$4; title=$5; body=$6
      if ((index(title, "(AB#" id ")") > 0) || (body ~ ("edit/" id "([^0-9]|$)")))
        printf "%s\t%s\t%s\t%s\n", state, num, url, head
    }'
}

aind_find_code_prs() { forge_pr_list all | aind_filter_code_prs "$1"; }
