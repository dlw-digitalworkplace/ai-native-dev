#!/usr/bin/env bash
# aind-status.sh <work-item-id> <new-state> [agent]
# Moves the work item to a new AIND state (invariant: exactly one AIND status per item).
#
# The mechanism depends on the tracker backend (AIND_TRACKER): on Azure DevOps Boards the state is
# the single `AIND status - <state>` tag (written via a REST replace, verified, and optionally
# mirrored into the native ADO State); in the file backend it is the scalar `state:` front-matter
# field. Both go through the tracker adapter, so callers stay backend-blind. The optional 3rd arg is
# the calling phase's agent, used only to attribute a native-State mirror-failure lesson (ADO only).
#
# Usage: aind-status.sh 123 "Intake approved"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-tracker.sh
source "$SCRIPT_DIR/aind-tracker.sh"

ID="${1:-}"
NEW_STATE="${2:-}"
AGENT="${3:-}"
[[ -n "$ID" && -n "$NEW_STATE" ]] || aind_die "usage: aind-status.sh <work-item-id> <new-state> [agent]"
tracker_require
tracker_set_state "$ID" "$NEW_STATE" "$AGENT"
