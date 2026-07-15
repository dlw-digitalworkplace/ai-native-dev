#!/usr/bin/env bash
# aind-worktree.sh — per-work-item git worktrees, so multiple items can be worked in parallel from
# one local clone. Opt-in: the feature is ON when a project ships `.claude/aind-worktree.config.json`
# and OFF (every command behaves exactly as before) when that file is absent.
#
# Model: every AIND session runs in the MAIN checkout (cwd = repo root, on the integration branch)
# and *drives* a worktree by path. A phase that creates a PR (plan, implement) gets its own worktree
# under `worktreeRoot` (default `.claude/worktrees/<id>-<phase>`); the PR-creating scripts cd into it
# in their own subprocess (so the session's cwd is never moved). Close-out (approve-plan / complete)
# removes the worktree from the main checkout — a process can never remove its own cwd worktree.
#
# Verbs (stdout = the requested value only; all diagnostics go to stderr):
#   enabled                              exit 0 if worktrees are configured, 1 otherwise (no jq).
#   root                                 print the absolute worktree root.
#   path   <id> <phase>                  print the absolute worktree path for <id>-<phase>.
#   ensure <id> <phase> <branch> <ref>   create-or-reuse the worktree checked out on <branch>
#                                        (new branch off <ref> when creating), copy the configured
#                                        files in, and print its absolute path.
#   list                                 list AIND-managed worktrees + their branches.
#   remove <id> <phase>                  tear the worktree down (never --force; refuses if cwd is
#                                        inside it). The caller deletes the branch afterwards.
#   prune                                sweep managed worktrees whose branch is gone from origin.
#
# Config file (.claude/aind-worktree.config.json):
#   { "worktreeRoot": ".claude/worktrees",
#     "copyFiles": [".claude/aind.env", ".claude/settings.local.json", ".env"] }
# copyFiles are gitignored files OR folders a fresh worktree would lack (config, secrets, project
# runtime env, editor settings like .vscode/); each is copied in at creation (a directory
# recursively) and removed again before teardown.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

# The MAIN worktree's root, resolved regardless of whether we are currently in a linked worktree.
# `--git-common-dir` points at the shared `.git`; its parent is the main checkout.
aind_wt_main_root() {
  local common
  common="$(git rev-parse --git-common-dir 2>/dev/null)" || aind_die "not inside a git repository"
  common="$(cd "$common" && pwd)"
  dirname "$common"
}

aind_wt_config_file() { echo "$(aind_wt_main_root)/.claude/aind-worktree.config.json"; }

# Cheap predicate — no jq. Worktrees are enabled iff the config file exists.
aind_wt_enabled() { [[ -f "$(aind_wt_config_file)" ]]; }

# Absolute worktree root from the config's worktreeRoot (default .claude/worktrees), repo-relative
# paths resolved against the main checkout.
aind_wt_root() {
  aind_require_cmd jq
  local main cfg root
  main="$(aind_wt_main_root)"
  cfg="$main/.claude/aind-worktree.config.json"
  [[ -f "$cfg" ]] || aind_die "worktrees not configured (no .claude/aind-worktree.config.json)"
  # Windows jq emits CRLF line endings — strip the trailing \r or every path we build gains a
  # phantom carriage return that fails filesystem tests. (Same CRLF family as the other AIND scripts.)
  root="$(jq -r '.worktreeRoot // ".claude/worktrees"' "$cfg" | tr -d '\r')"
  [[ -n "$root" && "$root" != "null" ]] || root=".claude/worktrees"
  case "$root" in
    /*|?:/*|?:\\*) echo "$root" ;;          # already absolute (unix or Windows drive)
    *)             echo "$main/$root" ;;     # repo-relative
  esac
}

aind_wt_path() {
  local id="$1" phase="$2"
  [[ -n "$id" && -n "$phase" ]] || aind_die "usage: path <id> <phase>"
  echo "$(aind_wt_root)/${id}-${phase}"
}

# Copy every configured copyFiles entry from the main checkout into the worktree (mkdir -p parents;
# a missing source is skipped with a warning, not a hard error).
aind_wt_copy_files() {
  local wt="$1" main cfg f src dst
  main="$(aind_wt_main_root)"
  cfg="$main/.claude/aind-worktree.config.json"
  [[ -f "$cfg" ]] || return 0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    src="$main/$f"; dst="$wt/$f"
    if [[ -d "$src" ]]; then
      # Folder entry: replace any existing copy (avoids cp's copy-into-existing-dir nesting) and
      # recurse. Self-heals on a reuse/refresh.
      mkdir -p "$(dirname "$dst")"; rm -rf "$dst"
      cp -rf "$src" "$dst" && echo "aind: copied $f/ (folder) into the worktree" >&2 \
        || echo "aind: [WARN] could not copy folder $f into the worktree — skipped" >&2
    elif [[ -e "$src" ]]; then
      mkdir -p "$(dirname "$dst")"
      cp -f "$src" "$dst" && echo "aind: copied $f into the worktree" >&2 \
        || echo "aind: [WARN] could not copy $f into the worktree — skipped" >&2
    else
      echo "aind: [WARN] copyFiles entry not found, skipped: $f" >&2
    fi
  done < <(jq -r '.copyFiles[]?' "$cfg" 2>/dev/null | tr -d '\r')
}

# Is $PWD inside <dir>? (normalised, so /c/… vs C:/… does not fool it.)
aind_wt_pwd_inside() {
  local dir="$1" d p
  d="$(cd "$dir" 2>/dev/null && pwd)" || return 1
  p="$(pwd)"
  case "$p/" in "$d/"*) return 0 ;; *) return 1 ;; esac
}

case "${1:-}" in
  enabled)
    aind_wt_enabled
    ;;

  root)
    aind_wt_root
    ;;

  path)
    aind_wt_path "${2:-}" "${3:-}"
    ;;

  ensure)
    ID="${2:-}"; PHASE="${3:-}"; BRANCH="${4:-}"; REF="${5:-}"
    [[ -n "$ID" && -n "$PHASE" && -n "$BRANCH" && -n "$REF" ]] \
      || aind_die "usage: ensure <id> <phase> <branch> <start-ref>"
    aind_require_cmd git jq
    WT="$(aind_wt_path "$ID" "$PHASE")"

    if [[ -f "$WT/.git" ]]; then
      # Already a registered worktree — reuse it (refresh the copied config, leave the branch alone).
      echo "aind: reusing worktree $WT" >&2
      aind_wt_copy_files "$WT"
      echo "$WT"
      exit 0
    fi
    [[ -e "$WT" ]] && aind_die "worktree path $WT exists but is not a git worktree — remove it or pick another worktreeRoot"

    # Fetch the start ref's branch so the new worktree branches from the latest remote state.
    if [[ "$REF" == origin/* ]]; then
      git fetch origin "${REF#origin/}" --quiet 2>/dev/null || true
    fi
    mkdir -p "$(dirname "$WT")"
    git worktree add -B "$BRANCH" "$WT" "$REF" >&2 \
      || aind_die "git worktree add failed for $WT on $BRANCH (off $REF)"
    echo "aind: created worktree $WT on branch $BRANCH (off $REF)" >&2
    aind_wt_copy_files "$WT"
    echo "$WT"
    ;;

  ensure-plan)
    # Convenience for /aind:plan: create-or-reuse the plan worktree (the plan branch is derivable),
    # so the command can author plans/<id>/plan.md INTO the worktree before the PR is opened.
    ID="${2:-}"
    [[ -n "$ID" ]] || aind_die "usage: ensure-plan <id>"
    aind_require_env AIND_INTEGRATION_BRANCH
    exec bash "$SCRIPT_DIR/aind-worktree.sh" ensure "$ID" plan "$(aind_plan_branch "$ID")" "origin/$AIND_INTEGRATION_BRANCH"
    ;;

  list)
    aind_require_cmd git
    root="$(aind_wt_root)"
    # `git worktree list --porcelain` prints native paths (C:/… on Windows); normalise our root to
    # the same form so the prefix filter matches (no-op off Windows, where cygpath is absent).
    root="$(cygpath -m "$root" 2>/dev/null || echo "$root")"
    git worktree list --porcelain 2>/dev/null | awk -v root="$root" '
      /^worktree /   { wt=substr($0,10) }
      /^branch /     { br=substr($0,8) }
      /^$/           { if (index(wt, root)==1) printf "%s\t%s\n", wt, br; wt=""; br="" }
      END            { if (wt!="" && index(wt, root)==1) printf "%s\t%s\n", wt, br }
    '
    ;;

  remove)
    ID="${2:-}"; PHASE="${3:-}"
    [[ -n "$ID" && -n "$PHASE" ]] || aind_die "usage: remove <id> <phase>"
    aind_require_cmd git jq
    WT="$(aind_wt_path "$ID" "$PHASE")"

    if [[ ! -f "$WT/.git" ]]; then
      echo "aind: no worktree at $WT — nothing to remove" >&2
      exit 0
    fi
    if aind_wt_pwd_inside "$WT"; then
      aind_die "refusing to remove $WT: this session is inside it (a process cannot delete its own working directory). Run close-out from the main checkout, or 'aind-worktree.sh prune' later."
    fi

    # Delete the files we copied in (they are untracked and would block a clean removal).
    main="$(aind_wt_main_root)"; cfg="$main/.claude/aind-worktree.config.json"
    if [[ -f "$cfg" ]]; then
      while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        rm -rf "$WT/$f" 2>/dev/null || true    # -rf so copied folders are removed too
      done < <(jq -r '.copyFiles[]?' "$cfg" 2>/dev/null | tr -d '\r')
    fi

    if git worktree remove "$WT" 2>/tmp/aind-wt-remove.$$; then
      echo "aind: removed worktree $WT" >&2
    else
      msg="$(cat /tmp/aind-wt-remove.$$ 2>/dev/null)"; rm -f /tmp/aind-wt-remove.$$
      aind_die "could not remove worktree $WT (uncommitted work in it?) — resolve it, then re-run. Never force-removed. Detail: $msg"
    fi
    rm -f /tmp/aind-wt-remove.$$ 2>/dev/null || true
    git worktree prune 2>/dev/null || true
    ;;

  prune)
    aind_require_cmd git
    root="$(aind_wt_root)"
    root="$(cygpath -m "$root" 2>/dev/null || echo "$root")"
    git worktree prune 2>/dev/null || true
    # Remove any managed worktree whose branch no longer exists on origin (merged + auto-deleted),
    # when its tree is clean. Never --force.
    git worktree list --porcelain 2>/dev/null | awk -v root="$root" '
      /^worktree /{wt=substr($0,10)} /^branch /{br=substr($0,8)}
      /^$/{ if (index(wt,root)==1 && br!="") printf "%s\t%s\n", wt, br; wt=""; br="" }
      END{ if (wt!="" && index(wt,root)==1 && br!="") printf "%s\t%s\n", wt, br }
    ' | while IFS=$'\t' read -r wt br; do
      short="${br#refs/heads/}"
      if [[ -z "$(git ls-remote --heads origin "$short" 2>/dev/null)" ]]; then
        if git worktree remove "$wt" 2>/dev/null; then
          echo "aind: pruned worktree $wt (branch $short gone from origin)" >&2
          git branch -D "$short" >/dev/null 2>&1 || true
        else
          echo "aind: [WARN] $wt has a gone branch but is not clean — left in place" >&2
        fi
      fi
    done
    git worktree prune 2>/dev/null || true
    ;;

  *)
    aind_die "usage: aind-worktree.sh enabled|root|path|ensure|list|remove|prune [args]"
    ;;
esac
