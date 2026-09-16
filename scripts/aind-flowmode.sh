#!/usr/bin/env bash
# aind-flowmode.sh — echo the configured flow mode: pr | local.
#
# Resolves AIND_FLOW_MODE (from the environment, or `.flow.mode` in aind.settings.json, which
# aind-common.sh maps for us), defaulting to "pr" — today's behavior. The plan/approve-plan/implement
# commands use this to pick where the plan-review and plan-approval gates live:
#   pr     — the default: plan lives on its own branch and is reviewed as a plan PR; the code branch
#            is separate; every gate is a Pull Request. (Unchanged behavior.)
#   local  — plan and code share ONE story branch; the plan is committed and reviewed locally in the
#            working tree (e.g. VS Code), with no plan PR; /aind:approve-plan needs an explicit
#            confirmation instead of a merged plan PR; /aind:implement continues on the same branch and
#            opens a single code PR at the end.
#
# An explicit setting/env value (or a per-command argument, which the commands resolve above this) is
# authoritative; an unknown value degrades to "pr" rather than erroring — so the default flow is never
# silently disabled by a typo.
#
# Local mode is single-tree by design: the session checks out the story branch in the main checkout so
# the developer sees the committed plan. It is therefore mutually exclusive with the worktree feature;
# if both are configured, this warns (on stderr) but still returns "local" — the branch-owning scripts
# force the single-tree path when flow==local.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

mode="$(printf '%s' "${AIND_FLOW_MODE:-pr}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$mode" in
  pr|local) ;;
  *) mode="pr" ;;
esac

if [[ "$mode" == "local" ]] && bash "$SCRIPT_DIR/aind-worktree.sh" enabled >/dev/null 2>&1; then
  echo "aind: [WARN] flow.mode is 'local' but worktrees are enabled — local mode is single-tree and takes precedence (worktrees ignored for this story)" >&2
fi

echo "$mode"
