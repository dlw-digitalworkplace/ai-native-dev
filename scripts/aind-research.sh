#!/usr/bin/env bash
# aind-research.sh — resolve where pre-story research findings are stored, and the file path for a
# given topic. The deterministic mechanics behind the /aind:research command (which does the
# grounding, web research, and writing); this script only owns paths so naming stays consistent.
#
# Verbs:
#   dir              Resolve + create + echo the research directory (absolute path).
#   path "<topic>"   Echo the markdown file path for a topic: <dir>/<YYYY-MM-DD>-<slug>.md
#
# Output location precedence (mirrors the work-item file store):
#   AIND_RESEARCH_DIR (env, or `.research.dir` in aind.settings.json which aind-common.sh maps)
#     -> otherwise <main-checkout>/.aind/research
# The directory is rooted at the MAIN checkout (not $PWD) so it is stable when a phase has cd'd into
# a worktree. A repo-relative override resolves against the main checkout; an absolute one is used
# as-is; a leading ~ is expanded. Findings are always markdown.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

# The MAIN worktree's root — `--git-common-dir` points at the shared `.git`, its parent is main.
_research_main_root() {
  local common
  common="$(git rev-parse --git-common-dir 2>/dev/null)" \
    || aind_die "AIND_RESEARCH_DIR is not set and this is not a git repo — set '.research.dir' in .claude/aind.settings.json (an absolute path) or run inside a repo."
  common="$(cd "$common" && pwd)"
  dirname "$common"
}

# Resolve, create, and echo the absolute research directory.
research_dir() {
  local d="${AIND_RESEARCH_DIR:-}" main
  main="$(_research_main_root)"
  if [[ -z "$d" ]]; then
    d="$main/.aind/research"
  else
    case "$d" in
      "~"|"~/"*)     d="${HOME}${d#\~}" ;;   # expand leading ~
      /*|?:/*|?:\\*) : ;;                     # already absolute (unix or Windows drive)
      *)             d="$main/$d" ;;          # repo-relative → resolve against main checkout
    esac
  fi
  mkdir -p "$d" 2>/dev/null || aind_die "cannot create research dir '$d' (check the path / permissions)"
  ( cd "$d" && pwd )
}

# Slugify a topic into a filename-safe token: lowercase, non-alphanumerics → '-', collapse and trim
# repeated '-', cap the length so a long question doesn't make an unwieldy filename.
_slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9' '-' \
    | sed -E 's/-+/-/g; s/^-//; s/-$//' \
    | cut -c1-60 \
    | sed -E 's/-$//'
}

# Echo the markdown file path for a topic.
research_path() {
  local topic="$1" slug
  [[ -n "$topic" ]] || aind_die "usage: aind-research.sh path \"<topic>\""
  slug="$(_slugify "$topic")"
  [[ -n "$slug" ]] || slug="research"
  echo "$(research_dir)/$(date +%Y-%m-%d)-${slug}.md"
}

cmd="${1:-}"
case "$cmd" in
  dir)  research_dir ;;
  path) shift; research_path "${1:-}" ;;
  ""|-h|--help|help)
    cat >&2 <<'USAGE'
aind-research.sh — research findings paths
  dir              resolve + create + echo the research directory
  path "<topic>"   echo <dir>/<YYYY-MM-DD>-<slug>.md for a topic
USAGE
    [[ "$cmd" == "" ]] && exit 2 || exit 0 ;;
  *) aind_die "unknown verb '$cmd' (expected: dir | path)" ;;
esac
