#!/usr/bin/env bash
# aind-common.sh — shared config resolution + helpers for AIND scripts.
# Sourced by the other aind-*.sh scripts; not run directly.
#
# Configuration comes from environment variables (set per-project, e.g. exported from the
# project's .claude/aind.env or recorded in its .claude/CLAUDE.md). Nothing is hard-coded.
#
#   AIND_ADO_ORG            ADO org URL, e.g. https://dev.azure.com/<your-org>
#   AIND_ADO_PROJECT        ADO project name, e.g. <your-project>
#   AIND_CODE_HOST          Where the code + PRs live: github (default) | ado. Selects the forge
#                           adapter (aind-forge.sh); the flow is otherwise identical on both hosts.
#   AIND_GH_REPO            GitHub repo, e.g. <owner>/<repo>   (used when AIND_CODE_HOST=github)
#   AIND_ADO_REPO           ADO repo name                       (used when AIND_CODE_HOST=ado)
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

# PR-layer helpers (agent signature, code-PR discovery, the forge verbs) live in aind-forge.sh —
# the code-host adapter, which sources this file. Scripts that touch PRs source aind-forge.sh
# instead of this file directly.

# --- Lessons stream (dreaming phase) ------------------------------------------------------------
# Lessons-learned records live on a dedicated, long-lived branch that never merges into the
# integration branch — a pure append-only exhaust store the dreamer later synthesises. The name is
# an internal AIND convention (like the /plans/<id>/plan.md path), so it has a fixed default and is
# only overridable for the rare project whose branch-protection/naming policy forbids that name.
aind_lessons_branch() { echo "${AIND_LESSONS_BRANCH:-aind/lessons}"; }

# Fetch + resolve the tip commit of the lessons branch. Remote wins (a fresh clone / another machine
# may have emitted since), then a local ref, else empty (branch does not exist yet). Echoes the SHA.
aind_lessons_ref() {
  local br ref=""
  br="$(aind_lessons_branch)"
  if git fetch --quiet origin "$br" 2>/dev/null; then
    ref="$(git rev-parse --verify --quiet FETCH_HEAD || true)"
  fi
  [[ -z "$ref" ]] && ref="$(git rev-parse --verify --quiet "refs/heads/$br" || true)"
  echo "$ref"
}

# Commit an already-written tree onto the lessons branch and push it, WITHOUT touching the working
# tree or the current branch (callers build the tree in a throwaway GIT_INDEX_FILE, so an agent can
# emit mid-implementation without being yanked off its branch). Args: <tree-sha> <parent-or-empty>
# <message>. Echoes the new commit SHA. Updates the local branch ref (unless it is the current HEAD)
# and pushes to origin when a remote exists; a rejected push (a concurrent emit raced us) is fatal
# so the caller can retry rather than silently lose the record.
aind_lessons_push() {
  local tree="$1" parent="$2" msg="$3" br commit cur
  br="$(aind_lessons_branch)"
  if [[ -n "$parent" ]]; then
    commit="$(git commit-tree "$tree" -p "$parent" -m "$msg")"
  else
    commit="$(git commit-tree "$tree" -m "$msg")"
  fi
  cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [[ "$cur" != "$br" ]] && git update-ref "refs/heads/$br" "$commit"
  if git remote get-url origin >/dev/null 2>&1; then
    git push --quiet origin "${commit}:refs/heads/${br}" 2>/dev/null \
      || aind_die "committed to local ${br} but the push to origin/${br} was rejected (a concurrent emit likely raced this one) — re-run to retry"
  fi
  echo "$commit"
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
