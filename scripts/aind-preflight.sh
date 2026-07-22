#!/usr/bin/env bash
# aind-preflight.sh
# Probes the local environment for the AIND prerequisites and prints a status checklist.
# Informational only — it never changes anything and always exits 0. Some prerequisites
# (the Azure Boards <-> GitHub integration, branch protection) cannot be auto-checked and
# are reported as [MANUAL].
#
# Reads the same env vars as the other scripts; missing ones are reported, not fatal.
# Config in .claude/aind.env is auto-loaded (walk-up from $PWD, like aind-common.sh), so you
# do not need to `source` it first. An already-set environment wins (CI / parent shell).

# NOTE: deliberately no `set -e` — we want every check to run and report. (This is also why
# we autosource inline rather than sourcing aind-common.sh, which sets -euo pipefail.)

# Auto-source the project's .claude/aind.env (first one found walking up from $PWD).
if [[ -z "${AIND_ADO_ORG:-}" ]]; then
  _dir="$PWD"
  while :; do
    if [[ -f "$_dir/.claude/aind.env" ]]; then
      set -a
      # shellcheck disable=SC1090,SC1091
      source "$_dir/.claude/aind.env"
      set +a
      break
    fi
    [[ "$_dir" == "/" || -z "$_dir" ]] && break
    _dir="$(dirname "$_dir")"
  done
  unset _dir
fi

HOST="${AIND_CODE_HOST:-github}"

pass=0; warn=0; fail=0

ok()     { echo "[PASS] $*"; pass=$((pass+1)); }
warning(){ echo "[WARN] $*"; warn=$((warn+1)); }
bad()    { echo "[FAIL] $*"; fail=$((fail+1)); }
manual() { echo "[MANUAL] $*"; }

have() { command -v "$1" >/dev/null 2>&1; }

echo "AIND preflight — prerequisites for the plan phase"
echo "-------------------------------------------------"
echo "Code host: $HOST"
echo

echo "Tools:"
for c in bash git curl; do
  if have "$c"; then ok "$c present"; else bad "$c not found (required)"; fi
done
if have az; then ok "az present ($(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo '?'))"; else bad "az (Azure CLI) not found — required for ADO work items"; fi
if have az && az extension show --name azure-devops >/dev/null 2>&1; then
  ok "az devops extension installed"
elif [[ "$HOST" == "ado" ]]; then
  bad "az 'azure-devops' extension not detected — required for ADO code host (az repos). Install: az extension add --name azure-devops"
else
  warning "az 'azure-devops' extension not detected — install with: az extension add --name azure-devops"
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
else
  bad "AZURE_DEVOPS_EXT_PAT not set — needed for ADO Work Items r/w${HOST:+ (and Code r/w for the ADO code host)}"
fi

echo
echo "AIND configuration (env vars):"
_cfg=(AIND_ADO_ORG AIND_ADO_PROJECT AIND_INTEGRATION_BRANCH)
if [[ "$HOST" == "ado" ]]; then _cfg+=(AIND_ADO_REPO); else _cfg+=(AIND_GH_REPO); fi
for v in "${_cfg[@]}"; do
  if [[ -n "${!v:-}" ]]; then ok "$v=${!v}"; else warning "$v not set (see .claude/aind.env)"; fi
done

echo
echo "Worktrees (parallel work — optional):"
_wtcfg=""
_d="$PWD"
while :; do
  if [[ -f "$_d/.claude/aind-worktree.config.json" ]]; then _wtcfg="$_d/.claude/aind-worktree.config.json"; break; fi
  [[ "$_d" == "/" || -z "$_d" ]] && break
  _d="$(dirname "$_d")"
done
if [[ -n "$_wtcfg" ]]; then
  ok "worktrees enabled ($_wtcfg)"
  if ! have jq; then bad "jq is REQUIRED to parse aind-worktree.config.json when worktrees are enabled"; fi
  if have jq; then
    _root="$(jq -r '.worktreeRoot // ".claude/worktrees"' "$_wtcfg" 2>/dev/null | tr -d '\r')"
    [[ -n "$_root" ]] || _root=".claude/worktrees"
    if git check-ignore -q "$_root/_probe" 2>/dev/null; then
      ok "worktreeRoot '$_root' is gitignored"
    else
      warning "worktreeRoot '$_root' is not gitignored — add it (e.g. '$_root/') to .gitignore so nested worktrees don't clutter 'git status'"
    fi
    # symlinkDirs: heavyweight dirs (e.g. node_modules) shared across worktrees (junction on
    # Windows / symlink on Unix). Report them and warn if a target is not yet present in the main
    # checkout (so nothing populates the shared store until an install runs there / in a worktree).
    _wtmain="$(dirname "$(dirname "$_wtcfg")")"
    _syms="$(jq -r '.symlinkDirs[]?' "$_wtcfg" 2>/dev/null | tr -d '\r')"
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
  fi
else
  manual "worktrees not enabled (no .claude/aind-worktree.config.json) — single-tree mode; that's fine"
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
if have az && [[ -n "${AIND_ADO_ORG:-}" && -n "${AIND_ADO_PROJECT:-}" && -n "${AZURE_DEVOPS_EXT_PAT:-}" ]]; then
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
if [[ "$HOST" == "github" ]]; then
  manual "Azure Boards <-> GitHub integration connected (so AB#<id> in a PR links to the work item)"
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
