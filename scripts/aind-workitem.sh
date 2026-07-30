#!/usr/bin/env bash
# aind-workitem.sh <work-item-id>
# Fetches a work item as normalised JSON — the grounding input for intake and the planner.
# Output keys: { id, title, description, acceptanceCriteria, state, dependsOn[], links[] }.
#
# The tracker backend is selected by config (AIND_TRACKER): Azure DevOps Boards or a local
# markdown-file store. description/acceptanceCriteria may be HTML (ADO) or markdown (file) — read
# through the markup. This script is read-only; it never modifies the story.
#
# Usage: aind-workitem.sh 123

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-tracker.sh
source "$SCRIPT_DIR/aind-tracker.sh"

ID="${1:-}"
[[ -n "$ID" ]] || aind_die "usage: aind-workitem.sh <work-item-id>"
tracker_require
tracker_fetch "$ID"
