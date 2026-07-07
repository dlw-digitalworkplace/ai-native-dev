#!/usr/bin/env bash
# aind-dream.sh <phase> [args]
#
# Mechanics for the dreaming phase — the cross-story feedback loop that turns the flow's exhaust
# (lessons-learned records on the lessons branch) into proposed improvements to the project's own
# .claude config, delivered as ONE human-gated PR. The command /aind:dream orchestrates; all git/gh
# mechanics live here so the warm orchestrator and the cold dreamer subagent stay thin.
#
# Phases:
#   digest                          Fetch the lessons branch and print every unprocessed record
#                                   (.aind/lessons/new/*.md) — the cold dreamer's input. Reads from
#                                   the branch tip WITHOUT checking it out (git show), so the working
#                                   tree is untouched. Exits 9 if there are no unprocessed lessons.
#   start   <dream-branch>          Branch off the integration branch for the config PR (clean-tree
#                                   guarded, like the code-PR opener). Branch must be aind/dream/<…>.
#   open-pr <dream-branch> [title]  Push the dream branch and open a PR targeting the integration
#                                   branch, carrying an AIND-DREAM marker. Body (the cluster summary,
#                                   consumed lessons, any parking-lot notes) is read from stdin.
#   consume <archive|reject> <lesson-id…>   Move the named records out of new/ on the lessons branch
#                                   — to archive/ (folded into the PR) or rejected/ (curated out as
#                                   noise). Unprocessed-but-not-actioned records are left in new/ on
#                                   purpose, so they remain in the pool for future pattern detection.
#   note                            Append a structural parking-lot note (body on stdin) to
#                                   .aind/parking-lot.md on the lessons branch — for a suspected
#                                   FLOW problem the dreamer must NOT encode as a config diff.
#
# The lessons branch and the parking-lot are updated via the same throwaway-index plumbing as the
# emitter (aind-common.sh), so no phase here ever checks out the lessons branch.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

PHASE="${1:-}"
[[ -n "$PHASE" ]] || aind_die "usage: aind-dream.sh <digest|start|open-pr|consume|note> [args]"
aind_require_cmd git

LESSONS_BRANCH="$(aind_lessons_branch)"

# Commit a temp-index tree to the lessons branch (shared by consume + note). Expects GIT_INDEX_FILE
# to be exported and populated by the caller. Args: <parent> <message>.
commit_lessons_index() {
  local parent="$1" msg="$2" tree
  tree="$(git write-tree)"
  unset GIT_INDEX_FILE
  aind_lessons_push "$tree" "$parent" "$msg" >/dev/null
}

case "$PHASE" in
  digest)
    REF="$(aind_lessons_ref)"
    [[ -n "$REF" ]] || { echo "aind: no lessons branch yet ($LESSONS_BRANCH) — nothing to dream on"; exit 9; }
    mapfile -t FILES < <(git ls-tree -r --name-only "$REF" -- ".aind/lessons/new/" 2>/dev/null | sort)
    (( ${#FILES[@]} > 0 )) || { echo "aind: no unprocessed lessons in ${LESSONS_BRANCH}:.aind/lessons/new/ — nothing to dream on"; exit 9; }
    echo "===== UNPROCESSED LESSONS (${#FILES[@]}) — from ${LESSONS_BRANCH} ====="
    for f in "${FILES[@]}"; do
      echo "----- ${f##*/} -----"
      git show "${REF}:${f}"
      echo
    done
    echo "==================================================================="
    ;;

  start)
    BRANCH="${2:-}"
    [[ -n "$BRANCH" ]] || aind_die "usage: aind-dream.sh start <dream-branch>"
    [[ "$BRANCH" =~ ^aind/dream/[A-Za-z0-9._-]+$ ]] \
      || aind_die "dream branch '$BRANCH' must be aind/dream/<name> (e.g. aind/dream/$(date -u +%Y%m%d))"
    aind_require_env AIND_INTEGRATION_BRANCH
    if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
      aind_die "working tree has uncommitted changes — commit or stash them before starting (this command won't stash for you)"
    fi
    git fetch origin "$AIND_INTEGRATION_BRANCH" --quiet
    git checkout -B "$BRANCH" "origin/$AIND_INTEGRATION_BRANCH" >/dev/null 2>&1 \
      || git checkout -B "$BRANCH" "$AIND_INTEGRATION_BRANCH"
    echo "aind: on branch $BRANCH (off $AIND_INTEGRATION_BRANCH) — apply the approved .claude changes, commit, then run 'open-pr'"
    ;;

  open-pr)
    BRANCH="${2:-}"
    TITLE="${3:-}"
    [[ -n "$BRANCH" ]] || aind_die "usage: aind-dream.sh open-pr <dream-branch> [title]  (body on stdin)"
    aind_require_env AIND_GH_REPO AIND_INTEGRATION_BRANCH
    aind_require_cmd gh
    [[ -n "$TITLE" ]] || TITLE="Dreaming: proposed .claude improvements"

    git fetch origin "$AIND_INTEGRATION_BRANCH" --quiet
    if [[ "$(git rev-list --count "origin/${AIND_INTEGRATION_BRANCH}..${BRANCH}")" == "0" ]]; then
      aind_die "no commits on $BRANCH beyond $AIND_INTEGRATION_BRANCH — apply and commit the approved changes before opening the PR"
    fi
    git push -u origin "$BRANCH" --quiet

    SUMMARY="$(cat)"
    [[ -n "$SUMMARY" ]] || aind_die "empty PR body — feed the cluster summary on stdin"
    BODY_FILE="$(mktemp)"
    trap 'rm -f "$BODY_FILE"' EXIT
    {
      echo "<!-- AIND-DREAM cycle -->"
      echo "_Proposed by the dreaming phase from accumulated lessons-learned records. Every change is"
      echo "individually reviewable — accept, adjust, or reject before merge._"
      echo
      printf '%s\n' "$SUMMARY"
    } > "$BODY_FILE"

    PR_URL="$(gh pr create \
      --repo "$AIND_GH_REPO" \
      --base "$AIND_INTEGRATION_BRANCH" \
      --head "$BRANCH" \
      --title "$TITLE" \
      --body-file "$BODY_FILE")"
    echo "aind: opened dream PR"
    echo "$PR_URL"
    ;;

  consume)
    ACTION="${2:-}"
    shift 2 2>/dev/null || true
    case "$ACTION" in archive|reject) ;; *) aind_die "usage: aind-dream.sh consume <archive|reject> <lesson-id…>" ;; esac
    (( $# > 0 )) || aind_die "consume: name at least one lesson id (the filename stem, without .md)"
    PARENT="$(aind_lessons_ref)"
    [[ -n "$PARENT" ]] || aind_die "no lessons branch ($LESSONS_BRANCH) — nothing to consume"
    DEST_DIR=".aind/lessons/${ACTION}"; [[ "$ACTION" == "archive" ]] || DEST_DIR=".aind/lessons/rejected"

    TMP_INDEX="$(mktemp)"; rm -f "$TMP_INDEX"
    trap 'rm -f "$TMP_INDEX"' EXIT
    export GIT_INDEX_FILE="$TMP_INDEX"
    git read-tree "$PARENT"
    moved=0
    for id in "$@"; do
      id="${id%.md}"
      src=".aind/lessons/new/${id}.md"
      blob="$(git rev-parse --verify --quiet "${PARENT}:${src}" || true)"
      if [[ -z "$blob" ]]; then echo "aind: warning — no unprocessed lesson '$id' (skipped)" >&2; continue; fi
      git update-index --add --cacheinfo 100644 "$blob" "${DEST_DIR}/${id}.md"
      git update-index --force-remove "$src"
      moved=$((moved+1))
    done
    (( moved > 0 )) || aind_die "consume: none of the named lessons were found in new/"
    commit_lessons_index "$PARENT" "dream: ${ACTION} ${moved} lesson(s)"
    echo "aind: moved ${moved} lesson(s) to ${ACTION}/ on ${LESSONS_BRANCH}"
    ;;

  note)
    BODY="$(cat)"
    [[ -n "$BODY" ]] || aind_die "empty note — feed the parking-lot note on stdin"
    PARENT="$(aind_lessons_ref)"
    STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    PL=".aind/parking-lot.md"

    NEW="$(mktemp)"; TMP_INDEX="$(mktemp)"; rm -f "$TMP_INDEX"
    trap 'rm -f "$NEW" "$TMP_INDEX"' EXIT
    if [[ -n "$PARENT" ]] && git rev-parse --verify --quiet "${PARENT}:${PL}" >/dev/null; then
      git show "${PARENT}:${PL}" > "$NEW"
    else
      { echo "# AIND dreaming — parking lot"; echo; echo "Suspected FLOW-level problems raised by the dreamer for a human to consider."; echo "These are deliberately NOT encoded as config diffs (the dreamer may not change the flow)."; echo; } > "$NEW"
    fi
    { echo "## ${STAMP}"; printf '%s\n' "$BODY"; echo; } >> "$NEW"

    export GIT_INDEX_FILE="$TMP_INDEX"
    [[ -n "$PARENT" ]] && git read-tree "$PARENT"
    blob="$(git hash-object -w "$NEW")"
    git update-index --add --cacheinfo 100644 "$blob" "$PL"
    commit_lessons_index "$PARENT" "dream: parking-lot note"
    echo "aind: recorded parking-lot note in ${LESSONS_BRANCH}:${PL}"
    ;;

  *)
    aind_die "unknown phase '$PHASE' (use: digest | start | open-pr | consume | note)"
    ;;
esac
