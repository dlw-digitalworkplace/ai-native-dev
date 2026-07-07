#!/usr/bin/env bash
# aind-emit-lesson.sh <work-item-id> <agent> <severity> [source] [area]      (Observation on stdin)
#
# Append ONE lessons-learned record to the lessons branch — the single sanctioned way an agent emits
# a lesson, the exhaust twin of aind-comment.sh (the single sanctioned way to post an ADO comment).
# The record is a self-report of what happened + WHY, so the cold dreamer can later synthesise it; it
# never proposes a fix (that is the dreamer's job). Human PR feedback becomes lessons the same way —
# an agent that acted on a human's correction/suggestion emits a record citing the source thread.
#
# Arguments:
#   <work-item-id>  the story this lesson came from (the join value).
#   <agent>         the emitting agent: intake | planner | coder | reviewer | polish.
#   <severity>      how much a human had to step in (the highest-value signal):
#                     observation  agent noticed friction itself, no human involved
#                     suggestion   a human offered an improvement that was accepted
#                     correction   a human overrode a decision (tiebreak / rejected assumption)
#                     blocker      a human had to abort/redirect the agent
#   [source]        where it came from — a PR/thread/comment URL, or "self-report" (the default).
#   [area]          OPTIONAL, non-binding guess at the implicated config file (e.g. skills/lint,
#                   rules/frontend.md). The dreamer decides the real target; leave empty if unsure.
# Observation body is read from stdin (feed it as a direct heredoc — one command, no `cat |` pipe):
#   bash "…/aind-emit-lesson.sh" 42 reviewer correction "<pr-thread-url>" rules/api.md <<'EOF'
#   <what happened + why — concrete; the cause, not a proposed fix>
#   EOF
#
# The record lands at .aind/lessons/new/<id>.md on the lessons branch. Emission never checks out that
# branch or disturbs the working tree: the commit is built in a throwaway index so an agent can emit
# in the middle of its own session without being pulled off its branch.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

ID="${1:-}"
AGENT="${2:-}"
SEVERITY="${3:-}"
SOURCE="${4:-self-report}"
AREA="${5:-}"
[[ -n "$ID" && -n "$AGENT" && -n "$SEVERITY" ]] \
  || aind_die "usage: aind-emit-lesson.sh <work-item-id> <agent> <severity> [source] [area]  (Observation on stdin)"

aind_require_cmd git
git rev-parse --git-dir >/dev/null 2>&1 || aind_die "not inside a git repository"

case "$SEVERITY" in
  observation|suggestion|correction|blocker) ;;
  *) aind_die "invalid severity '$SEVERITY' (use: observation | suggestion | correction | blocker)" ;;
esac

# Phase is derived from the agent so the emitter never has to pass it.
case "$AGENT" in
  intake)                 PHASE="intake" ;;
  planner)                PHASE="plan" ;;
  coder|reviewer|polish)  PHASE="build" ;;
  *)                      PHASE="unknown" ;;
esac

BODY="$(cat)"
[[ -n "$BODY" ]] || aind_die "empty observation body — feed the Observation on stdin (heredoc)"

LESSONS_BRANCH="$(aind_lessons_branch)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LESSON_ID="${ID}-${AGENT}-${STAMP}"
LESSON_PATH=".aind/lessons/new/${LESSON_ID}.md"

REC="$(mktemp)"
TMP_INDEX="$(mktemp)"; rm -f "$TMP_INDEX"   # a non-existent path is an empty index
trap 'rm -f "$REC" "$TMP_INDEX"' EXIT

{
  echo "---"
  echo "id: ${LESSON_ID}"
  echo "work_item: ${ID}"
  echo "agent: ${AGENT}"
  echo "phase: ${PHASE}"
  echo "severity: ${SEVERITY}"
  echo "source: ${SOURCE}"
  [[ -n "$AREA" ]] && echo "area: ${AREA}"
  echo "---"
  echo
  echo "## Observation"
  printf '%s\n' "$BODY"
} > "$REC"

PARENT="$(aind_lessons_ref)"

# Build the new tree in a throwaway index: seed from the branch tip (if any), add the record blob.
export GIT_INDEX_FILE="$TMP_INDEX"
[[ -n "$PARENT" ]] && git read-tree "$PARENT"
BLOB="$(git hash-object -w "$REC")"
git update-index --add --cacheinfo 100644 "$BLOB" "$LESSON_PATH"
TREE="$(git write-tree)"
unset GIT_INDEX_FILE

COMMIT="$(aind_lessons_push "$TREE" "$PARENT" "lesson: ${AGENT} on AB#${ID} (${SEVERITY})")"

if git remote get-url origin >/dev/null 2>&1; then
  echo "aind: emitted ${SEVERITY} lesson ${LESSON_ID} to ${LESSONS_BRANCH} (${COMMIT:0:9})"
else
  echo "aind: emitted ${SEVERITY} lesson ${LESSON_ID} to local ${LESSONS_BRANCH} — no origin remote, not pushed (${COMMIT:0:9})"
fi
