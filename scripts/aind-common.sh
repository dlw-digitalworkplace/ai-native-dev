#!/usr/bin/env bash
# aind-common.sh — shared config resolution + helpers for AIND scripts.
# Sourced by the other aind-*.sh scripts; not run directly.
#
# Configuration comes from environment variables (set per-project, e.g. exported from the
# project's .claude/aind.env or recorded in its .claude/CLAUDE.md). Nothing is hard-coded.
#
#   AIND_ADO_ORG            ADO org URL, e.g. https://dev.azure.com/<your-org>
#   AIND_ADO_PROJECT        ADO project name, e.g. <your-project>
#   AIND_GH_REPO            GitHub repo, e.g. <owner>/<repo>
#   AIND_INTEGRATION_BRANCH Integration/trunk branch the plan PR targets, e.g. main
#   AZURE_DEVOPS_EXT_PAT    ADO PAT (Work Items r/w, Code r/w). Read automatically by `az`,
#                           and reused here for direct REST (comments) via curl.
#   AIND_ACTOR              (optional) human-readable actor for the signature line;
#                           falls back to `git config user.email`, then $USER.

set -euo pipefail

# The canonical set of AIND status states.
AIND_STATES=(
  "Ready for intake"
  "Intake declined"
  "Intake approved"
  "Generating plan"
  "Plan ready for review"
  "Ready for implementation"
  "In implementation"
  "Implementation complete"
  "Needs attention"
)

aind_die() { echo "aind: $*" >&2; exit 1; }

# Require a set of env vars to be non-empty.
aind_require_env() {
  local missing=()
  local v
  for v in "$@"; do
    if [[ -z "${!v:-}" ]]; then missing+=("$v"); fi
  done
  if (( ${#missing[@]} > 0 )); then
    aind_die "missing required env var(s): ${missing[*]} (see scripts/aind-common.sh header)"
  fi
}

aind_require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || aind_die "required command not found: $c"
  done
}

# Validate a status string against the canonical set.
aind_validate_state() {
  local want="$1" s
  for s in "${AIND_STATES[@]}"; do
    [[ "$s" == "$want" ]] && return 0
  done
  aind_die "invalid AIND state: '$want'. Valid: ${AIND_STATES[*]}"
}

# Human-readable actor for signatures.
aind_actor() {
  if [[ -n "${AIND_ACTOR:-}" ]]; then echo "$AIND_ACTOR"; return; fi
  local e
  e="$(git config user.email 2>/dev/null || true)"
  if [[ -n "$e" ]]; then echo "$e"; return; fi
  echo "${USER:-unknown}"
}

# Strip the scheme from the org URL host for messages (cosmetic only).
aind_org() { echo "${AIND_ADO_ORG%/}"; }

# Agent signature for GitHub PR comments/threads/replies — the GitHub twin of the ADO signature
# built in aind-comment.sh. Same intent: in local/v0 mode the coder, reviewer, and planner all post
# under one GitHub identity, so every PR comment must be attributed to the agent that authored it.
# GitHub renders markdown and PRESERVES HTML comments, so the machine marker is a real HTML comment
# (invisible when rendered, still greppable as "AIND-AGENT: <name>") rather than the display:none
# span ADO needs. Callers append the returned string to the comment body before posting.
aind_gh_signature() {
  local agent="$1"
  [[ -n "$agent" ]] || aind_die "aind_gh_signature: missing agent name"
  printf '\n\n— 🤖 AIND %s Agent (run by %s)\n<!-- AIND-AGENT: %s -->' \
    "${agent^}" "$(aind_actor)" "$agent"
}

# Find the code PR(s) for a work item. The code branch is coder-generated and never reconstructed,
# so a PR is matched by this flow's own markers: a title ending "(AB#<id>)" (from aind-open-code-pr.sh
# open) OR an AIND-LINKS work-item URL ending "/edit/<id>". Emits one TSV line per matching PR:
#   <state>\t<number>\t<url>\t<head-ref>
# for EVERY state — the caller applies its own policy (e.g. a single MERGED match for completion, a
# single OPEN match for revision). The marker match itself lives in aind_filter_code_prs so it is
# unit-testable offline (feed it captured `gh pr list` TSV; no live gh needed).
aind_filter_code_prs() {
  # stdin: TSV rows "state\tnumber\turl\thead\ttitle\tbody" (body newlines escaped by @tsv).
  awk -F'\t' -v id="$1" '
    {
      state=$1; num=$2; url=$3; head=$4; title=$5; body=$6
      if ((index(title, "(AB#" id ")") > 0) || (body ~ ("edit/" id "([^0-9]|$)")))
        printf "%s\t%s\t%s\t%s\n", state, num, url, head
    }'
}

aind_find_code_prs() {
  # Needs AIND_GH_REPO + gh (caller validates). @tsv escapes newlines so each PR is one row.
  local id="$1"
  gh pr list --repo "$AIND_GH_REPO" --state all --limit 200 \
    --json number,title,url,state,headRefName,body \
    --jq '.[] | [.state,(.number|tostring),.url,.headRefName,.title,.body] | @tsv' \
  | aind_filter_code_prs "$id"
}

# Auto-source the project's .claude/aind.env so callers don't have to `source` it first.
# Walk up from $PWD; the first .claude/aind.env found wins. An already-set environment takes
# precedence: if AIND_ADO_ORG is already exported, we leave everything as-is (lets CI or a
# parent shell override the file). The file's own `export`s populate the environment.
aind_autosource_env() {
  [[ -n "${AIND_ADO_ORG:-}" ]] && return 0   # already configured — don't override
  local dir="$PWD"
  while :; do
    if [[ -f "$dir/.claude/aind.env" ]]; then
      set -a
      # shellcheck disable=SC1090,SC1091
      source "$dir/.claude/aind.env"
      set +a
      return 0
    fi
    [[ "$dir" == "/" || -z "$dir" ]] && break
    dir="$(dirname "$dir")"
  done
  return 0
}
aind_autosource_env
