#!/usr/bin/env bash
# aind-common.sh — shared config resolution + helpers for AIND scripts.
# Sourced by the other aind-*.sh scripts; not run directly.
#
# Configuration is read from environment variables (nothing is hard-coded). Those variables are
# populated per-project from TWO files under the project's .claude/, both auto-loaded by walking up
# from $PWD (see aind_autosource_env below):
#
#   .claude/aind.settings.json  SHARED, checked-in project config (JSON). Mapped to AIND_* vars:
#                                 .ado.org            -> AIND_ADO_ORG            (ADO org URL)
#                                 .ado.project        -> AIND_ADO_PROJECT        (ADO project name)
#                                 .ado.repo           -> AIND_ADO_REPO           (ADO repo; ado host)
#                                 .codeHost           -> AIND_CODE_HOST          (github | ado)
#                                 .github.repo        -> AIND_GH_REPO            (owner/repo; gh host)
#                                 .integrationBranch  -> AIND_INTEGRATION_BRANCH (trunk the PR targets)
#                                 .planBranchPrefix   -> AIND_PLAN_BRANCH_PREFIX (optional)
#                                 .lessonsBranch      -> AIND_LESSONS_BRANCH     (optional)
#                               (the .worktree block is read by aind-worktree.sh, not exported here.)
#   .claude/aind.env            GITIGNORED secrets + per-user overrides (shell `export` lines):
#                                 AZURE_DEVOPS_EXT_PAT   ADO PAT (Work Items r/w, Code r/w). Read
#                                                        automatically by `az`, reused for REST via curl.
#                                 AIND_ACTOR             (optional) actor for the signature line;
#                                                        falls back to `git config user.email`, then $USER.
#
# AIND_CODE_HOST selects the forge adapter (aind-forge.sh); the flow is otherwise identical on both
# hosts. An already-set environment wins over both files (CI / parent shell override).

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

# The plan branch for a work item. The prefix is a project concern (override with
# AIND_PLAN_BRANCH_PREFIX, default aind/plan/); the framework still reaches the branch through the
# PR, never by reconstructing this name to find an artifact — this is only used where the branch is
# being created/checked out by its own phase.
aind_plan_branch() { echo "${AIND_PLAN_BRANCH_PREFIX:-aind/plan/}${1}"; }

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

# --- Project config resolution ------------------------------------------------------------------

# Read a scalar from a JSON settings file. Echoes empty on any miss (absent file/key/null value).
# Strips CRLF because Windows jq emits \r, which would otherwise ride along on every value.
aind_json_get() {
  local file="$1" filter="$2"
  [[ -f "$file" ]] || return 0
  jq -r "$filter // empty" "$file" 2>/dev/null | tr -d '\r'
}

# export VAR from a settings filter, but only when VAR is still unset — so aind.env and an
# already-set environment (CI / parent shell) win over the shared settings file.
aind_export_from_settings() {
  local var="$1" file="$2" filter="$3" val
  [[ -n "${!var:-}" ]] && return 0
  val="$(aind_json_get "$file" "$filter")" || true
  [[ -n "$val" ]] && export "$var=$val"
  return 0
}

# Auto-load the project's config so callers don't have to `source` anything first. Walk up from
# $PWD; the first .claude/ holding either config file wins. An already-set environment takes
# precedence: if AIND_ADO_ORG is already exported we leave everything as-is (CI / parent-shell
# override). Within a project, .claude/aind.env is sourced FIRST (secrets + per-user overrides win),
# then .claude/aind.settings.json fills any AIND_* var still unset.
aind_autosource_env() {
  [[ -n "${AIND_ADO_ORG:-}" ]] && return 0   # already configured — don't override
  local dir="$PWD" cdir sf
  while :; do
    cdir="$dir/.claude"
    if [[ -f "$cdir/aind.env" || -f "$cdir/aind.settings.json" ]]; then
      if [[ -f "$cdir/aind.env" ]]; then
        set -a
        # shellcheck disable=SC1090,SC1091
        source "$cdir/aind.env"
        set +a
      fi
      sf="$cdir/aind.settings.json"
      if [[ -f "$sf" ]]; then
        if ! command -v jq >/dev/null 2>&1; then
          echo "aind: [WARN] found $sf but jq is not installed — shared config not loaded (install jq)" >&2
        else
          aind_export_from_settings AIND_ADO_ORG            "$sf" '.ado.org'
          aind_export_from_settings AIND_ADO_PROJECT        "$sf" '.ado.project'
          aind_export_from_settings AIND_ADO_REPO           "$sf" '.ado.repo'
          aind_export_from_settings AIND_CODE_HOST          "$sf" '.codeHost'
          aind_export_from_settings AIND_GH_REPO            "$sf" '.github.repo'
          aind_export_from_settings AIND_INTEGRATION_BRANCH "$sf" '.integrationBranch'
          aind_export_from_settings AIND_PLAN_BRANCH_PREFIX "$sf" '.planBranchPrefix'
          aind_export_from_settings AIND_LESSONS_BRANCH     "$sf" '.lessonsBranch'
        fi
      fi
      return 0
    fi
    [[ "$dir" == "/" || -z "$dir" ]] && break
    dir="$(dirname "$dir")"
  done
  return 0
}
aind_autosource_env
