#!/usr/bin/env bash
# aind-deps.sh <work-item-id>
# Resolves an ADO work item's dependency (Predecessor) links and reports, for each linked
# story, whether it is IMPLEMENTED yet — the grounding for intake's dependency gate.
#
# A "dependency" here is a Predecessor link (ADO link type System.LinkTypes.Dependency-Reverse):
# a story that must be completed before this one can start. For each such link it fetches the
# target's title, ADO state, and AIND status tag and classifies it:
#   IMPLEMENTED      — its AIND status tag is "Implementation complete"; or (if the dependency
#                      carries no AIND status tag) its ADO state is a done-like state
#                      (Closed / Done / Resolved / Completed).
#   NOT IMPLEMENTED  — still in progress / not yet complete.
#   UNKNOWN          — the linked item could not be read (deleted / no access).
#
# Output: a human-readable list, a one-line summary, and a final machine line:
#   DEPS_VERDICT: NONE | MET | UNMET
# NONE  = no dependency links.  MET = every dependency IMPLEMENTED.  UNMET = at least one
# NOT IMPLEMENTED or UNKNOWN. Intake reads DEPS_VERDICT to gate the verdict — an UNMET
# dependency declines the story — WITHOUT affecting the readiness score.
#
# Usage: aind-deps.sh 123

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

ID="${1:-}"
[[ -n "$ID" ]] || aind_die "usage: aind-deps.sh <work-item-id>"
aind_require_env AIND_ADO_ORG AZURE_DEVOPS_EXT_PAT
aind_require_cmd az jq

ORG="$(aind_org)"
TERMINAL="Implementation complete"     # the AIND state that means "implemented"

# Normalize a string for comparison: strip CR, lowercase, collapse whitespace, trim.
norm() {
  printf '%s' "$1" | tr -d '\r' | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[[:space:]]\{1,\}/ /g' -e 's/^ //' -e 's/ $//'
}

# ADO states (any process template) that count as done for a dependency NOT tracked by AIND.
is_done_state() {
  case "$(norm "$1")" in
    closed|done|resolved|completed) return 0 ;;
    *) return 1 ;;
  esac
}

# Extract the AIND status value ("Implementation complete", …) from a ';'-separated tags string;
# echoes empty if the item carries no AIND status tag. Match is normalized on the prefix.
aind_tag_value() {
  local current="$1" raw clean
  [[ -z "$current" ]] && return 0
  IFS=';' read -ra parts <<< "$current"
  for raw in "${parts[@]}"; do
    clean="$(printf '%s' "$raw" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    case "$(norm "$clean")" in
      "aind status -"*)
        printf '%s' "$clean" | sed -E 's/^[Aa][Ii][Nn][Dd][[:space:]]+[Ss]tatus[[:space:]]*-[[:space:]]*//'
        return 0 ;;
    esac
  done
}

# 1. Fetch the work item's relations.
wi_json="$(az boards work-item show --id "$ID" --org "$ORG" --expand relations --output json 2>/dev/null)" \
  || aind_die "could not fetch work item $ID from ADO (check the id, org, and PAT)"

# 2. Predecessor links -> dependency work-item ids (the trailing id of each relation URL).
dep_ids="$(printf '%s' "$wi_json" | jq -r '
  [ (.relations // [])[]
    | select(.rel == "System.LinkTypes.Dependency-Reverse")
    | (.url | sub(".*/"; "")) ] | .[]
' 2>/dev/null || true)"

total=0; implemented=0; notimpl=0; unknown=0
lines=()
if [[ -n "$dep_ids" ]]; then
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    total=$((total+1))
    dj="$(az boards work-item show --id "$dep" --org "$ORG" \
        --query '{title:fields."System.Title", state:fields."System.State", tags:fields."System.Tags"}' \
        -o json 2>/dev/null || true)"
    if [[ -z "$dj" ]]; then
      lines+=("  AB#$dep | (could not read linked item) | UNKNOWN")
      unknown=$((unknown+1)); continue
    fi
    title="$(printf '%s' "$dj" | jq -r '.title // ""')"
    state="$(printf '%s' "$dj" | jq -r '.state // ""')"
    tags="$(printf '%s' "$dj" | jq -r '.tags // ""')"
    aind_val="$(aind_tag_value "$tags")"
    if [[ -n "$aind_val" ]]; then
      if [[ "$(norm "$aind_val")" == "$(norm "$TERMINAL")" ]]; then verdict="IMPLEMENTED"; else verdict="NOT IMPLEMENTED"; fi
    elif is_done_state "$state"; then
      verdict="IMPLEMENTED"
    else
      verdict="NOT IMPLEMENTED"
    fi
    case "$verdict" in
      IMPLEMENTED) implemented=$((implemented+1)) ;;
      *) notimpl=$((notimpl+1)) ;;
    esac
    lines+=("  AB#$dep | state=\"$state\" | aind=\"${aind_val:-(none)}\" | $verdict | \"$title\"")
  done <<< "$dep_ids"
fi

echo "Dependencies (Predecessor links — stories this item must not start before):"
if (( total == 0 )); then
  echo "  (none linked)"
else
  for l in "${lines[@]}"; do echo "$l"; done
fi
echo
echo "Summary: $total dependency(ies); $implemented implemented, $notimpl not implemented, $unknown unknown."

if (( total == 0 )); then
  echo "DEPS_VERDICT: NONE"
elif (( notimpl + unknown == 0 )); then
  echo "DEPS_VERDICT: MET"
else
  echo "DEPS_VERDICT: UNMET"
fi
