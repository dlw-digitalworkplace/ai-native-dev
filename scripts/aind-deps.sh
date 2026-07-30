#!/usr/bin/env bash
# aind-deps.sh <work-item-id>
# Resolves a work item's dependencies and reports, for each, whether it is IMPLEMENTED yet — the
# grounding for intake's dependency gate.
#
# A "dependency" is a story that must be completed before this one can start (an ADO Predecessor link,
# or a `dependsOn:` entry in the file backend). For each it classifies:
#   IMPLEMENTED      — its AIND status is "Implementation complete" (ADO: or, for a non-AIND
#                      dependency, a done-like ADO state: Closed / Done / Resolved / Completed).
#   NOT IMPLEMENTED  — still in progress / not yet complete.
#   UNKNOWN          — the linked item could not be read (deleted / no access / missing file).
#
# Output: a human list, a one-line summary, and a final machine line:
#   DEPS_VERDICT: NONE | MET | UNMET
# Intake reads DEPS_VERDICT to gate the verdict — an UNMET dependency declines the story — WITHOUT
# affecting the readiness score. The tracker backend is selected by config (AIND_TRACKER).
#
# Usage: aind-deps.sh 123

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-tracker.sh
source "$SCRIPT_DIR/aind-tracker.sh"

ID="${1:-}"
[[ -n "$ID" ]] || aind_die "usage: aind-deps.sh <work-item-id>"
tracker_require
tracker_deps "$ID"
