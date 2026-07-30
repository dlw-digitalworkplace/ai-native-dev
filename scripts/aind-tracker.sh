#!/usr/bin/env bash
# aind-tracker.sh — the work-item TRACKER adapter. Sourced by the work-item scripts (and runnable
# directly for a few verbs); it is the tracker twin of aind-forge.sh (the code-host adapter).
#
# WHY THIS EXISTS
# The AIND flow hangs off a "work item": it reads the story, drives its status through the flow,
# posts signed comments, resolves dependencies, links the PR, and attaches usage telemetry. Those
# were all hardwired to Azure DevOps Boards. This file makes the tracker pluggable the same way the
# code host is: one set of tracker-agnostic verbs that dispatch on AIND_TRACKER to an Azure DevOps
# (`_ado_*`) or a local-file (`_file_*`) implementation, so commands, skills, and agents never learn
# which tracker they run on.
#
#   AIND_TRACKER   ado (default) | file
#   ado  path uses:  AIND_ADO_ORG + AIND_ADO_PROJECT + AZURE_DEVOPS_EXT_PAT  + `az`/`curl`/`jq`
#   file path uses:  AIND_TRACKER_DIR (one markdown file per item; default <repo>/.aind/items) + `jq`
#
# CANONICAL VOCABULARY (both backends normalise to this, so callers are tracker-blind):
#   state        : one of the 9 AIND_STATES strings (aind-common.sh). On ADO it is carried as the
#                  single `AIND status - <state>` tag; in a file it is the scalar `state:` field.
#   fetch output : a normalised JSON object
#                  { id, title, description, acceptanceCriteria, state, dependsOn:[..], links:[..] }
#                  (ADO description/acceptance are HTML; file ones are markdown — read through it.)
#   deps output  : a human list + a machine line `DEPS_VERDICT: NONE | MET | UNMET`.
#   item id      : an opaque token — a numeric ADO id, or the file backend's numeric filename stem.
#                  Numeric on both so the `AB#<id>` / AIND-LINKS PR join keeps working unchanged.
#
# THE FILE BACKEND'S NO-DEADLOCK CONTRACT
#   One markdown file per item (`<dir>/<id>.md`) → items are independent; acting on 42 never
#   contends with a human editing 43. Each file is split into a MACHINE-owned YAML front-matter
#   block (only this adapter rewrites it) and HUMAN-owned `##` sections (the adapter READS
#   Description/Acceptance and only APPENDS to Comments — it never edits prose). Every write is
#   temp-file-then-atomic-`mv`, so the adapter never holds a file open: it can write even while the
#   file is open in an editor (the editor just offers to reload). No locks, so nothing can deadlock.
#   Front-matter is deliberately FLAT SCALARS (`dependsOn: 37, 40`) so it needs no YAML parser.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

# ------------------------------------------------------------------------------------------------
# Backend selection + config/tool validation
# ------------------------------------------------------------------------------------------------

aind_tracker_kind() { echo "${AIND_TRACKER:-ado}"; }

# Validate the config + tools the selected tracker needs. Call once, after sourcing, in each caller.
tracker_require() {
  case "$(aind_tracker_kind)" in
    ado)  aind_require_env AIND_ADO_ORG AIND_ADO_PROJECT AZURE_DEVOPS_EXT_PAT
          aind_require_cmd az curl jq ;;
    file) aind_require_cmd jq
          _file_dir >/dev/null ;;   # resolves + creates AIND_TRACKER_DIR (dies with guidance if it can't)
    *)    aind_die "unknown AIND_TRACKER '$(aind_tracker_kind)' (use: ado | file)" ;;
  esac
}

# ================================================================================================
# ADO backend
# ================================================================================================

# ADO REST helper (same auth + UTF-8-safe body-from-file discipline as aind-comment.sh / aind-forge.sh).
# _ado_api <METHOD> <url> <content-type> [body-file] -> prints response body; non-2xx -> aind_die.
_ado_api() {
  local method="$1" url="$2" ctype="$3" bodyfile="${4:-}" resp code out msg
  local args=(-s -w $'\n%{http_code}' -u ":${AZURE_DEVOPS_EXT_PAT}" -X "$method" -H "Content-Type: $ctype" "$url")
  [[ -n "$bodyfile" ]] && args+=(--data-binary @"$bodyfile")
  resp="$(curl "${args[@]}")" || aind_die "ADO API $method $url: network/curl error"
  code="${resp##*$'\n'}"; out="${resp%$'\n'*}"
  if [[ "$code" != 2* ]]; then
    msg="$(printf '%s' "$out" | jq -r '.message // empty' 2>/dev/null)"
    aind_die "ADO API $method failed (HTTP $code)${msg:+: $msg}"
  fi
  printf '%s' "$out"
}

# Normalize a string for AIND-status detection: strip CR, lowercase, collapse whitespace, trim.
_trk_norm() {
  printf '%s' "$1" | tr -d '\r' | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[[:space:]]\{1,\}/ /g' -e 's/^ //' -e 's/ $//'
}

# Extract the AIND status value ("Intake approved", …) from a ';'-separated ADO tags string; empty
# if none. Match is normalized on the prefix.
_ado_tag_value() {
  local current="$1" raw clean
  [[ -z "$current" ]] && return 0
  local IFS=';'
  read -ra parts <<< "$current"
  for raw in "${parts[@]}"; do
    clean="$(printf '%s' "$raw" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    case "$(_trk_norm "$clean")" in
      "aind status -"*)
        printf '%s' "$clean" | sed -E 's/^[Aa][Ii][Nn][Dd][[:space:]]+[Ss]tatus[[:space:]]*-[[:space:]]*//'
        return 0 ;;
    esac
  done
}

_ado_read_tags() {
  az boards work-item show --id "$1" --org "$(aind_org)" --query 'fields."System.Tags"' -o tsv 2>/dev/null || true
}

_ado_fetch() {
  local id="$1" raw tags state
  raw="$(az boards work-item show --id "$id" --org "$(aind_org)" --expand all --output json)" \
    || aind_die "could not fetch work item $id from ADO (check the id, org, and PAT)"
  tags="$(printf '%s' "$raw" | jq -r '.fields["System.Tags"] // ""')"
  state="$(_ado_tag_value "$tags")"
  printf '%s' "$raw" | jq --arg s "$state" '{
    id: (.id | tostring),
    title: (.fields["System.Title"] // ""),
    description: (.fields["System.Description"] // ""),
    acceptanceCriteria: (.fields["Microsoft.VSTS.Common.AcceptanceCriteria"] // ""),
    state: $s,
    dependsOn: [ (.relations // [])[] | select(.rel == "System.LinkTypes.Dependency-Reverse") | (.url | sub(".*/"; "")) ],
    links: [ (.relations // [])[] | select(.rel // "" | test("PullRequest"; "i")) | .url ]
  }'
}

_ado_get_state() { _ado_tag_value "$(_ado_read_tags "$1")"; }

# Set the single AIND status tag (invariant: exactly one). REST PATCH op:replace (az's --fields
# emits an `add` that MERGES on some builds -> two tags). Verifies + auto-corrects once, then mirrors
# into the native ADO State when a stateMap is configured. This is the former aind-status.sh body.
_ado_set_state() {
  local id="$1" new="$2" agent="${3:-}" org target current desired op
  org="$(aind_org)"; target="AIND status - $new"

  _ado_build_desired() {
    local current="$1" raw clean norm joined="" t; local kept=()
    if [[ -n "$current" ]]; then
      local IFS=';'; read -ra parts <<< "$current"
      for raw in "${parts[@]}"; do
        clean="$(printf '%s' "$raw" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -z "$clean" ]] && continue
        norm="$(_trk_norm "$clean")"
        case "$norm" in "aind status -"*) continue ;; *) kept+=("$clean") ;; esac
      done
    fi
    kept+=("$target")
    for t in "${kept[@]}"; do if [[ -z "$joined" ]]; then joined="$t"; else joined="$joined; $t"; fi; done
    printf '%s' "$joined"
  }
  _ado_patch_tags() {
    local op="$1" value="$2" body tmp
    body="$(jq -nc --arg op "$op" --arg val "$value" '[{op:$op, path:"/fields/System.Tags", value:$val}]')"
    tmp="$(mktemp)"; printf '%s' "$body" > "$tmp"
    _ado_api PATCH "${org}/_apis/wit/workitems/${id}?api-version=7.1" 'application/json-patch+json' "$tmp" >/dev/null
    rm -f "$tmp"
  }
  _ado_set_tags() {
    current="$(_ado_read_tags "$id")"; desired="$(_ado_build_desired "$current")"
    if [[ -n "$current" ]]; then op="replace"; else op="add"; fi
    _ado_patch_tags "$op" "$desired"
  }
  _ado_verify() {
    local cur="$1" raw norm tnorm; tnorm="$(_trk_norm "$target")"
    AIND_COUNT=0; AIND_HAS_TARGET=0; [[ -z "$cur" ]] && return
    local IFS=';'; read -ra parts <<< "$cur"
    for raw in "${parts[@]}"; do norm="$(_trk_norm "$raw")"
      case "$norm" in "aind status -"*) AIND_COUNT=$((AIND_COUNT+1)); [[ "$norm" == "$tnorm" ]] && AIND_HAS_TARGET=1 ;; esac
    done
  }

  _ado_set_tags
  _ado_verify "$(_ado_read_tags "$id")"
  if (( AIND_COUNT != 1 )) || (( AIND_HAS_TARGET != 1 )); then
    _ado_set_tags; _ado_verify "$(_ado_read_tags "$id")"
    if (( AIND_COUNT != 1 )) || (( AIND_HAS_TARGET != 1 )); then
      aind_warn "work item $id has ${AIND_COUNT} AIND status tag(s) after update (expected exactly 1 = '$target'). Check the tags manually."
    else
      aind_warn "auto-corrected stray/duplicate AIND status tag(s) on work item $id."
    fi
  fi
  echo "aind: work item $id -> $target"

  # Mirror into the native ADO State (best-effort projection; the AIND tag stays authoritative).
  [[ -n "${AIND_STATE_MAP:-}" ]] || return 0
  local mtarget
  mtarget="$(printf '%s' "$AIND_STATE_MAP" | jq -r --arg s "$new" '.[$s] // empty' 2>/dev/null | tr -d '\r' || true)"
  [[ -n "$mtarget" ]] || return 0
  if az boards work-item update --id "$id" --org "$org" --state "$mtarget" >/dev/null 2>&1; then
    echo "aind: mirrored native State -> $mtarget"; return 0
  fi
  aind_warn "could not mirror native State '$mtarget' on work item $id — board not moved (flow unaffected)"
  if [[ -n "$agent" ]]; then
    bash "$SCRIPT_DIR/aind-emit-lesson.sh" "$id" "$agent" observation self-report stateMap <<EOF 2>/dev/null || true
Mirroring AIND status "$new" to native ADO State "$mtarget" failed on work item $id. The mapped
state may not exist in this project's process template, or the transition to it is not allowed from
the work item's current state. The AIND status tag was set correctly and remains authoritative; only
the native-State projection did not move, so the board silently diverges from the flow here.
EOF
  fi
}

# ADO work-item comments are an HTML rich-text field. Convert the markdown subset to HTML and append
# the display:none signature span (ADO strips HTML comments). This is the former aind-comment.sh body.
_ado_md_to_html() {
  awk '
    function esc(s){ gsub(/&/,"\\&amp;",s); gsub(/</,"\\&lt;",s); gsub(/>/,"\\&gt;",s); return s }
    function inl(s){
      while (match(s, /\*\*[^*]+\*\*/)) s = substr(s,1,RSTART-1) "<strong>" substr(s,RSTART+2,RLENGTH-4) "</strong>" substr(s,RSTART+RLENGTH)
      while (match(s, /`[^`]+`/))        s = substr(s,1,RSTART-1) "<code>"   substr(s,RSTART+1,RLENGTH-2) "</code>"   substr(s,RSTART+RLENGTH)
      return s
    }
    function closelists(){ if(ul){print "</ul>"; ul=0} if(ol){print "</ol>"; ol=0} }
    function tcells(row, tag,   n,a,i,out,c){
      sub(/^[[:space:]]*\|/,"",row); sub(/\|[[:space:]]*$/,"",row)
      n=split(row,a,"|"); out=""
      for(i=1;i<=n;i++){ c=a[i]; gsub(/^[[:space:]]+/,"",c); gsub(/[[:space:]]+$/,"",c); out=out "<" tag ">" inl(esc(c)) "</" tag ">" }
      return out
    }
    function flushtable(   i,row,issep){
      if(tn==0) return
      print "<table>"
      for(i=1;i<=tn;i++){ row=tbl[i]; issep=(row ~ /^[[:space:]]*\|?[[:space:]:|-]+\|?[[:space:]]*$/)
        if(i==1) print "<tr>" tcells(row,"th") "</tr>"; else if(issep) continue; else print "<tr>" tcells(row,"td") "</tr>" }
      print "</table>"; tn=0
    }
    BEGIN{ ul=0; ol=0; tn=0 }
    {
      line=$0; sub(/\r$/,"",line)
      istbl=(line ~ /^[[:space:]]*\|.*\|[[:space:]]*$/)
      if (!istbl) flushtable()
      if (line ~ /^[[:space:]]*$/) { closelists(); next }
      if (istbl) { closelists(); tbl[++tn]=line; next }
      if (line ~ /^### /) { closelists(); print "<h3>" inl(esc(substr(line,5))) "</h3>"; next }
      if (line ~ /^## /)  { closelists(); print "<h2>" inl(esc(substr(line,4))) "</h2>"; next }
      if (line ~ /^# /)   { closelists(); print "<h1>" inl(esc(substr(line,3))) "</h1>"; next }
      if (line ~ /^[-*] /) { if (ol){print "</ol>";ol=0} if(!ul){print "<ul>";ul=1} print "<li>" inl(esc(substr(line,3))) "</li>"; next }
      if (line ~ /^[0-9]+\. /) { if (ul){print "</ul>";ul=0} if(!ol){print "<ol>";ol=1} sub(/^[0-9]+\. /,"",line); print "<li>" inl(esc(line)) "</li>"; next }
      closelists(); print "<div>" inl(esc(line)) "</div>"
    }
    END{ closelists(); flushtable() }
  '
}
_ado_comment() {
  local id="$1" agent="$2" bodyfile="$3" display actor sig full body tmp org url
  display="${agent^}"; actor="$(aind_actor)"
  sig="<br><br>— 🤖 AIND ${display} Agent (run by ${actor})<span style=\"display:none\">AIND-AGENT: ${agent}</span>"
  full="$(_ado_md_to_html < "$bodyfile")${sig}"
  body="$(printf '%s' "$full" | jq -Rs '{text: .}')"
  org="$(aind_org)"; url="${org}/${AIND_ADO_PROJECT}/_apis/wit/workItems/${id}/comments?api-version=7.1-preview.4"
  tmp="$(mktemp)"; printf '%s' "$body" > "$tmp"
  _ado_api POST "$url" 'application/json; charset=utf-8' "$tmp" >/dev/null
  rm -f "$tmp"
  echo "aind: posted signed ${agent} comment to work item $id"
}

_ado_deps() {
  local id="$1" org wi_json dep_ids; org="$(aind_org)"
  local TERMINAL="Implementation complete"
  _ado_is_done() { case "$(_trk_norm "$1")" in closed|done|resolved|completed) return 0 ;; *) return 1 ;; esac; }
  wi_json="$(az boards work-item show --id "$id" --org "$org" --expand relations --output json 2>/dev/null)" \
    || aind_die "could not fetch work item $id from ADO (check the id, org, and PAT)"
  dep_ids="$(printf '%s' "$wi_json" | jq -r '
    [ (.relations // [])[] | select(.rel == "System.LinkTypes.Dependency-Reverse") | (.url | sub(".*/"; "")) ] | .[]
  ' 2>/dev/null || true)"
  local total=0 implemented=0 notimpl=0 unknown=0; local lines=()
  if [[ -n "$dep_ids" ]]; then
    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue; total=$((total+1))
      local dj title state tags aind_val verdict
      dj="$(az boards work-item show --id "$dep" --org "$org" \
          --query '{title:fields."System.Title", state:fields."System.State", tags:fields."System.Tags"}' -o json 2>/dev/null || true)"
      if [[ -z "$dj" ]]; then lines+=("  AB#$dep | (could not read linked item) | UNKNOWN"); unknown=$((unknown+1)); continue; fi
      title="$(printf '%s' "$dj" | jq -r '.title // ""')"; state="$(printf '%s' "$dj" | jq -r '.state // ""')"
      tags="$(printf '%s' "$dj" | jq -r '.tags // ""')"; aind_val="$(_ado_tag_value "$tags")"
      if [[ -n "$aind_val" ]]; then
        if [[ "$(_trk_norm "$aind_val")" == "$(_trk_norm "$TERMINAL")" ]]; then verdict="IMPLEMENTED"; else verdict="NOT IMPLEMENTED"; fi
      elif _ado_is_done "$state"; then verdict="IMPLEMENTED"; else verdict="NOT IMPLEMENTED"; fi
      case "$verdict" in IMPLEMENTED) implemented=$((implemented+1)) ;; *) notimpl=$((notimpl+1)) ;; esac
      lines+=("  AB#$dep | state=\"$state\" | aind=\"${aind_val:-(none)}\" | $verdict | \"$title\"")
    done <<< "$dep_ids"
  fi
  _trk_emit_deps "$total" "$implemented" "$notimpl" "$unknown" "${lines[@]}"
}

# NOTE: attach + field_accumulate are the TELEMETRY verbs — best-effort, they must NEVER abort a
# phase. So they never go through _ado_api (which aind_die-exits on failure): the read runs inside a
# command substitution (a subshell contains any exit), and each write PATCH runs in an explicit
# ( … ) subshell so a die can't kill the caller — on any failure they aind_warn + return 1.
_ado_attach() {
  local id="$1" file="$2" fname="${3:-$(basename "$file")}" org atturl body tmp
  org="$(aind_org)"
  atturl="$(_ado_api POST "${org}/${AIND_ADO_PROJECT}/_apis/wit/attachments?fileName=${fname}&api-version=7.1" 'application/json' "$file" 2>/dev/null | jq -r '.url // empty' 2>/dev/null)"
  [[ -n "$atturl" ]] || { aind_warn "telemetry attachment upload failed for AB#$id"; return 1; }
  body="$(jq -nc --arg u "$atturl" --arg n "$fname" \
    '[{op:"add", path:"/relations/-", value:{rel:"AttachedFile", url:$u, attributes:{name:$n, comment:"AIND telemetry"}}}]')"
  tmp="$(mktemp)"; printf '%s' "$body" > "$tmp"
  ( _ado_api PATCH "${org}/_apis/wit/workitems/${id}?api-version=7.1" 'application/json-patch+json' "$tmp" >/dev/null 2>&1 ) \
    || { rm -f "$tmp"; aind_warn "linking telemetry attachment to AB#$id failed"; return 1; }
  rm -f "$tmp"
}

_ado_field_accumulate() {
  local id="$1" ref="$2" delta="$3" cur op new org url tmp body
  org="$(aind_org)"
  url="${org}/_apis/wit/workitems/${id}?fields=${ref}&api-version=7.1"
  cur="$(curl -s -u ":${AZURE_DEVOPS_EXT_PAT}" "$url" 2>/dev/null | jq -r --arg f "$ref" '.fields[$f] // empty' 2>/dev/null | tr -d '\r')"
  if [[ "$cur" =~ ^[0-9]+$ ]]; then op=replace; else cur=0; op=add; fi
  new=$(( cur + delta ))
  body="$(jq -nc --arg op "$op" --arg ref "$ref" --argjson val "$new" '[{op:$op, path:("/fields/" + $ref), value:$val}]')"
  tmp="$(mktemp)"; printf '%s' "$body" > "$tmp"
  ( _ado_api PATCH "${org}/_apis/wit/workitems/${id}?api-version=7.1" 'application/json-patch+json' "$tmp" >/dev/null 2>&1 ) \
    || { rm -f "$tmp"; aind_warn "duration field '$ref' update on AB#$id failed"; return 1; }
  rm -f "$tmp"
}

# On ADO the PR<->work-item link is created natively by the code host at PR-create time (aind-forge.sh
# `az repos pr work-item add` when both axes are ADO, or the AB#<id> marker for the Boards<->GitHub
# app), so there is nothing to record here.
_ado_link_pr() { return 0; }

_ado_url() { echo "$(aind_org)/${AIND_ADO_PROJECT}/_workitems/edit/$1"; }

_ado_new() {
  aind_die "creating work items is not supported for the ADO tracker — create the story in Azure DevOps (Boards), then run the AIND phases against its id."
}

# ================================================================================================
# File backend (markdown file per item)
# ================================================================================================

# Resolve the item-store directory (precedence: AIND_TRACKER_DIR env/settings -> <main-repo>/.aind/items),
# expand a leading ~, and create it. Rooted at the MAIN checkout (not $PWD) so it is stable when a
# phase has cd'd into a worktree. Echoes the absolute path.
_file_dir() {
  local d="${AIND_TRACKER_DIR:-}"
  if [[ -z "$d" ]]; then
    local gcd main
    gcd="$(git rev-parse --git-common-dir 2>/dev/null || true)"
    [[ -n "$gcd" ]] || aind_die "AIND_TRACKER_DIR is not set and this is not a git repo — set '.trackerDir' in .claude/aind.settings.json (an absolute path) or run inside a repo."
    main="$(cd "$(dirname "$gcd")" && pwd)"
    d="$main/.aind/items"
  fi
  case "$d" in "~"|"~/"*) d="${HOME}${d#\~}" ;; esac
  mkdir -p "$d" 2>/dev/null || aind_die "cannot create tracker dir '$d' (check the path / permissions)"
  ( cd "$d" && pwd )
}

_file_path() { echo "$(_file_dir)/$1.md"; }

_file_require_item() {
  local f; f="$(_file_path "$1")"
  [[ -f "$f" ]] || aind_die "work item $1 not found at $f (create it with: aind-tracker.sh new \"<title>\")"
  printf '%s' "$f"
}

# Read one flat front-matter scalar (empty if absent). Front-matter = the block between the first two
# `---` lines; keys are `key: value`.
_file_fm_get() {
  local f="$1" key="$2"
  awk -v k="$key" '
    BEGIN{st=0}
    { line=$0; sub(/\r$/,"",line)
      if (st==0){ if(line=="---"){st=1} next }
      if (st==1){ if(line=="---"){exit}
        if (line ~ "^"k"[[:space:]]*:"){ sub("^"k"[[:space:]]*:[[:space:]]*","",line); print line; exit } } }
  ' "$f"
}

# Atomically set/replace a flat front-matter scalar (insert before the closing --- if absent).
# Only front-matter line endings are normalised (machine-owned); the body is passed through verbatim.
_file_fm_set() {
  local f="$1" key="$2" val="$3" tmp
  tmp="$(mktemp "$(dirname "$f")/.aind-XXXXXX")" || aind_die "cannot create temp file next to $f"
  awk -v k="$key" -v val="$val" '
    BEGIN{st=0; done=0}
    {
      if (st==0){ if($0=="---"||$0=="---\r"){st=1; print "---"; next} print; next }
      if (st==1){
        if($0=="---"||$0=="---\r"){ if(!done){print k": " val; done=1} st=2; print "---"; next }
        kl=$0; sub(/\r$/,"",kl)
        if (kl ~ "^"k"[[:space:]]*:"){ print k": " val; done=1; next }
        print kl; next
      }
      print; next
    }
  ' "$f" > "$tmp" && mv "$tmp" "$f" || { rm -f "$tmp"; aind_die "failed to update front-matter '$key' on $f"; }
}

# Extract the body of a `## <heading>` section (up to the next `## ` or EOF), trimmed of surrounding blanks.
_file_section() {
  local f="$1" heading="$2"
  awk -v H="$heading" '
    BEGIN{grab=0}
    { line=$0; sub(/\r$/,"",line)
      if (line ~ /^## /){ hd=line; sub(/^## /,"",hd)
        if (hd==H){grab=1; next} else if(grab){exit} else next }
      if (grab) print line }
  ' "$f" | sed -e '/./,$!d' | sed -e ':a' -e '/^[[:space:]]*$/{$d;N;ba}'
}

_file_fetch() {
  local id="$1" f; f="$(_file_require_item "$id")"
  local title desc ac state deps links
  title="$(_file_fm_get "$f" title)"; state="$(_file_fm_get "$f" state)"
  deps="$(_file_fm_get "$f" dependsOn)"; links="$(_file_fm_get "$f" links)"
  desc="$(_file_section "$f" Description)"; ac="$(_file_section "$f" 'Acceptance Criteria')"
  jq -n --arg id "$id" --arg t "$title" --arg d "$desc" --arg a "$ac" --arg s "$state" \
        --arg deps "$deps" --arg links "$links" '
    def csv: split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0));
    {id:$id, title:$t, description:$d, acceptanceCriteria:$a, state:$s,
     dependsOn: ($deps|csv), links: ($links|csv)}'
}

_file_get_state() { _file_fm_get "$(_file_require_item "$1")" state; }

_file_set_state() {
  local id="$1" new="$2" f; f="$(_file_require_item "$id")"
  _file_fm_set "$f" state "$new"
  echo "aind: work item $id -> AIND status - $new"
}

_file_comment() {
  local id="$1" agent="$2" bodyfile="$3" f display actor stamp tmp
  f="$(_file_require_item "$id")"; display="${agent^}"; actor="$(aind_actor)"; stamp="$(date +%Y-%m-%d 2>/dev/null || echo '')"
  # Ensure a Comments section exists (convention: it is the LAST section, so we append at EOF).
  grep -q '^## Comments[[:space:]]*$' "$f" || printf '\n## Comments\n' >> "$f"
  tmp="$(mktemp "$(dirname "$f")/.aind-XXXXXX")" || aind_die "cannot create temp file next to $f"
  {
    cat "$f"
    printf '\n### 🤖 AIND %s Agent%s (run by %s)\n\n' "$display" "${stamp:+ — $stamp}" "$actor"
    cat "$bodyfile"
    printf '\n\n<!-- AIND-AGENT: %s -->\n' "$agent"
  } > "$tmp" && mv "$tmp" "$f" || { rm -f "$tmp"; aind_die "failed to append comment to $f"; }
  echo "aind: posted signed ${agent} comment to work item $id"
}

_file_deps() {
  local id="$1" f deps; f="$(_file_require_item "$id")"
  local TERMINAL="Implementation complete"
  deps="$(_file_fm_get "$f" dependsOn)"
  local total=0 implemented=0 notimpl=0 unknown=0; local lines=()
  local IFS=','; read -ra parts <<< "$deps"
  local raw dep df dtitle dstate verdict
  for raw in "${parts[@]}"; do
    dep="$(printf '%s' "$raw" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$dep" ]] && continue; total=$((total+1))
    df="$(_file_dir)/$dep.md"
    if [[ ! -f "$df" ]]; then lines+=("  #$dep | (no such item file) | UNKNOWN"); unknown=$((unknown+1)); continue; fi
    dtitle="$(_file_fm_get "$df" title)"; dstate="$(_file_fm_get "$df" state)"
    if [[ "$(_trk_norm "$dstate")" == "$(_trk_norm "$TERMINAL")" ]]; then verdict="IMPLEMENTED"; implemented=$((implemented+1)); else verdict="NOT IMPLEMENTED"; notimpl=$((notimpl+1)); fi
    lines+=("  #$dep | state=\"$dstate\" | $verdict | \"$dtitle\"")
  done
  unset IFS
  _trk_emit_deps "$total" "$implemented" "$notimpl" "$unknown" "${lines[@]}"
}

# File telemetry verbs are best-effort too: the front-matter write (which can aind_die) runs in a
# ( … ) subshell so a failure warns + returns 1 instead of aborting the phase.
_file_attach() {
  local id="$1" file="$2" fname="${3:-$(basename "$file")}" dir adir f cur_list new_list
  dir="$(_file_dir)"; adir="$dir/attachments"; mkdir -p "$adir"
  cp "$file" "$adir/$fname" || { aind_warn "could not copy telemetry attachment to $adir/$fname"; return 1; }
  f="$(_file_path "$id")"; cur_list="$(_file_fm_get "$f" attachments)"
  if [[ -n "$cur_list" ]]; then new_list="$cur_list, attachments/$fname"; else new_list="attachments/$fname"; fi
  ( _file_fm_set "$f" attachments "$new_list" ) || { aind_warn "could not record attachment on item $id"; return 1; }
}

_file_field_accumulate() {
  # The ADO field refName ($2) is irrelevant for the file backend — time accumulates in `durationSeconds`.
  local id="$1" delta="$3" f cur; f="$(_file_path "$id")"
  [[ -f "$f" ]] || { aind_warn "item $id not found — duration not recorded"; return 1; }
  cur="$(_file_fm_get "$f" durationSeconds)"; [[ "$cur" =~ ^[0-9]+$ ]] || cur=0
  ( _file_fm_set "$f" durationSeconds "$(( cur + delta ))" ) || { aind_warn "could not record duration on item $id"; return 1; }
}

_file_link_pr() {
  local id="$1" url="$2" f cur; f="$(_file_require_item "$id")"
  cur="$(_file_fm_get "$f" links)"
  if [[ -n "$cur" ]]; then
    case ", $cur," in *", $url,"*) return 0 ;; esac   # idempotent
    _file_fm_set "$f" links "$cur, $url"
  else _file_fm_set "$f" links "$url"; fi
}

_file_url() { _file_path "$1"; }

# Create a new item file from the template, assigning id = max existing + 1. Echoes "<id> <path>".
_file_new() {
  local title="$1" dir tmpl next f
  [[ -n "$title" ]] || aind_die "usage: aind-tracker.sh new \"<title>\""
  dir="$(_file_dir)"
  next="$(_file_next_id "$dir")"
  f="$dir/$next.md"
  tmpl="$SCRIPT_DIR/../project-template/item-template.md"
  if [[ -f "$tmpl" ]]; then
    sed -e "s/^id:.*/id: $next/" -e "s/^title:.*/title: $title/" "$tmpl" > "$f"
  else
    {
      printf -- '---\nid: %s\ntitle: %s\nstate: Ready for intake\ndependsOn:\nlinks:\nattachments:\ndurationSeconds: 0\n---\n\n' "$next" "$title"
      printf '## Description\n\n\n## Acceptance Criteria\n\n\n## Comments\n'
    } > "$f"
  fi
  echo "$next $f"
}

_file_next_id() {
  local dir="$1" max=0 base n
  shopt -s nullglob
  for base in "$dir"/*.md; do
    n="$(basename "$base" .md)"
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    (( n > max )) && max="$n"
  done
  shopt -u nullglob
  echo $(( max + 1 ))
}

# ================================================================================================
# Shared helpers + host-blind verb dispatch
# ================================================================================================

# Emit the dependency report (identical shape for both backends). Args: total impl notimpl unknown [lines...]
_trk_emit_deps() {
  local total="$1" implemented="$2" notimpl="$3" unknown="$4"; shift 4
  echo "Dependencies (stories this item must not start before):"
  if (( total == 0 )); then echo "  (none linked)"; else local l; for l in "$@"; do echo "$l"; done; fi
  echo
  echo "Summary: $total dependency(ies); $implemented implemented, $notimpl not implemented, $unknown unknown."
  if (( total == 0 )); then echo "DEPS_VERDICT: NONE"
  elif (( notimpl + unknown == 0 )); then echo "DEPS_VERDICT: MET"
  else echo "DEPS_VERDICT: UNMET"; fi
}

# Read a body from a file arg, or (when the arg is "-" / absent) from stdin, into a temp file; echoes
# the temp path. Callers rm it. Lets tracker_comment take a message file OR piped markdown.
_trk_body_to_file() {
  local src="${1:--}" tmp; tmp="$(mktemp)"
  if [[ "$src" == "-" || -z "$src" ]]; then cat > "$tmp"; else cat "$src" > "$tmp"; fi
  printf '%s' "$tmp"
}

tracker_fetch()            { case "$(aind_tracker_kind)" in file) _file_fetch "$@";; *) _ado_fetch "$@";; esac; }
tracker_get_state()        { case "$(aind_tracker_kind)" in file) _file_get_state "$@";; *) _ado_get_state "$@";; esac; }
tracker_set_state()        { aind_validate_state "${2:-}"; case "$(aind_tracker_kind)" in file) _file_set_state "$@";; *) _ado_set_state "$@";; esac; }
tracker_comment()          { case "$(aind_tracker_kind)" in file) _file_comment "$@";; *) _ado_comment "$@";; esac; }
tracker_deps()             { case "$(aind_tracker_kind)" in file) _file_deps "$@";; *) _ado_deps "$@";; esac; }
tracker_attach()           { case "$(aind_tracker_kind)" in file) _file_attach "$@";; *) _ado_attach "$@";; esac; }
tracker_field_accumulate() { case "$(aind_tracker_kind)" in file) _file_field_accumulate "$@";; *) _ado_field_accumulate "$@";; esac; }
tracker_link_pr()          { case "$(aind_tracker_kind)" in file) _file_link_pr "$@";; *) _ado_link_pr "$@";; esac; }
tracker_url()              { case "$(aind_tracker_kind)" in file) _file_url "$@";; *) _ado_url "$@";; esac; }
tracker_new()              { case "$(aind_tracker_kind)" in file) _file_new "$@";; *) _ado_new "$@";; esac; }

# ------------------------------------------------------------------------------------------------
# Direct CLI dispatch (when executed, not sourced) — a thin front end for the verbs that a command
# or a human invokes directly (mainly `new`; the rest are handy for testing / scripting).
# ------------------------------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  VERB="${1:-}"; shift || true
  case "$VERB" in
    new)               tracker_require; tracker_new "$@" ;;
    fetch)             tracker_require; tracker_fetch "$@" ;;
    get-state)         tracker_require; tracker_get_state "$@" ;;
    set-state)         tracker_require; tracker_set_state "$@" ;;
    deps)              tracker_require; tracker_deps "$@" ;;
    url)               tracker_require; tracker_url "$@" ;;
    link-pr)           tracker_require; tracker_link_pr "$@" ;;
    comment)           tracker_require; ID="${1:?work-item id}"; AGENT="${2:?agent}"; BF="$(_trk_body_to_file "${3:-}")"; tracker_comment "$ID" "$AGENT" "$BF"; rm -f "$BF" ;;
    require)           tracker_require; echo "aind: tracker '$(aind_tracker_kind)' OK" ;;
    kind)              echo "$(aind_tracker_kind)" ;;
    *) aind_die "usage: aind-tracker.sh <new|fetch|get-state|set-state|deps|url|link-pr|comment|require|kind> [args]" ;;
  esac
fi
