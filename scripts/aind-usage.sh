#!/usr/bin/env bash
# aind-usage.sh begin|report <work-item-id> <agent>
#
# Per-phase usage telemetry — the exhaust twin of aind-emit-lesson.sh for TOKENS + TIME. A phase
# brackets its work with two calls: `begin` at the start stamps a marker, `report` at the end
# measures how many tokens the phase consumed (a per-model, per-token-type breakdown) and how long it
# took. It stores RAW USAGE ONLY — never a cost:
#   - the token breakdown is written as a machine-readable JSON ATTACHMENT on the ADO work item (the
#     durable trace / source of truth); one append-only attachment per phase-run;
#   - the wall-clock SECONDS accumulate into one configurable numeric ADO field (queryable per story).
# There is deliberately NO cost, NO rate card, and NO rendered on-item table — pricing is done
# entirely offline against the attachments, so history can be re-priced anytime.
#
# WHY A HOST-AWARE COLLECTOR
# The agent host (Claude Code or GitHub Copilot CLI) is the only component that can see token usage —
# the bash scripts shell out to az/gh/curl and have no view of the model's tokens. Both hosts happen
# to write a per-session events file to disk carrying per-message token counts + ISO timestamps, but
# in different places and shapes. So, mirroring how aind-forge.sh hides the code host, this file
# hides the AGENT host behind one collector with two backends. Measurement is by TIMESTAMP WINDOW:
# `begin` stamps a start marker and `report` sums only the usage inside the window, so attribution is
# per-phase even when several phases share one session. On Claude both the **token** window and the
# **duration** are HEAD-ANCHORED back to this command's invocation turn in the transcript (matched by
# its `<command-message>…</command-message>` envelope), not to `begin`: the command-load + grounding
# turn (a full cache-read) fires a beat before `begin` can run, so anchoring to `begin` would drop it
# from both. Copilot has no invocation tag, so both start at `begin`. The trailing post-`report`
# narration turn is still not captured (report can't see its own future); it is marginal and shrinks
# with phase length, though a phase's closing full-context cache-read leaves a small raw-token tail.
#
#   Claude  : ~/.claude/projects/<slug>/<session>.jsonl — assistant lines carry message.model +
#             message.usage (input/output/cache_creation/cache_read) + top-level ISO `timestamp`.
#             Streaming repeats a message.id, so we DEDUPE by message.id. Subagents (e.g. the reviewer)
#             live under <session>/subagents/agent-*.jsonl and are NOT rolled into the parent — summed
#             too, so a build total includes the reviewer passes. Broken down PER MODEL.
#   Copilot : ~/.copilot/session-state/<session>/events.jsonl — assistant.message events carry
#             data.outputTokens + top-level ISO `timestamp`; workspace.yaml records git_root/cwd.
#             Its events carry no per-message model and no input/cache mid-session, so the Copilot
#             record is a single "copilot" bucket with OUTPUT tokens only. `seconds` is exact on both.
#
# NEVER BREAKS A PHASE. Telemetry is best-effort: a missing marker, no session file (a host that
# exposes nothing), missing tools, or an ADO hiccup all WARN and exit 0. It is fully inert until a
# project opts in (telemetry.enabled in .claude/aind.settings.json).
#
# Config (all from .claude/aind.settings.json via aind-common.sh; nothing hard-coded):
#   AIND_TELEMETRY_ENABLED         true|1|yes to record (anything else / unset -> inert)
#   AIND_TELEMETRY_DURATION_FIELD  ADO field refName for the cumulative seconds total (e.g. Custom.AindDurationSec)
#   AIND_AGENT_HOST (optional)     claude|copilot — force the backend instead of auto-detecting.
# Token detail is stored as an attachment (no field); only time uses a numeric field.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-tracker.sh
# Source the tracker adapter (re-exports aind-common.sh). The write side of telemetry — the
# per-run token-breakdown attachment and the accumulating duration total — goes through the tracker
# verbs (tracker_attach / tracker_field_accumulate) so it lands wherever the item lives (an ADO work
# item or a local markdown file). aind_warn is provided by aind-common.sh.
source "$SCRIPT_DIR/aind-tracker.sh"

# Enabled iff explicitly opted in.
_telemetry_enabled() {
  case "$(printf '%s' "${AIND_TELEMETRY_ENABLED:-}" | tr '[:upper:]' '[:lower:]' | tr -d '\r')" in
    true|1|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# Resolve the user's home. MSYS $HOME can point at a mapped drive (e.g. /h/), so prefer the Windows
# USERPROFILE, converted to an MSYS path. Falls back to $HOME elsewhere.
_home() {
  if [[ -n "${USERPROFILE:-}" ]]; then
    cygpath -u "$USERPROFILE" 2>/dev/null && return 0
    printf '%s\n' "$USERPROFILE"; return 0
  fi
  printf '%s\n' "$HOME"
}

# Canonicalise a path for comparison: to mixed Windows form (cygpath -m gives a drive letter with
# forward slashes, so /c/x and C:\x unify without any backslash juggling), lowercased, no trailing
# slash. Used to match a recorded session cwd/git_root to this repo.
_canon() {
  local p; p="$(cygpath -m "$1" 2>/dev/null || printf '%s' "$1")"
  printf '%s' "$p" | tr -d '\r' | tr '[:upper:]' '[:lower:]' | sed 's#/*$##'
}

# The current working tree root (for matching a session's recorded cwd to this repo).
_repo_root() { git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD"; }

# The MAIN checkout root — where the marker dir lives so `begin` and `report` agree even when the
# session has cd'd into a linked worktree between them (git-common-dir points at <main>/.git from
# anywhere, including a worktree; its parent is the main working tree).
_main_root() {
  local common main
  common="$(git rev-parse --git-common-dir 2>/dev/null)" || { printf '%s' "$PWD"; return; }
  if [[ "$common" != /* && "$common" != [A-Za-z]:* ]]; then
    common="$(cd "$common" 2>/dev/null && pwd)" || common=""
  fi
  if [[ -n "$common" ]]; then
    main="$(dirname "$common")"
    [[ -d "$main" ]] && { printf '%s' "$main"; return; }
  fi
  _repo_root
}

USAGE_DIR="$(_main_root)/.aind/usage"

# ------------------------------------------------------------------------------------------------
# begin — stamp the phase start
# ------------------------------------------------------------------------------------------------
cmd_begin() {
  local id="$1" agent="$2"
  [[ -n "$id" && -n "$agent" ]] || aind_die "usage: aind-usage.sh begin <work-item-id> <agent>"
  _telemetry_enabled || return 0
  mkdir -p "$USAGE_DIR" 2>/dev/null || { aind_warn "could not create $USAGE_DIR — telemetry off for this phase"; return 0; }
  local at epoch
  at="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
  epoch="$(date +%s)"
  printf '{"started_at":"%s","started_epoch":%s}\n' "$at" "$epoch" > "$USAGE_DIR/${id}-${agent}.json" \
    || aind_warn "could not write telemetry marker for AB#${id} ${agent}"
  return 0
}

# ------------------------------------------------------------------------------------------------
# Backends — find this session's events file and reduce in-window usage to a PER-MODEL breakdown.
# Each *_file fn sets USAGE_FILE on success (returns non-zero when it can't attribute a session to
# this repo); each *_metrics fn echoes a JSON models map { "<model>": {input,output,cacheWrite,cacheRead} }.
# ------------------------------------------------------------------------------------------------

# Claude: prefer the slug dir (fast); fall back to matching each session's recorded .cwd to this repo
# (robust if the slug transform ever drifts). Among matches, newest mtime = the live session.
# Identity is the MAIN checkout, NOT $PWD: Claude keys the transcript folder to the session's LAUNCH
# cwd (always the main checkout under drive-from-main), but in worktree mode the session may have cd'd
# into a worktree by the time `report` runs — so slugging $PWD would look under a nonexistent
# worktree slug and miss. `_main_root` (git-common-dir → main) is the launch identity from anywhere.
_claude_file() {
  local base slug dir f root mroot
  base="${CLAUDE_CONFIG_DIR:+$CLAUDE_CONFIG_DIR}"; base="${base:-$(_home)/.claude}/projects"
  [[ -d "$base" ]] || return 1
  mroot="$(_main_root)"
  slug="$(cygpath -w "$mroot" 2>/dev/null || printf '%s' "$mroot")"
  slug="$(printf '%s' "$slug" | sed -e 's#[:\\/]#-#g')"
  dir="$base/$slug"
  if [[ -d "$dir" ]]; then
    f="$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1)"
    [[ -n "$f" ]] && { USAGE_FILE="$f"; return 0; }
  fi
  # Fallback: scan all sessions, match recorded cwd to the main checkout, keep the newest.
  root="$(_canon "$mroot")"
  local best="" bestt=0 c t
  for f in "$base"/*/*.jsonl; do
    [[ -f "$f" ]] || continue
    c="$(head -n1 "$f" | jq -r '.cwd // empty' 2>/dev/null)"
    [[ -n "$c" && "$(_canon "$c")" == "$root" ]] || continue
    t="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
    if (( t > bestt )); then bestt="$t"; best="$f"; fi
  done
  [[ -n "$best" ]] && { USAGE_FILE="$best"; return 0; }
  return 1
}

# Claude usage in [lo,hi] across the parent transcript + its subagent transcripts, deduped by
# message.id (streaming writes repeat an id) and reduced to a per-model breakdown. Keys a line lacking
# message.id by its uuid/timestamp so distinct lines are never collapsed. Echoes a JSON models map.
_claude_metrics() {
  local f="$1" lo="$2" hi="$3" sess subdir; sess="$(basename "$f" .jsonl)"
  subdir="$(dirname "$f")/$sess/subagents"
  local files=("$f"); local sf
  if [[ -d "$subdir" ]]; then
    for sf in "$subdir"/agent-*.jsonl; do [[ -f "$sf" ]] && files+=("$sf"); done
  fi
  jq -s --arg lo "$lo" --arg hi "$hi" '
    [ .[]
      | select((.timestamp // "") >= $lo and (.timestamp // "") <= $hi)
      | select(.message.usage != null)
      | { k: (.message.id // .uuid // .timestamp), model: (.message.model // "unknown"), u: .message.usage } ]
    | group_by(.k) | map(.[0])
    | reduce .[] as $m ({};
        .[$m.model] as $c
        | .[$m.model] = { input:      ((($c.input)      // 0) + ($m.u.input_tokens              // 0)),
                          output:     ((($c.output)     // 0) + ($m.u.output_tokens             // 0)),
                          cacheWrite: ((($c.cacheWrite) // 0) + ($m.u.cache_creation_input_tokens // 0)),
                          cacheRead:  ((($c.cacheRead)  // 0) + ($m.u.cache_read_input_tokens    // 0)) })
  ' "${files[@]}" 2>/dev/null || echo '{}'
}

# HEAD-ANCHOR the token window: a slash command's first turn (the model reading the command +
# grounding context, a full cache-read) happens BEFORE it can run the `begin` bash step, so a
# [begin, now] window drops that turn. The transcript records a real invocation as a user turn wrapped
# in a `<command-message>…</command-message>` + `<command-name>/…</command-name>` envelope, so we start
# the token window at the timestamp of the MOST RECENT such invocation at/before `hi` — which is
# exactly this command's start, and (in a shared session) never reaches back into a prior phase.
# We match the well-formed `<command-message>` envelope, NOT a bare `<command-name>` substring: a phase
# that reads a file/command/tool-output merely QUOTING the literal string `<command-name>` (this very
# script's comments do) would otherwise be mistaken for an invocation and jump the anchor forward,
# silently truncating the window from the front. Falls back to the marker's start if none is found.
_claude_anchor_lo() {
  local f="$1" fallback="$2" hi="$3" ts
  ts="$(jq -rs --arg hi "$hi" '
    [ .[]
      | select((.timestamp // "") <= $hi)
      | select(((.message.content // "") | tostring) | test("<command-message>[^<]*</command-message>"))
      | .timestamp ] | max // empty' "$f" 2>/dev/null)"
  [[ -n "$ts" ]] && printf '%s' "$ts" || printf '%s' "$fallback"
}

# Claude models map with the head-anchored window (marker `lo` is the fallback). Exposes the resolved
# anchor in USAGE_ANCHOR so `report` can head-anchor the DURATION to the same point.
_claude_models() {
  local f="$1" lo="$2" hi="$3" clo
  clo="$(_claude_anchor_lo "$f" "$lo" "$hi")"
  USAGE_ANCHOR="$clo"
  _claude_metrics "$f" "$clo" "$hi"
}

# Copilot: find the session whose workspace.yaml git_root/cwd is this repo; newest wins. Matches the
# MAIN checkout (session launch identity) so it also resolves when the shell cd'd into a worktree.
_copilot_file() {
  local base root wsf gr cwd cand best="" bestt=0 t
  base="$(_home)/.copilot/session-state"
  [[ -d "$base" ]] || return 1
  root="$(_canon "$(_main_root)")"
  for wsf in "$base"/*/workspace.yaml; do
    [[ -f "$wsf" ]] || continue
    gr="$(grep -m1 '^git_root:' "$wsf" 2>/dev/null | sed 's/^git_root:[[:space:]]*//' | tr -d '\r"')"
    cwd="$(grep -m1 '^cwd:' "$wsf" 2>/dev/null | sed 's/^cwd:[[:space:]]*//' | tr -d '\r"')"
    [[ ( -n "$gr" && "$(_canon "$gr")" == "$root" ) || ( -n "$cwd" && "$(_canon "$cwd")" == "$root" ) ]] || continue
    cand="$(dirname "$wsf")/events.jsonl"
    [[ -f "$cand" ]] || continue
    t="$(stat -c %Y "$cand" 2>/dev/null || echo 0)"
    if (( t > bestt )); then bestt="$t"; best="$cand"; fi
  done
  [[ -n "$best" ]] && { USAGE_FILE="$best"; return 0; }
  return 1
}

# Copilot per-message output tokens in [lo,hi], as a single "copilot" bucket (no per-message model or
# input/cache is available). Echoes a JSON models map { "copilot": { "output": N } }.
_copilot_metrics() {
  local f="$1" lo="$2" hi="$3"
  jq -s --arg lo "$lo" --arg hi "$hi" '
    { copilot: { output: ([ .[]
        | select(.type=="assistant.message" and (.timestamp//"")>=$lo and (.timestamp//"")<=$hi)
        | (.data.outputTokens // 0) ] | add // 0) } }
  ' "$f" 2>/dev/null || echo '{}'
}

# Detect the host and compute the per-model breakdown for the window. Sets USAGE_HOST, USAGE_MODELS
# (JSON models map), USAGE_FILE. Honours AIND_AGENT_HOST; else picks whichever host has a session file
# for this repo (newest mtime wins when both exist — the host actually running now wrote most recently).
aind_collect_usage() {
  local lo="$1" hi="$2" forced cf="" pf=""
  forced="$(printf '%s' "${AIND_AGENT_HOST:-}" | tr '[:upper:]' '[:lower:]' | tr -d '\r')"
  USAGE_HOST=""; USAGE_MODELS='{}'; USAGE_FILE=""; USAGE_ANCHOR=""
  case "$forced" in
    claude)  _claude_file  && { USAGE_HOST=claude;  USAGE_MODELS="$(_claude_models   "$USAGE_FILE" "$lo" "$hi")"; return 0; }; return 1 ;;
    copilot) _copilot_file && { USAGE_HOST=copilot; USAGE_MODELS="$(_copilot_metrics "$USAGE_FILE" "$lo" "$hi")"; return 0; }; return 1 ;;
  esac
  _claude_file  && cf="$USAGE_FILE"
  _copilot_file && pf="$USAGE_FILE"
  if [[ -n "$cf" && -n "$pf" ]]; then
    if [[ "$pf" -nt "$cf" ]]; then USAGE_HOST=copilot; USAGE_FILE="$pf"; else USAGE_HOST=claude; USAGE_FILE="$cf"; fi
  elif [[ -n "$cf" ]]; then USAGE_HOST=claude;  USAGE_FILE="$cf"
  elif [[ -n "$pf" ]]; then USAGE_HOST=copilot; USAGE_FILE="$pf"
  else return 1
  fi
  if [[ "$USAGE_HOST" == copilot ]]; then USAGE_MODELS="$(_copilot_metrics "$USAGE_FILE" "$lo" "$hi")"
  else USAGE_MODELS="$(_claude_models "$USAGE_FILE" "$lo" "$hi")"; fi
  return 0
}

# The write side (numeric-field accumulation + the token-breakdown attachment) now lives in the
# tracker adapter as tracker_field_accumulate / tracker_attach, so telemetry lands wherever the item
# lives (an ADO work item or a local markdown file). See scripts/aind-tracker.sh.

# Phase label for an agent (so the record/attachment is stage-tagged without the caller passing it).
_phase_of() {
  case "$1" in
    intake)                echo intake ;;
    planner)               echo plan ;;
    approver)              echo approve ;;
    coder|reviewer|polish) echo build ;;
    completer)             echo complete ;;
    *)                     echo unknown ;;
  esac
}

# ------------------------------------------------------------------------------------------------
# report — measure the phase window; attach the token breakdown + accumulate seconds into ADO
# ------------------------------------------------------------------------------------------------
cmd_report() {
  local id="$1" agent="$2"
  [[ -n "$id" && -n "$agent" ]] || aind_die "usage: aind-usage.sh report <work-item-id> <agent>"
  _telemetry_enabled || return 0
  set +e   # from here on telemetry is strictly best-effort: warn + exit 0, never abort the phase

  local marker="$USAGE_DIR/${id}-${agent}.json"
  [[ -f "$marker" ]] || { aind_warn "no telemetry marker for AB#${id} ${agent} (begin not run?) — skipping"; return 0; }
  aind_require_cmd jq >/dev/null 2>&1 || { aind_warn "jq not found — telemetry skipped"; return 0; }

  local lo hi start_epoch now_epoch seconds win_start_epoch started_out
  lo="$(jq -r '.started_at // empty' "$marker" 2>/dev/null)"
  start_epoch="$(jq -r '.started_epoch // empty' "$marker" 2>/dev/null)"
  hi="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
  now_epoch="$(date +%s)"
  [[ -n "$lo" && -n "$start_epoch" ]] || { aind_warn "telemetry marker for AB#${id} ${agent} is unreadable — skipping"; rm -f "$marker"; return 0; }
  rm -f "$marker"   # consume it now: `begin` re-creates it next run, so a stale marker can't widen a later window

  if ! aind_collect_usage "$lo" "$hi"; then
    aind_warn "no session events file found for this repo (host may not expose usage) — telemetry skipped for AB#${id} ${agent}"
    return 0
  fi

  # Duration window: default [begin, report]. When the host exposed a head-anchor (Claude: this
  # command's invocation turn, which fires a beat before `begin` could run), extend the START back to
  # it — the same head-anchor the token window uses — so time and tokens span the same window and the
  # command-load/grounding turn at the front isn't dropped. Copilot has no invocation tag → begin-based.
  win_start_epoch="$start_epoch"; started_out="$lo"
  if [[ -n "${USAGE_ANCHOR:-}" && "$USAGE_ANCHOR" != "$lo" ]]; then
    local anchor_epoch
    anchor_epoch="$(date -u -d "$USAGE_ANCHOR" +%s 2>/dev/null || echo "")"
    if [[ "$anchor_epoch" =~ ^[0-9]+$ ]] && (( anchor_epoch < win_start_epoch )); then
      win_start_epoch="$anchor_epoch"; started_out="$USAGE_ANCHOR"
    fi
  fi
  seconds=$(( now_epoch - win_start_epoch )); (( seconds < 0 )) && seconds=0
  local models="${USAGE_MODELS:-}"; [[ -n "$models" ]] || models='{}'
  printf '%s' "$models" | jq -e . >/dev/null 2>&1 || models='{}'

  # A one-line, human-scannable summary of the models map for the log.
  local msum
  msum="$(printf '%s' "$models" | jq -r '
    to_entries
    | map("\(.key) in\(.value.input//0)/out\(.value.output//0)/cw\(.value.cacheWrite//0)/cr\(.value.cacheRead//0)")
    | if length==0 then "no messages in window" else join("; ") end' 2>/dev/null)"

  local phase; phase="$(_phase_of "$agent")"

  # Writing goes through the tracker. The ADO backend needs org + project + PAT; without them, print
  # the numbers and stop (echo-only mode). The file backend can always write (the item store is local).
  if [[ "$(aind_tracker_kind)" == ado ]] \
     && { [[ -z "${AIND_ADO_ORG:-}" || -z "${AIND_ADO_PROJECT:-}" || -z "${AZURE_DEVOPS_EXT_PAT:-}" ]]; }; then
    echo "aind: telemetry AB#${id} ${agent} (host=${USAGE_HOST}) ${seconds}s, models: ${msum} — not written (ADO org/project/PAT unset)"
    return 0
  fi

  # Build the record and write it as an append-only attachment (the token-breakdown trace).
  local stamp fname rec atturl wrote=""
  stamp="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo unknown)"
  fname="aind-telemetry-${id}-${phase}-${agent}-${stamp}.json"
  rec="$(mktemp)"
  jq -nc --arg wi "$id" --arg phase "$phase" --arg agent "$agent" --arg host "$USAGE_HOST" \
        --arg started "$started_out" --arg ended "$hi" --argjson seconds "$seconds" --argjson models "$models" \
        '{work_item:$wi, phase:$phase, agent:$agent, host:$host, started_at:$started, ended_at:$ended, seconds:$seconds, models:$models}' \
        > "$rec" 2>/dev/null
  if tracker_attach "$id" "$rec" "$fname"; then
    wrote+=" attached ${fname}"
  fi
  rm -f "$rec"

  # Accumulate wall-clock seconds into the tracker's duration total. The file backend always keeps a
  # `durationSeconds` total (the field ref is irrelevant there); the ADO backend does so only when a
  # numeric duration field is configured (AIND_TELEMETRY_DURATION_FIELD).
  if [[ "$(aind_tracker_kind)" == file ]]; then
    tracker_field_accumulate "$id" durationSeconds "$seconds" && wrote+=" duration+=${seconds}s"
  elif [[ -n "${AIND_TELEMETRY_DURATION_FIELD:-}" ]]; then
    tracker_field_accumulate "$id" "$AIND_TELEMETRY_DURATION_FIELD" "$seconds" && wrote+=" ${AIND_TELEMETRY_DURATION_FIELD}+=${seconds}s"
  fi

  echo "aind: telemetry AB#${id} ${agent} (host=${USAGE_HOST}) ${seconds}s, models: ${msum} →${wrote:- (nothing written)}"
  return 0
}

# ------------------------------------------------------------------------------------------------
VERB="${1:-}"; shift || true
case "$VERB" in
  begin)  cmd_begin  "${1:-}" "${2:-}" ;;
  report) cmd_report "${1:-}" "${2:-}" ;;
  *) aind_die "usage: aind-usage.sh begin|report <work-item-id> <agent>" ;;
esac
