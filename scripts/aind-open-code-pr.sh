#!/usr/bin/env bash
# aind-open-code-pr.sh start        <work-item-id> <branch>
# aind-open-code-pr.sh open         <work-item-id> <branch> [pr-title] [flow]
# aind-open-code-pr.sh start-local  <work-item-id> <branch>            (local same-branch flow)
# aind-open-code-pr.sh resume-local <work-item-id>                     (local same-branch flow)
#
# The GitHub-flow twin of aind-open-plan-pr.sh, for the build phase.
#
#   start : branch off the integration branch and check it out, so the coder implements on a
#           fresh branch. Refuses if a code PR for that branch already exists (no clobber).
#   open  : push the (already-committed) branch and open a code PR that targets the integration
#           branch, mentions AB#<id> (native Boards<->GitHub linking) and carries the AIND-LINKS
#           block — including the plan-PR URL, so an agent re-grounding from the PR alone can reach
#           the spec. The PR is created AFTER the push, so a failure leaves a real, discoverable
#           branch rather than a dangling pointer (create-link-after-push ordering). A trailing
#           `flow` arg (pr|local) overrides config; in the local flow there is no plan PR (the plan
#           rides in this PR's diff) and the "has commits" gate ignores the plan commit.
#   start-local : LOCAL flow — create/reuse the story branch and commit the already-written plan
#           onto it (no PR, no push), so the plan is reviewed in the working tree. Idempotent, so a
#           plan revision just re-commits. Leaves the session on the story branch.
#   resume-local : LOCAL flow — discover the story branch for this id (by the code-branch
#           convention) and check it out, so /aind:implement continues on the same branch. Prints
#           the branch name.
#
# The coding agent chooses the branch name from a fixed convention: <type>/<id>-<short-name>
# (e.g. feat/123-new-component, fix/456-typo). The framework never reaches the branch by deriving
# its name — every later step finds it through the code PR.
#
# Usage:
#   aind-open-code-pr.sh start 123 feat/123-csv-export
#   aind-open-code-pr.sh open  123 feat/123-csv-export "Add CSV export to the reports page"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-forge.sh
source "$SCRIPT_DIR/aind-forge.sh"

MODE="${1:-}"
ID="${2:-}"
BRANCH="${3:-}"
[[ -n "$MODE" && -n "$ID" ]] \
  || aind_die "usage: aind-open-code-pr.sh start|open|start-local <work-item-id> <branch> [pr-title]  |  resume-local <work-item-id>"

aind_require_cmd git
# The forge (gh/az) is only needed by the modes that read or create PRs. The local-flow verbs
# start-local/resume-local are pure local git — they must work with no forge configured/reachable.
case "$MODE" in start|open) forge_require ;; esac

# Resolve the flow mode: pr (default, two-PR flow) | local (same-branch flow). Config drives it
# (AIND_FLOW_MODE, mapped from .flow.mode); an unknown value degrades to pr so the default is never
# silently disabled. The `open` verb also accepts an explicit override argument.
_flow() {
  local m; m="$(printf '%s' "${AIND_FLOW_MODE:-pr}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$m" in local) echo local ;; *) echo pr ;; esac
}

# Enforce the branch convention: <type>/<id>-<short-name>. Keeping the id in the branch makes it
# traceable; the type prefix matches conventional branch naming. (The framework reaches the branch
# through the PR — except the local same-branch flow, which discovers it by this same convention
# because no PR exists yet.) resume-local discovers the branch, so it has none to validate here;
# every other mode is handed the branch explicitly.
if [[ "$MODE" != "resume-local" ]]; then
  [[ -n "$BRANCH" ]] || aind_die "usage: aind-open-code-pr.sh $MODE <work-item-id> <branch> [pr-title]"
  [[ "$BRANCH" =~ ^[a-z]+/${ID}-[A-Za-z0-9._-]+$ ]] \
    || aind_die "branch '$BRANCH' must follow <type>/${ID}-<short-name> (e.g. feat/${ID}-new-component)"
fi

# A code PR already open for this branch means a re-run of the CREATE path, which would conflict on
# push / PR creation. Revising an open PR is a separate flow: re-run /aind:implement, which detects
# the open PR and enters revise mode (aind-revise-code-pr.sh) instead of opening a second PR.
code_pr_exists() {
  [[ -n "$(forge_pr_list open "$BRANCH")" ]]
}

case "$MODE" in
  start)
    aind_require_env AIND_INTEGRATION_BRANCH
    code_pr_exists && aind_die "a code PR already exists for $BRANCH — to change it, re-run /aind:implement (it enters revise mode) instead of opening a new PR"
    if bash "$SCRIPT_DIR/aind-worktree.sh" enabled >/dev/null 2>&1; then
      # Worktree mode: build in a dedicated worktree for this item's implement phase. Its path is
      # printed as `aind: worktree <path>` — that directory is the coder's project root; implement
      # + commit THERE (the session's own cwd stays on the main checkout).
      WT="$(bash "$SCRIPT_DIR/aind-worktree.sh" ensure "$ID" impl "$BRANCH" "origin/$AIND_INTEGRATION_BRANCH")" \
        || aind_die "could not prepare the implement worktree for $ID"
      echo "aind: worktree $WT"
      echo "aind: on branch $BRANCH in the worktree above — implement + commit there, then run 'open'"
    else
      # Don't clobber a dirty working tree: branching off integration with uncommitted tracked
      # changes would drag them onto the new branch. Refuse and let the developer decide — never
      # stash automatically. (Untracked files are fine; they're carried along harmlessly.)
      if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
        aind_die "working tree has uncommitted changes — commit or stash them before starting (this command won't stash for you)"
      fi
      git fetch origin "$AIND_INTEGRATION_BRANCH" --quiet
      git checkout -B "$BRANCH" "origin/$AIND_INTEGRATION_BRANCH" >/dev/null 2>&1 \
        || git checkout -B "$BRANCH" "$AIND_INTEGRATION_BRANCH"
      echo "aind: on branch $BRANCH (off $AIND_INTEGRATION_BRANCH) — implement, commit, then run 'open'"
    fi
    ;;

  open)
    TITLE="${4:-}"
    # Flow override: an explicit 5th arg wins over config (so a command that resolved an arg-level
    # override passes it through); otherwise read config. Unknown -> pr.
    FLOW="${5:-}"; [[ -n "$FLOW" ]] || FLOW="$(_flow)"
    case "$FLOW" in local) ;; *) FLOW="pr" ;; esac
    aind_require_env AIND_ADO_ORG AIND_ADO_PROJECT AIND_INTEGRATION_BRANCH
    [[ -n "$TITLE" ]] || TITLE="Implementation for work item ${ID}"

    code_pr_exists && aind_die "a code PR already exists for $BRANCH — to change it, re-run /aind:implement (it enters revise mode) instead of opening a new PR"

    # Worktree mode: push + open from the implement worktree (where the coder committed). Reuse the
    # one `start` created; the cd is in this subprocess only. The local same-branch flow is
    # single-tree (the story branch lives in the main checkout), so it never uses a worktree.
    if [[ "$FLOW" != "local" ]] && bash "$SCRIPT_DIR/aind-worktree.sh" enabled >/dev/null 2>&1; then
      WT="$(bash "$SCRIPT_DIR/aind-worktree.sh" path "$ID" impl)"
      [[ -f "$WT/.git" ]] || aind_die "implement worktree $WT missing — run 'aind-open-code-pr.sh start' first"
      cd "$WT"
    fi

    # There must be implementation to review. In the local flow the branch also carries the plan
    # commit, so "beyond integration" is not enough — require a code change beyond plans/<id>/.
    git fetch origin "$AIND_INTEGRATION_BRANCH" --quiet
    if [[ "$FLOW" == "local" ]]; then
      if git diff --quiet "origin/${AIND_INTEGRATION_BRANCH}...${BRANCH}" -- . ":(exclude)plans/${ID}/"; then
        aind_die "no implementation on $BRANCH beyond the committed plan — implement and commit code before opening the PR"
      fi
    else
      if [[ "$(git rev-list --count "origin/${AIND_INTEGRATION_BRANCH}..${BRANCH}")" == "0" ]]; then
        aind_die "no commits on $BRANCH beyond $AIND_INTEGRATION_BRANCH — implement and commit before opening the PR"
      fi
    fi

    git push -u origin "$BRANCH" --quiet

    # Resolve the (now merged) plan PR URL so the code PR's AIND-LINKS can point back to the spec. The
    # local flow has no plan PR — the plan rides in THIS PR's diff — so pass no URL (AIND-LINKS then
    # emits just the plan path, which is correct).
    if [[ "$FLOW" == "local" ]]; then
      PLAN_PR_URL=""
      PLAN_NOTE="Includes the implementation plan at \`plans/${ID}/plan.md\` (reviewed locally) — see it for the task breakdown, any data contracts, and the definition of done this PR is validated against."
    else
      PLAN_BRANCH="$(aind_plan_branch "$ID")"
      PLAN_PR_ROW="$(forge_pr_list all "$PLAN_BRANCH")"; PLAN_PR_ROW="${PLAN_PR_ROW%%$'\n'*}"
      PLAN_PR_URL="$(printf '%s' "$PLAN_PR_ROW" | cut -f3)"
      PLAN_NOTE="Implements the merged plan at \`plans/${ID}/plan.md\` — see that plan for the task breakdown, any data contracts, and the definition of done this PR is validated against."
    fi

    LINKS_BLOCK="$(bash "$SCRIPT_DIR/aind-links.sh" write "$ID" "$PLAN_PR_URL")"
    BODY_FILE="$(mktemp)"
    trap 'rm -f "$BODY_FILE"' EXIT
    cat > "$BODY_FILE" <<EOF
Implementation for **AB#${ID}** — ${TITLE}.

${PLAN_NOTE}

${LINKS_BLOCK}
EOF

    PR_URL="$(forge_pr_create "$AIND_INTEGRATION_BRANCH" "$BRANCH" "Implement: ${TITLE} (AB#${ID})" "$BODY_FILE" "$ID")"

    # Record the PR on the work item (best-effort; no-op for the ADO tracker, which links natively at
    # create time — appends the URL to the item's links for the file backend).
    bash "$SCRIPT_DIR/aind-tracker.sh" link-pr "$ID" "$PR_URL" >/dev/null 2>&1 || true

    echo "aind: opened code PR for work item $ID"
    echo "$PR_URL"
    ;;

  start-local)
    # LOCAL same-branch flow: create (or, on a plan revision, reuse) the story branch and commit the
    # already-written plan onto it — NO PR, NO push. The plan is reviewed locally in the working tree.
    # Leaves the session on the story branch so the developer sees plans/<id>/plan.md in their editor.
    aind_require_env AIND_INTEGRATION_BRANCH
    PLAN_PATH="plans/${ID}/plan.md"
    [[ -f "$PLAN_PATH" ]] || aind_die "plan not found at $PLAN_PATH — write the plan before committing it"
    # Idempotent: reuse an existing story branch for this id (a plan revision); else create it off
    # integration. Discovery is by the id-scoped convention — no PR handle exists yet.
    EXISTING="$(aind_find_story_branch "$ID")"
    if [[ "$(printf '%s' "$EXISTING" | grep -c .)" -gt 1 ]]; then
      aind_die "more than one story branch matches AB#${ID} ($(echo $EXISTING | tr '\n' ' ')) — resolve the duplicate before continuing"
    fi
    if [[ -n "$EXISTING" ]]; then
      [[ "$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)" == "$EXISTING" ]] \
        || git checkout "$EXISTING" >/dev/null 2>&1 \
        || aind_die "could not check out existing story branch $EXISTING — commit or stash your changes first"
      BRANCH="$EXISTING"
      echo "aind: reusing story branch $BRANCH (plan revision)"
    else
      # Untracked plan.md is fine (it rides onto the new branch); refuse only tracked changes.
      if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
        aind_die "working tree has uncommitted changes — commit or stash them before starting (this command won't stash for you)"
      fi
      git fetch origin "$AIND_INTEGRATION_BRANCH" --quiet
      git checkout -B "$BRANCH" "origin/$AIND_INTEGRATION_BRANCH" >/dev/null 2>&1 \
        || git checkout -B "$BRANCH" "$AIND_INTEGRATION_BRANCH"
      echo "aind: created story branch $BRANCH (off $AIND_INTEGRATION_BRANCH)"
    fi
    git add "plans/${ID}/"
    if git diff --cached --quiet; then
      echo "aind: plan unchanged — nothing to commit on $BRANCH"
    else
      git commit -m "Add implementation plan for AB#${ID}" --quiet
      echo "aind: committed $PLAN_PATH on $BRANCH"
    fi
    echo "aind: review the plan locally at $PLAN_PATH, then run /aind:approve-plan $ID (it asks you to confirm)"
    ;;

  resume-local)
    # LOCAL same-branch flow: discover and check out the story branch for this id (created at plan
    # time), so /aind:implement continues on the SAME branch the plan lives on. Prints the branch
    # name on stdout (status goes to stderr) so the caller can capture it.
    BRANCH="$(aind_find_story_branch "$ID")"
    [[ -n "$BRANCH" ]] || aind_die "no local story branch found for AB#${ID} — run /aind:plan $ID in the local flow first (it creates the branch and commits the plan)"
    [[ "$(printf '%s' "$BRANCH" | grep -c .)" -le 1 ]] \
      || aind_die "more than one story branch matches AB#${ID} ($(echo $BRANCH | tr '\n' ' ')) — resolve the duplicate before continuing"
    [[ "$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)" == "$BRANCH" ]] \
      || git checkout "$BRANCH" >/dev/null 2>&1 \
      || aind_die "could not check out story branch $BRANCH — commit or stash your changes first"
    echo "aind: on story branch $BRANCH" >&2
    echo "$BRANCH"
    ;;

  *)
    aind_die "usage: aind-open-code-pr.sh start|open|start-local <work-item-id> <branch> [pr-title]  |  resume-local <work-item-id>"
    ;;
esac
