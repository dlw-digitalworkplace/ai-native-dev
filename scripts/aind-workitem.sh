#!/usr/bin/env bash
# aind-workitem.sh <work-item-id>
# Fetches an ADO work item as JSON — the grounding input for intake and the planner.
# Outputs the raw work-item JSON (fields incl. title, description, acceptance criteria,
# tags) to stdout for the agent to read.
#
# Usage: aind-workitem.sh 123

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

ID="${1:-}"
[[ -n "$ID" ]] || aind_die "usage: aind-workitem.sh <work-item-id>"
aind_require_env AIND_ADO_ORG AZURE_DEVOPS_EXT_PAT
aind_require_cmd az

# `az boards work-item show` reads AZURE_DEVOPS_EXT_PAT automatically.
# --expand all so the agent sees fields + relations (linked PRs, etc.).
az boards work-item show \
  --id "$ID" \
  --org "$(aind_org)" \
  --expand all \
  --output json
