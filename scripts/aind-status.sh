#!/usr/bin/env bash
# aind-status.sh <work-item-id> <new-state>
# Atomically swaps the AIND status tag (invariant: exactly one
# `AIND status - <state>` tag per item). Preserves all non-AIND tags; removes any
# existing AIND-status tag — robustly, regardless of casing / spacing / a trailing CR —
# and adds the new one.
#
# The write uses a REST PATCH with a **replace** op, NOT `az boards work-item update
# --fields "System.Tags=…"`: that az path emits a JSON-Patch `add`, which on some az builds
# MERGES into the existing tag set instead of replacing it — silently undoing the strip and
# leaving two AIND status tags (violating the single-tag invariant). `replace` overwrites the field outright. When
# the item has no tags yet the field doesn't exist, so we use `add` in that one case.
#
# After updating it VERIFIES the result: if there is not exactly one AIND status tag (the
# target), it auto-corrects once and warns.
#
# Usage: aind-status.sh 123 "Intake approved"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

ID="${1:-}"
NEW_STATE="${2:-}"
[[ -n "$ID" && -n "$NEW_STATE" ]] || aind_die "usage: aind-status.sh <work-item-id> <new-state>"
aind_require_env AIND_ADO_ORG AZURE_DEVOPS_EXT_PAT
aind_require_cmd az curl jq
aind_validate_state "$NEW_STATE"

ORG="$(aind_org)"
TARGET="AIND status - $NEW_STATE"

# Normalize a tag for AIND-status detection: strip CR, lowercase, collapse whitespace, trim.
# This is what makes the strip robust to UI-entered casing/spacing and az.cmd's CRLF.
aind_norm() {
  printf '%s' "$1" | tr -d '\r' | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[[:space:]]\{1,\}/ /g' -e 's/^ //' -e 's/ $//'
}

read_tags() {
  az boards work-item show --id "$ID" --org "$ORG" \
    --query 'fields."System.Tags"' -o tsv 2>/dev/null || true
}

# From a current tags string, build the desired one: keep every non-AIND tag (cleaned),
# drop every AIND-status tag, then append the target exactly once.
build_desired() {
  local current="$1" raw clean norm joined="" t
  local kept=()
  if [[ -n "$current" ]]; then
    IFS=';' read -ra parts <<< "$current"
    for raw in "${parts[@]}"; do
      clean="$(printf '%s' "$raw" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -z "$clean" ]] && continue
      norm="$(aind_norm "$clean")"
      case "$norm" in
        "aind status -"*) continue ;;   # drop any existing AIND status tag
        *) kept+=("$clean") ;;
      esac
    done
  fi
  kept+=("$TARGET")
  for t in "${kept[@]}"; do
    if [[ -z "$joined" ]]; then joined="$t"; else joined="$joined; $t"; fi
  done
  printf '%s' "$joined"
}

# PATCH System.Tags via REST with an explicit op (replace, or add when the field is absent).
patch_tags() {
  local op="$1" value="$2" body url resp code msg tmp
  body="$(jq -nc --arg op "$op" --arg val "$value" \
    '[{op:$op, path:"/fields/System.Tags", value:$val}]')"
  url="${ORG}/_apis/wit/workitems/${ID}?api-version=7.1"
  # Temp file + --data-binary: keeps multibyte UTF-8 intact on Windows/MSYS (same reason as
  # aind-comment.sh) and avoids any argument-boundary mangling of the JSON.
  tmp="$(mktemp)"
  printf '%s' "$body" > "$tmp"
  resp="$(curl -s -w $'\n%{http_code}' -u ":${AZURE_DEVOPS_EXT_PAT}" \
    -H 'Content-Type: application/json-patch+json' \
    -X PATCH "$url" --data-binary @"$tmp")" \
    || { rm -f "$tmp"; aind_die "could not reach ADO to update tags on work item $ID (network/curl error)"; }
  rm -f "$tmp"
  code="${resp##*$'\n'}"
  msg="${resp%$'\n'*}"
  if [[ "$code" != 2* ]]; then
    local ado_msg
    ado_msg="$(printf '%s' "$msg" | jq -r '.message // empty' 2>/dev/null)"
    aind_die "tag update on work item $ID failed (HTTP ${code})${ado_msg:+: $ado_msg}"
  fi
}

# Read current tags, compute the desired set, and PATCH it (replace, or add if no tags yet).
set_tags() {
  local current desired op
  current="$(read_tags)"
  desired="$(build_desired "$current")"
  if [[ -n "$current" ]]; then op="replace"; else op="add"; fi
  patch_tags "$op" "$desired"
}

# Count AIND status tags in a tags string, and whether the target is present.
# Sets globals AIND_COUNT and AIND_HAS_TARGET.
verify_tags() {
  local current="$1" raw norm target_norm
  target_norm="$(aind_norm "$TARGET")"
  AIND_COUNT=0; AIND_HAS_TARGET=0
  [[ -z "$current" ]] && return
  IFS=';' read -ra parts <<< "$current"
  for raw in "${parts[@]}"; do
    norm="$(aind_norm "$raw")"
    case "$norm" in
      "aind status -"*)
        AIND_COUNT=$((AIND_COUNT+1))
        [[ "$norm" == "$target_norm" ]] && AIND_HAS_TARGET=1
        ;;
    esac
  done
}

set_tags

verify_tags "$(read_tags)"
if (( AIND_COUNT != 1 )) || (( AIND_HAS_TARGET != 1 )); then
  # Auto-correct once: rebuild from the current state (strips any strays, re-adds target).
  set_tags
  verify_tags "$(read_tags)"
  if (( AIND_COUNT != 1 )) || (( AIND_HAS_TARGET != 1 )); then
    echo "aind: [WARN] work item $ID has ${AIND_COUNT} AIND status tag(s) after update (expected exactly 1 = '$TARGET'). Check the tags manually." >&2
  else
    echo "aind: [WARN] auto-corrected stray/duplicate AIND status tag(s) on work item $ID." >&2
  fi
fi

echo "aind: work item $ID -> $TARGET"
