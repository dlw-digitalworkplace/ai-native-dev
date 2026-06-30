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

pass=0; warn=0; fail=0

ok()     { echo "[PASS] $*"; pass=$((pass+1)); }
warning(){ echo "[WARN] $*"; warn=$((warn+1)); }
bad()    { echo "[FAIL] $*"; fail=$((fail+1)); }
manual() { echo "[MANUAL] $*"; }

have() { command -v "$1" >/dev/null 2>&1; }

echo "AIND preflight — prerequisites for the plan phase"
echo "-------------------------------------------------"

echo "Tools:"
for c in bash git curl; do
  if have "$c"; then ok "$c present"; else bad "$c not found (required)"; fi
done
if have az; then ok "az present ($(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo '?'))"; else bad "az (Azure CLI) not found — required for ADO work items"; fi
if have az && az extension show --name azure-devops >/dev/null 2>&1; then ok "az devops extension installed"; else warning "az 'azure-devops' extension not detected — install with: az extension add --name azure-devops"; fi
if have gh; then ok "gh present"; else bad "gh (GitHub CLI) not found — required for plan PRs"; fi
if have jq; then ok "jq present"; else bad "jq not found — required by aind-comment (install: brew/apt/winget install jq)"; fi

echo
echo "Authentication:"
if have gh; then
  if gh auth status >/dev/null 2>&1; then ok "gh authenticated"; else bad "gh not authenticated — run: gh auth login"; fi
fi
if [[ -n "${AZURE_DEVOPS_EXT_PAT:-}" ]]; then ok "AZURE_DEVOPS_EXT_PAT is set"; else bad "AZURE_DEVOPS_EXT_PAT not set — needed for ADO (Work Items r/w + Code r/w)"; fi

echo
echo "AIND configuration (env vars):"
for v in AIND_ADO_ORG AIND_ADO_PROJECT AIND_GH_REPO AIND_INTEGRATION_BRANCH; do
  if [[ -n "${!v:-}" ]]; then ok "$v=${!v}"; else warning "$v not set (see .claude/aind.env)"; fi
done

echo
echo "Connectivity (best-effort):"
if have gh && [[ -n "${AIND_GH_REPO:-}" ]]; then
  if gh repo view "$AIND_GH_REPO" >/dev/null 2>&1; then ok "GitHub repo reachable: $AIND_GH_REPO"; else bad "cannot access GitHub repo $AIND_GH_REPO with the current gh account"; fi
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
manual "Azure Boards <-> GitHub integration connected (so AB#<id> in a PR links to the work item)"
manual "Integration branch has 'require conversation resolution before merging' enabled (so assumption threads gate the plan-PR merge)"

echo
echo "-------------------------------------------------"
echo "Summary: $pass passed, $warn warnings, $fail failed."
if (( fail > 0 )); then
  echo "Resolve the [FAIL] items before running the AIND plan-phase commands."
fi
exit 0
