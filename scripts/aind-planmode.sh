#!/usr/bin/env bash
# aind-planmode.sh — echo the configured planning run-mode: auto | attended | headless.
#
# Resolves AIND_PLAN_MODE (from the environment, or `.planning.mode` in aind.settings.json, which
# aind-common.sh maps for us), defaulting to "auto". `/aind:plan` uses this as the DEFAULT run mode
# when the caller didn't pass an explicit mode argument:
#   attended  — always spar interactively (requires an AskUserQuestion-capable host)
#   headless  — never spar; draft + thread + open the PR (today's proceed-on-assumption path)
#   auto      — decide per run: attended if the host can ask and it isn't a headless `claude -p` run
#
# An explicit setting/env value overrides auto-detection — so a dev can force headless even in an
# interactive session (e.g. kick off planning before bed, review the PR in the morning). An unknown
# value degrades to "auto" rather than erroring.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

mode="$(printf '%s' "${AIND_PLAN_MODE:-auto}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$mode" in
  auto|attended|headless) echo "$mode" ;;
  *) echo "auto" ;;
esac
