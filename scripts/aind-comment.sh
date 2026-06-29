#!/usr/bin/env bash
# aind-comment.sh <work-item-id> <agent-name> [message]
# Posts a comment to an ADO work item, ALWAYS appending an agent signature
# (design: every agent post is signed by the agent name; mitigates the current
# "everything under the developer's identity" limitation).
#
# The message may be passed as the 3rd arg OR piped on stdin (preferred for
# multi-line markdown):  echo "## Verdict ..." | aind-comment.sh 123 intake
#
# This script is the ONLY sanctioned path for posting ADO comments — the
# signing PreToolUse hook blocks raw comment calls that bypass it.
#
# Usage: aind-comment.sh 123 intake "Looks good."
#        cat report.md | aind-comment.sh 123 planner

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aind-common.sh
source "$SCRIPT_DIR/aind-common.sh"

ID="${1:-}"
AGENT="${2:-}"
[[ -n "$ID" && -n "$AGENT" ]] || aind_die "usage: aind-comment.sh <work-item-id> <agent-name> [message]"
aind_require_env AIND_ADO_ORG AIND_ADO_PROJECT AZURE_DEVOPS_EXT_PAT
aind_require_cmd curl jq

# Body: 3rd arg if present, else stdin.
if [[ $# -ge 3 ]]; then
  MESSAGE="$3"
else
  MESSAGE="$(cat)"
fi
[[ -n "$MESSAGE" ]] || aind_die "empty comment message"

DISPLAY="${AGENT^}"                       # intake -> Intake
ACTOR="$(aind_actor)"

# ADO work-item comments are an HTML rich-text field, not markdown: posting raw markdown
# shows the literal markup. Convert the agent's markdown body to a small, safe HTML subset
# (headings, ordered/unordered lists, bold, inline code, paragraphs) so it renders.
md_to_html() {
  awk '
    function esc(s){ gsub(/&/,"\\&amp;",s); gsub(/</,"\\&lt;",s); gsub(/>/,"\\&gt;",s); return s }
    function inl(s){
      while (match(s, /\*\*[^*]+\*\*/)) s = substr(s,1,RSTART-1) "<strong>" substr(s,RSTART+2,RLENGTH-4) "</strong>" substr(s,RSTART+RLENGTH)
      while (match(s, /`[^`]+`/))        s = substr(s,1,RSTART-1) "<code>"   substr(s,RSTART+1,RLENGTH-2) "</code>"   substr(s,RSTART+RLENGTH)
      return s
    }
    function closelists(){ if(ul){print "</ul>"; ul=0} if(ol){print "</ol>"; ol=0} }
    # Split a buffered pipe-table row into <th>/<td> cells (strips the outer pipes).
    function tcells(row, tag,   n,a,i,out,c){
      sub(/^[[:space:]]*\|/,"",row); sub(/\|[[:space:]]*$/,"",row)
      n=split(row,a,"|")
      out=""
      for(i=1;i<=n;i++){ c=a[i]; gsub(/^[[:space:]]+/,"",c); gsub(/[[:space:]]+$/,"",c); out=out "<" tag ">" inl(esc(c)) "</" tag ">" }
      return out
    }
    # Flush buffered table rows: row 1 = header, the |---| separator is skipped, rest = data.
    function flushtable(   i,row,issep){
      if(tn==0) return
      print "<table>"
      for(i=1;i<=tn;i++){
        row=tbl[i]
        issep = (row ~ /^[[:space:]]*\|?[[:space:]:|-]+\|?[[:space:]]*$/)
        if(i==1) print "<tr>" tcells(row,"th") "</tr>"
        else if(issep) continue
        else print "<tr>" tcells(row,"td") "</tr>"
      }
      print "</table>"
      tn=0
    }
    BEGIN{ ul=0; ol=0; tn=0 }
    {
      line=$0; sub(/\r$/,"",line)
      istbl = (line ~ /^[[:space:]]*\|.*\|[[:space:]]*$/)
      if (!istbl) flushtable()
      if (line ~ /^[[:space:]]*$/) { closelists(); next }
      if (istbl) { closelists(); tbl[++tn]=line; next }
      if (line ~ /^### /) { closelists(); print "<h3>" inl(esc(substr(line,5))) "</h3>"; next }
      if (line ~ /^## /)  { closelists(); print "<h2>" inl(esc(substr(line,4))) "</h2>"; next }
      if (line ~ /^# /)   { closelists(); print "<h1>" inl(esc(substr(line,3))) "</h1>"; next }
      if (line ~ /^[-*] /) {
        if (ol){ print "</ol>"; ol=0 }
        if (!ul){ print "<ul>"; ul=1 }
        print "<li>" inl(esc(substr(line,3))) "</li>"; next
      }
      if (line ~ /^[0-9]+\. /) {
        if (ul){ print "</ul>"; ul=0 }
        if (!ol){ print "<ol>"; ol=1 }
        sub(/^[0-9]+\. /,"",line)
        print "<li>" inl(esc(line)) "</li>"; next
      }
      closelists(); print "<div>" inl(esc(line)) "</div>"
    }
    END{ closelists(); flushtable() }
  '
}

# Signature: a human-visible attribution line plus a machine marker. ADO strips HTML
# comments, so the marker is a display:none span — it survives sanitization, stays invisible
# when rendered, and remains greppable as "AIND-AGENT: <name>" in the stored comment text.
SIGNATURE="<br><br>— 🤖 AIND ${DISPLAY} Agent (run by ${ACTOR})<span style=\"display:none\">AIND-AGENT: ${AGENT}</span>"
FULL="$(printf '%s' "$MESSAGE" | md_to_html)${SIGNATURE}"

BODY="$(printf '%s' "$FULL" | jq -Rs '{text: .}')"

ORG="$(aind_org)"
URL="${ORG}/${AIND_ADO_PROJECT}/_apis/wit/workItems/${ID}/comments?api-version=7.1-preview.4"

# Send the body from a file, not an inline -d argument: on Windows/MSYS (Git Bash)
# multibyte UTF-8 in command-line args (e.g. the em-dash in the signature) gets mangled
# before it reaches curl.exe, corrupting the JSON so ADO rejects it ("must provide a value
# for the text parameter"). A temp file + --data-binary avoids the argument boundary.
TMP_BODY="$(mktemp)"
trap 'rm -f "$TMP_BODY"' EXIT
printf '%s' "$BODY" > "$TMP_BODY"

# Capture the response body AND the HTTP status so failures are self-explanatory. The old
# `curl -sf … >/dev/null` discarded both, turning ADO's actual error (e.g. the misleading
# "You must provide a value for the text parameter") into an opaque "failed to post".
RESP="$(curl -s -w $'\n%{http_code}' -u ":${AZURE_DEVOPS_EXT_PAT}" \
  -H "Content-Type: application/json; charset=utf-8" \
  -X POST \
  "$URL" \
  --data-binary @"$TMP_BODY")" || aind_die "could not reach ADO to post comment on work item $ID (network/curl error)"

HTTP_CODE="${RESP##*$'\n'}"
RESP_BODY="${RESP%$'\n'*}"
if [[ "$HTTP_CODE" != 2* ]]; then
  ADO_MSG="$(printf '%s' "$RESP_BODY" | jq -r '.message // empty' 2>/dev/null)"
  aind_die "comment POST to work item $ID failed (HTTP ${HTTP_CODE})${ADO_MSG:+: $ADO_MSG}"
fi

echo "aind: posted signed ${AGENT} comment to work item $ID"
