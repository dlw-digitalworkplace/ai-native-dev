#!/usr/bin/env bash
# aind-states.sh discover <work-item-type>
# aind-states.sh propose  <work-item-type>
# aind-states.sh write                              (final stateMap JSON object on stdin)
#
# Adopt a project's NATIVE work-item States for the AIND-status mirror — the deterministic mechanics
# behind /aind:map-states. AIND's status->category *intent* is fixed here; the concrete state *name*
# comes from whatever the project already has. We never create, rename, or force states — we map onto
# what exists, so there is no per-project/per-org burden of imposing our own state set. Categories are
# ADO's universal buckets, present in every process template (Agile/Scrum/Basic/CMMI/custom):
#   Proposed | InProgress | Resolved | Completed | Removed.
#
#   discover : GET the states of <work-item-type> from ADO; print a JSON array
#                [{"name":"<state>","category":"<category>"}, ...]
#              For offline testing, set AIND_STATES_FILE=<path> to a JSON array (or a raw ADO
#              response with a .value array) of that shape and NO ADO call is made.
#   propose  : discover, then for each MIRRORED AIND status print one TSV line:
#                <aind-status> \t <category> \t <resolved-state-or-empty> \t <count> \t <cand1|cand2|…>
#              resolved-state is filled only when exactly ONE state carries that category (auto-pick);
#              count 0 or >1 means /aind:map-states asks the human (AskUserQuestion) to pick or skip.
#   write    : read a JSON object {"<aind-status>":"<state>", …} on stdin and merge it into .stateMap
#              of the project's .claude/aind.settings.json (found by walking up from $PWD).
#
# The resolved map lives in aind.settings.json (shared config, D41); aind-common.sh surfaces it as
# AIND_STATE_MAP and aind-status.sh mirrors the native State after each tag write. Best-effort
# throughout — an unmapped status is simply not mirrored, and the AIND tag stays the source of truth.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

# AIND status -> universal ADO state category (the fixed intent). Only the statuses listed here are
# mirrored; the edge/error statuses (Intake declined, Intake approved, Needs attention) are
# intentionally left tag-only in v1 — they have no clean category in most templates. Two parallel
# entries "status|category" (not an associative array, for bash 3.2 portability).
AIND_MIRRORED=(
  "Ready for intake|Proposed"
  "Generating plan|InProgress"
  "Plan ready for review|InProgress"
  "Ready for implementation|InProgress"
  "In implementation|InProgress"
  "Implementation complete|Completed"
)

# Locate the nearest .claude/aind.settings.json by walking up from $PWD. Echoes the path, or empty.
aind_find_settings() {
  local dir="$PWD"
  while :; do
    [[ -f "$dir/.claude/aind.settings.json" ]] && { echo "$dir/.claude/aind.settings.json"; return 0; }
    [[ "$dir" == "/" || -z "$dir" ]] && break
    dir="$(dirname "$dir")"
  done
  return 0
}

# Print the discovered states as a normalized JSON array [{"name","category"}]. ADO's field is
# `stateCategory`; we fall back to `category` in case a build/version differs.
cmd_discover() {
  local type="$1"
  [[ -n "$type" ]] || aind_die "usage: aind-states.sh discover <work-item-type>"
  aind_require_cmd jq
  if [[ -n "${AIND_STATES_FILE:-}" ]]; then
    [[ -f "$AIND_STATES_FILE" ]] || aind_die "AIND_STATES_FILE not found: $AIND_STATES_FILE"
    jq '[ ((.value? // .)[]) | {name, category: (.stateCategory // .category)} ]' "$AIND_STATES_FILE"
    return
  fi
  aind_require_env AIND_ADO_ORG AIND_ADO_PROJECT AZURE_DEVOPS_EXT_PAT
  aind_require_cmd curl
  local org enc url resp code body ado_msg
  org="$(aind_org)"
  enc="$(jq -rn --arg s "$type" '$s|@uri')"
  url="${org}/${AIND_ADO_PROJECT}/_apis/wit/workitemtypes/${enc}/states?api-version=7.1"
  resp="$(curl -s -w $'\n%{http_code}' -u ":${AZURE_DEVOPS_EXT_PAT}" "$url")" \
    || aind_die "could not reach ADO to list states for '$type' (network/curl error)"
  code="${resp##*$'\n'}"; body="${resp%$'\n'*}"
  if [[ "$code" != 2* ]]; then
    ado_msg="$(printf '%s' "$body" | jq -r '.message // empty' 2>/dev/null)"
    aind_die "listing states for work-item type '$type' failed (HTTP ${code})${ado_msg:+: $ado_msg}"
  fi
  printf '%s' "$body" | jq '[ .value[] | {name, category: (.stateCategory // .category)} ]'
}

# For each mirrored AIND status, emit its category, the auto-resolved state (only when the category
# has exactly one state), the candidate count, and the pipe-joined candidate list.
cmd_propose() {
  local type="$1"
  [[ -n "$type" ]] || aind_die "usage: aind-states.sh propose <work-item-type>"
  local states row status cat cands count resolved joined
  states="$(cmd_discover "$type")"
  for row in "${AIND_MIRRORED[@]}"; do
    status="${row%%|*}"; cat="${row##*|}"
    cands="$(printf '%s' "$states" \
      | jq -r --arg c "$cat" '[ .[] | select((.category // "" | ascii_downcase) == ($c | ascii_downcase)) | .name ] | .[]')"
    count="$(printf '%s' "$cands" | grep -c . || true)"
    if [[ "$count" == "1" ]]; then resolved="$cands"; else resolved=""; fi
    joined="$(printf '%s' "$cands" | paste -sd'|' - 2>/dev/null || true)"
    printf '%s\t%s\t%s\t%s\t%s\n' "$status" "$cat" "$resolved" "$count" "$joined"
  done
}

# Merge a stdin JSON object into .stateMap of the project's aind.settings.json.
cmd_write() {
  aind_require_cmd jq
  local map settings tmp n
  map="$(cat)"
  printf '%s' "$map" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || aind_die "write: stdin must be a JSON object mapping AIND statuses to state names"
  settings="$(aind_find_settings)"
  [[ -n "$settings" ]] || aind_die "no .claude/aind.settings.json found (run /aind:onboard first, then re-run)"
  tmp="$(mktemp)"
  if jq --argjson m "$map" '.stateMap = $m' "$settings" > "$tmp"; then
    mv "$tmp" "$settings"
  else
    rm -f "$tmp"; aind_die "could not update stateMap in $settings"
  fi
  n="$(printf '%s' "$map" | jq 'length')"
  echo "aind: wrote stateMap ($n mapping(s)) into $settings"
}

MODE="${1:-}"
case "$MODE" in
  discover) cmd_discover "${2:-}" ;;
  propose)  cmd_propose  "${2:-}" ;;
  write)    cmd_write ;;
  *)        aind_die "usage: aind-states.sh discover|propose <work-item-type>  |  aind-states.sh write  (stateMap JSON on stdin)" ;;
esac
