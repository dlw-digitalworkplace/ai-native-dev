#!/usr/bin/env bash
# aind-writing.sh — print the effective writing guide for human-facing text.
#
# Every AIND command/agent that writes something a human reads (work-item comments, PR bodies,
# review threads/replies, plan files, console messages) runs this once at the start and follows
# the output. It combines:
#   1. the active reading level — `.writing.level` (plain | standard | technical, default standard)
#      from aind.settings.json, mapped by aind-common.sh to AIND_WRITING_LEVEL;
#   2. the plugin's default guide (writing/guide.md);
#   3. the project's own rules, if `.claude/writing-guide.md` exists (walk-up from $PWD) — these
#      are printed last and win on conflict.
#
# Best-effort: this script ALWAYS exits 0. A bad level degrades to "standard", a missing guide to
# a short built-in fallback, each with a one-line WARN on stderr — it must never block a phase.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh" 2>/dev/null || true
set +e

level="$(printf '%s' "${AIND_WRITING_LEVEL:-standard}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$level" in
  plain|standard|technical) ;;
  *) echo "aind: [WARN] writing.level '$level' is not plain|standard|technical — using 'standard'" >&2
     level="standard" ;;
esac
echo "Active writing level: $level"
echo

guide="$SCRIPT_DIR/../writing/guide.md"
if [[ -f "$guide" ]]; then
  tr -d '\r' < "$guide"
else
  echo "aind: [WARN] default writing guide not found at $guide — using the short fallback" >&2
  cat <<'EOF'
# AIND writing guide (fallback)

- Lead with the ask: start with "**What I need from you:**" and numbered yes/no questions.
- One idea per sentence. Use bullets and tables. Keep paragraphs to 3 sentences or fewer.
- Use common words. Explain any needed jargon once. No filler or hedging.
- Label facts "Found:" and guesses "Assumed:".
- End every phase in the console with "**Done:** / **Needs you:** / **Next:**" lines.
- Always write in English.
- Plans and PR bodies follow these rules too: keep technical names exact in backticks, and explain
  everything around them in plain sentences.
EOF
fi

# Project rules: the first .claude/writing-guide.md found walking up from $PWD.
dir="$PWD"
while :; do
  if [[ -f "$dir/.claude/writing-guide.md" ]]; then
    echo
    echo "## Project rules (these win on conflict)"
    echo
    tr -d '\r' < "$dir/.claude/writing-guide.md"
    break
  fi
  [[ "$dir" == "/" || -z "$dir" ]] && break
  dir="$(dirname "$dir")"
done

exit 0
