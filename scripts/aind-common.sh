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

# The canonical set of AIND status states (design-log D4).
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
