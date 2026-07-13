#!/usr/bin/env bash
# aind-links.sh write <work-item-id> [plan-pr-url]
# aind-links.sh parse                      (reads a PR body on stdin)
#
# The AIND-LINKS block is a machine-parseable HTML comment carried in a PR
# body. It is invisible in the rendered PR but lets a cold agent resolve the work item and
# plan from artifacts alone (no ADO round-trip). The work-item ID is the join value; branch
# names are never encoded (a branch is reached through its PR).
#
# SPIKE (ADO code host): GitHub preserves HTML comments in PR bodies, so the block is invisible
# there. If a live ADO run shows ADO strips HTML comments from PR descriptions, switch the ADO
# carrier here to a display:none span (as aind-comment.sh uses for ADO work-item fields) or a
# fenced marker, and make `parse` tolerant of that form. Both `write` and `parse` are host-neutral
# today on the assumption ADO preserves the comment — validate before relying on invisibility.
#
#   write : emit the block to stdout (work-item URL + plan path [+ plan-PR URL]).
#   parse : read a PR body on stdin, print the block's key: value lines.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

MODE="${1:-}"

case "$MODE" in
  write)
    ID="${2:-}"
    PLAN_PR_URL="${3:-}"
    [[ -n "$ID" ]] || aind_die "usage: aind-links.sh write <work-item-id> [plan-pr-url]"
    aind_require_env AIND_ADO_ORG AIND_ADO_PROJECT
    ORG="$(aind_org)"
    WORKITEM_URL="${ORG}/${AIND_ADO_PROJECT}/_workitems/edit/${ID}"
    {
      echo "<!-- AIND-LINKS"
      echo "work-item: ${WORKITEM_URL}"
      echo "plan: /plans/${ID}/plan.md"
      [[ -n "$PLAN_PR_URL" ]] && echo "plan-pr: ${PLAN_PR_URL}"
      echo "-->"
    }
    ;;
  parse)
    # Extract the lines between the AIND-LINKS marker and the closing -->.
    awk '
      /<!-- AIND-LINKS/ { inblock=1; next }
      inblock && /-->/  { inblock=0 }
      inblock           { print }
    '
    ;;
  *)
    aind_die "usage: aind-links.sh write <work-item-id> [plan-pr-url] | aind-links.sh parse"
    ;;
esac
