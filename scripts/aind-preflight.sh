#!/usr/bin/env bash
# aind-preflight.sh
# Probes the local environment for the AIND prerequisites and prints a status checklist.
# Informational only — it never changes anything and always exits 0. Some prerequisites
# (the Azure Boards <-> GitHub integration, branch protection) cannot be auto-checked and
# are reported as [MANUAL].
#
# Reads the same env vars as the other scripts; missing ones are reported, not fatal.
# Project config is auto-loaded (walk-up from $PWD, like aind-common.sh): shared settings from
# .claude/aind.settings.json and secrets from .claude/aind.env, so you do not need to `source`
# anything first. An already-set environment wins (CI / parent shell).

# NOTE: deliberately no `set -e` — we want every check to run and report. (This is also why
# we autosource inline rather than sourcing aind-common.sh, which sets -euo pipefail.)

# Auto-load the project's config (first .claude/ found walking up from $PWD): source aind.env
# (secrets), then map aind.settings.json (shared) -> AIND_* vars. Mirrors aind-common.sh.
if [[ -z "${AIND_ADO_ORG:-}" ]]; then
  _dir="$PWD"
  while :; do
    _cdir="$_dir/.claude"
    if [[ -f "$_cdir/aind.env" || -f "$_cdir/aind.settings.json" ]]; then
      if [[ -f "$_cdir/aind.env" ]]; then
        set -a
        # shellcheck disable=SC1090,SC1091
        source "$_cdir/aind.env"
        set +a
      fi
      _sf="$_cdir/aind.settings.json"
      if [[ -f "$_sf" ]] && command -v jq >/dev/null 2>&1; then
        _pf_set() { local v="$1" f="$2" val; [[ -n "${!v:-}" ]] && return 0; val="$(jq -r "$f // empty" "$_sf" 2>/dev/null | tr -d '\r')"; [[ -n "$val" ]] && export "$v=$val"; return 0; }
        _pf_set AIND_ADO_ORG            '.ado.org'
        _pf_set AIND_ADO_PROJECT        '.ado.project'
        _pf_set AIND_ADO_REPO           '.ado.repo'
        _pf_set AIND_TRACKER            '.tracker'
        _pf_set AIND_TRACKER_DIR        '.trackerDir'
        _pf_set AIND_CODE_HOST          '.codeHost'
        _pf_set AIND_GH_REPO            '.github.repo'
        _pf_set AIND_INTEGRATION_BRANCH '.integrationBranch'
        _pf_set AIND_PLAN_BRANCH_PREFIX '.planBranchPrefix'
        _pf_set AIND_LESSONS_BRANCH     '.lessonsBranch'
        unset -f _pf_set
      fi
      break
    fi
    [[ "$_dir" == "/" || -z "$_dir" ]] && break
    _dir="$(dirname "$_dir")"
  done
  unset _dir _cdir _sf
fi

HOST="${AIND_CODE_HOST:-github}"
TRACKER="${AIND_TRACKER:-ado}"
# ADO tooling (az + azure-devops ext + PAT) is needed when EITHER the work-item tracker OR the code
# host is Azure DevOps.
if [[ "$TRACKER" == "ado" || "$HOST" == "ado" ]]; then NEED_ADO=1; else NEED_ADO=0; fi

pass=0; warn=0; fail=0

ok()     { echo "[PASS] $*"; pass=$((pass+1)); }
warning(){ echo "[WARN] $*"; warn=$((warn+1)); }
bad()    { echo "[FAIL] $*"; fail=$((fail+1)); }
manual() { echo "[MANUAL] $*"; }

have() { command -v "$1" >/dev/null 2>&1; }

echo "AIND preflight — prerequisites for the plan phase"
echo "-------------------------------------------------"
echo "Work-item tracker: $TRACKER"
echo "Code host: $HOST"
echo

echo "Tools:"
for c in bash git curl; do
  if have "$c"; then ok "$c present"; else bad "$c not found (required)"; fi
done
if have az; then
  ok "az present ($(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo '?'))"
elif (( NEED_ADO )); then
  bad "az (Azure CLI) not found — required for Azure DevOps (work items and/or code host)"
else
  ok "az not required (tracker=$TRACKER, code host=$HOST)"
fi
if have az && az extension show --name azure-devops >/dev/null 2>&1; then
  ok "az devops extension installed"
elif (( NEED_ADO )); then
  bad "az 'azure-devops' extension not detected — required for Azure DevOps (az boards / az repos). Install: az extension add --name azure-devops"
else
  manual "az 'azure-devops' extension not needed (tracker=$TRACKER, code host=$HOST)"
fi
if [[ "$HOST" == "github" ]]; then
  if have gh; then ok "gh present"; else bad "gh (GitHub CLI) not found — required for the GitHub code host"; fi
elif have gh; then
  ok "gh present (not required for the ADO code host)"
fi
if have jq; then ok "jq present"; else bad "jq not found — required by aind-comment (install: brew/apt/winget install jq)"; fi

echo
echo "Authentication:"
if [[ "$HOST" == "github" ]] && have gh; then
  if gh auth status >/dev/null 2>&1; then ok "gh authenticated"; else bad "gh not authenticated — run: gh auth login"; fi
fi
if [[ -n "${AZURE_DEVOPS_EXT_PAT:-}" ]]; then
  ok "AZURE_DEVOPS_EXT_PAT is set"
elif (( NEED_ADO )); then
  bad "AZURE_DEVOPS_EXT_PAT not set — needed for Azure DevOps (work items and/or code r/w)"
else
  ok "AZURE_DEVOPS_EXT_PAT not required (tracker=$TRACKER, code host=$HOST)"
fi

echo
echo "AIND configuration (shared — .claude/aind.settings.json):"
_cfg=(AIND_INTEGRATION_BRANCH)
if [[ "$TRACKER" == "ado" ]]; then _cfg+=(AIND_ADO_ORG AIND_ADO_PROJECT); fi
if [[ "$HOST" == "ado" ]]; then _cfg+=(AIND_ADO_REPO); else _cfg+=(AIND_GH_REPO); fi
for v in "${_cfg[@]}"; do
  if [[ -n "${!v:-}" ]]; then ok "$v=${!v}"; else warning "$v not set (see .claude/aind.settings.json)"; fi
done

# File tracker: report the item-store directory, its default resolution, writability, and (only when
# it resolves inside the repo) whether it is gitignored.
if [[ "$TRACKER" == "file" ]]; then
  if ! have jq; then
    warning "jq not present — the file tracker needs jq to read/write items"
  fi
  _tdir="${AIND_TRACKER_DIR:-}"
  if [[ -z "$_tdir" ]]; then
    _gcd="$(git rev-parse --git-common-dir 2>/dev/null || true)"
    if [[ -n "$_gcd" ]]; then _troot="$(cd "$(dirname "$_gcd")" && pwd)"; _tdir="$_troot/.aind/items"; fi
  fi
  case "$_tdir" in "~"|"~/"*) _tdir="${HOME}${_tdir#\~}" ;; esac
  if [[ -z "$_tdir" ]]; then
    bad "file tracker: AIND_TRACKER_DIR not set and not in a git repo — set '.trackerDir' (absolute path) in .claude/aind.settings.json"
  else
    if mkdir -p "$_tdir" 2>/dev/null && [[ -w "$_tdir" ]]; then
      ok "file tracker dir writable: $_tdir"
    else
      bad "file tracker dir not writable: $_tdir (check the path / permissions)"
    fi
    if git check-ignore -q "$_tdir" 2>/dev/null; then
      ok "file tracker dir is gitignored"
    elif git rev-parse --show-toplevel >/dev/null 2>&1 && [[ "$_tdir" == "$(git rev-parse --show-toplevel)"* ]]; then
      warning "file tracker dir '$_tdir' is inside the repo but not gitignored — add it to .gitignore if you don't want items committed"
    else
      ok "file tracker dir is outside the repo (not tracked by git)"
    fi
  fi
fi

echo
echo "Worktrees (parallel work — optional):"
_settings=""
_d="$PWD"
while :; do
  if [[ -f "$_d/.claude/aind.settings.json" ]]; then _settings="$_d/.claude/aind.settings.json"; break; fi
  [[ "$_d" == "/" || -z "$_d" ]] && break
  _d="$(dirname "$_d")"
done
_wt_enabled="false"
if [[ -n "$_settings" ]] && have jq; then
  _wt_enabled="$(jq -r '.worktree.enabled // false' "$_settings" 2>/dev/null | tr -d '\r')"
fi
if [[ "$_wt_enabled" == "true" ]]; then
  ok "worktrees enabled (worktree.enabled=true in $_settings)"
  _root="$(jq -r '.worktree.worktreeRoot // ".claude/worktrees"' "$_settings" 2>/dev/null | tr -d '\r')"
  [[ -n "$_root" ]] || _root=".claude/worktrees"
  if git check-ignore -q "$_root/_probe" 2>/dev/null; then
    ok "worktreeRoot '$_root' is gitignored"
  else
    warning "worktreeRoot '$_root' is not gitignored — add it (e.g. '$_root/') to .gitignore so nested worktrees don't clutter 'git status'"
  fi
  # symlinkDirs: heavyweight dirs (e.g. node_modules) shared across worktrees (junction on
  # Windows / symlink on Unix). Report them and warn if a target is not yet present in the main
  # checkout (so nothing populates the shared store until an install runs there / in a worktree).
  _wtmain="$(dirname "$(dirname "$_settings")")"
  _syms="$(jq -r '.worktree.symlinkDirs[]?' "$_settings" 2>/dev/null | tr -d '\r')"
  if [[ -n "$_syms" ]]; then
    ok "symlinkDirs (shared across worktrees): $(echo "$_syms" | tr '\n' ' ')"
    while IFS= read -r _sd; do
      [[ -n "$_sd" ]] || continue
      if [[ -d "$_wtmain/$_sd" ]]; then
        ok "shared dir '$_sd' present in the main checkout"
      else
        warning "shared dir '$_sd' not present in the main checkout yet — create/install it there (e.g. run 'npm install') so worktrees have something to share; it's a genuinely shared store (a branch changing deps re-installs into it; concurrent installs across worktrees can collide — pnpm avoids both)"
      fi
    done <<< "$_syms"
  fi
elif [[ -n "$_settings" ]] && ! have jq; then
  warning "jq is REQUIRED to read the worktree config from aind.settings.json — cannot determine worktree status"
else
  manual "worktrees not enabled (worktree.enabled not true in .claude/aind.settings.json) — single-tree mode; that's fine"
fi

echo
echo "Connectivity (best-effort):"
if [[ "$HOST" == "github" ]] && have gh && [[ -n "${AIND_GH_REPO:-}" ]]; then
  if gh repo view "$AIND_GH_REPO" >/dev/null 2>&1; then ok "GitHub repo reachable: $AIND_GH_REPO"; else bad "cannot access GitHub repo $AIND_GH_REPO with the current gh account"; fi
fi
if [[ "$HOST" == "ado" ]] && have az && [[ -n "${AIND_ADO_ORG:-}" && -n "${AIND_ADO_PROJECT:-}" && -n "${AIND_ADO_REPO:-}" && -n "${AZURE_DEVOPS_EXT_PAT:-}" ]]; then
  if az repos show --repository "$AIND_ADO_REPO" --org "$AIND_ADO_ORG" --project "$AIND_ADO_PROJECT" >/dev/null 2>&1; then
    ok "ADO repo reachable: $AIND_ADO_REPO (project $AIND_ADO_PROJECT)"
  else
    bad "cannot access ADO repo $AIND_ADO_REPO (PAT 'Code' scope? repo/project name?) — needed for the ADO code host"
  fi
fi
if [[ "$TRACKER" == "ado" ]] && have az && [[ -n "${AIND_ADO_ORG:-}" && -n "${AIND_ADO_PROJECT:-}" && -n "${AZURE_DEVOPS_EXT_PAT:-}" ]]; then
  # Probe work-item READ access with a project-scoped query (proves org reachability + PAT +
  # Work Items read in one call). Does not assume any particular work-item id exists, so an
  # empty project still passes instead of false-warning.
  if az boards query --org "$AIND_ADO_ORG" --project "$AIND_ADO_PROJECT" \
       --wiql "SELECT [System.Id] FROM WorkItems" >/dev/null 2>&1; then
    ok "ADO work items readable in $AIND_ADO_PROJECT (org $AIND_ADO_ORG)"
  else
    warning "could not query work items in $AIND_ADO_PROJECT (PAT 'Work Items' read scope? org/project access?) — verify before running /intake"
  fi
fi

echo
echo "Manual checks (cannot be auto-verified):"
if [[ "$TRACKER" == "ado" && "$HOST" == "github" ]]; then
  manual "Azure Boards <-> GitHub integration connected (so AB#<id> in a PR links to the work item)"
fi
if [[ "$HOST" == "github" ]]; then
  manual "Integration branch has 'require conversation resolution before merging' enabled (so assumption threads gate the plan-PR merge)"
else
  manual "Integration branch has a branch policy requiring all comments resolved before completion (so assumption threads gate the plan-PR merge)"
fi

echo
echo "-------------------------------------------------"
echo "Summary: $pass passed, $warn warnings, $fail failed."
if (( fail > 0 )); then
  echo "Resolve the [FAIL] items before running the AIND plan-phase commands."
fi
exit 0
