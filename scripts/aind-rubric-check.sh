#!/usr/bin/env bash
# aind-rubric-check.sh <rubric-path>
# Validates that a project's intake rubric is present and usable. Prints "objective=<n>
# judgment=<m>" and exits 0 on success; otherwise prints a reason on stderr and exits:
#   64  usage error (no path given)
#   2   file missing
#   3   file empty / whitespace-only
#   4   no objective criteria (the gate could never decline a story — unconfigured rubric)
#
# There is deliberately NO fallback to the plugin seed. Onboarding copies the seed into the
# project at setup, so a missing/empty/criteria-less project rubric means setup was skipped or
# a human emptied it — that must be flagged and stop the run, not silently papered over.
#
# A "criterion" is a markdown table data row (not the header/separator) or a `-`/`*` list item
# appearing under a heading whose text contains "Objective" or "Judgment" (case-insensitive) —
# the rubric<->command contract.

set -u

PATH_IN="${1:-}"
[[ -n "$PATH_IN" ]] || { echo "usage: aind-rubric-check.sh <rubric-path>" >&2; exit 64; }

if [[ ! -f "$PATH_IN" ]]; then
  echo "aind: no intake rubric at '$PATH_IN' — run /aind:onboard (or restore the file) before intake." >&2
  exit 2
fi

if ! grep -q '[^[:space:]]' "$PATH_IN"; then
  echo "aind: intake rubric '$PATH_IN' is empty — add criteria (or re-run /aind:onboard) before intake." >&2
  exit 3
fi

counts="$(awk '
  function isSep(l){ return (l ~ /^[[:space:]]*\|?[[:space:]:|-]+\|?[[:space:]]*$/) }
  function isRow(l){ return (l ~ /^[[:space:]]*\|.*\|[[:space:]]*$/) }
  function isList(l){ return (l ~ /^[[:space:]]*[-*][[:space:]]/) }
  BEGIN{ sec="other"; obj=0; jud=0; hdr_obj=0; hdr_jud=0 }
  {
    line=$0; sub(/\r$/,"",line); low=tolower(line)
    if (line ~ /^#{1,6}[[:space:]]/) {
      if (low ~ /objective/) sec="obj"
      else if (low ~ /judg[e]?ment/) sec="jud"
      else sec="other"
      next
    }
    if (sec=="obj") {
      if (isRow(line) && !isSep(line)) { if(!hdr_obj) hdr_obj=1; else obj++ }
      else if (isList(line)) obj++
    } else if (sec=="jud") {
      if (isRow(line) && !isSep(line)) { if(!hdr_jud) hdr_jud=1; else jud++ }
      else if (isList(line)) jud++
    }
  }
  END{ print obj" "jud }
' "$PATH_IN")"

obj="${counts%% *}"; jud="${counts##* }"

if [[ "${obj:-0}" -lt 1 ]]; then
  echo "aind: intake rubric '$PATH_IN' has no objective criteria — the gate cannot decline anything. Add at least one pass/fail criterion under an 'Objective' heading (or re-run /aind:onboard)." >&2
  exit 4
fi

echo "objective=$obj judgment=$jud"
