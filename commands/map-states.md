---
description: Discover this project's native ADO work-item States and map the AIND statuses onto the ones that already exist, so status transitions mirror to the board. Adopts existing states — never forces new ones.
argument-hint: "[work-item-type]"
allowed-tools: Bash, AskUserQuestion, Read
---

# /map-states — adopt the project's existing ADO States for the status mirror

> **ADO tracker only.** This command applies when work items live in **Azure DevOps Boards**
> (`tracker: "ado"`). With the **file** tracker there is no separate native State to mirror — the
> AIND state *is* the item's `state:` field — so if `AIND_TRACKER=file`, stop and tell the user this
> step doesn't apply.

You configure the **native-State mirror**: when the flow moves a story through its phases, the ADO
work item's built-in **State** field should follow, so anyone reading the board sees progress without
looking at the AIND tag. You do this by **adopting the states the project already has** — you never
create, rename, or require particular states. The result is written to `.claude/aind.settings.json`
as a `stateMap`; the runtime reads it and mirrors after each tag write. Re-run this anytime the org
or process template changes its states.

## 1. Resolve the work-item type
If the user passed a type as `$1`, use it. Otherwise ask which work-item type the flow's stories use
(via `AskUserQuestion` — typical answers: `User Story`, `Product Backlog Item`, `Issue`, or a custom
type). If they gave you a sample work-item id instead, you may read its type first:
```bash
az boards work-item show --id <sample-id> --org "$AIND_ADO_ORG" --query 'fields."System.WorkItemType"' -o tsv
```

## 2. Get the proposed mapping
```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-states.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" propose "<work-item-type>"
```
Each line is TSV: `<aind-status>  <category>  <resolved-state>  <count>  <candidate1|candidate2|…>`.
The script fixes each AIND status to a universal **category** (`Proposed`/`InProgress`/`Resolved`/
`Completed`) and reports the concrete state(s) in that category for this project:
- **`count = 1`** → `resolved-state` is filled: **accept it automatically, do not ask.** This is the
  common case and the whole point — no human effort where the choice is obvious.
- **`count > 1`** → several states share the category: **ask** the user (`AskUserQuestion`) to pick
  one from the candidate list, or to leave that AIND status unmapped.
- **`count = 0`** → no state in that category: **ask** whether to map this AIND status to one of the
  project's *other* states (run `aind-states.sh discover "<work-item-type>"` to show the full list)
  or leave it unmapped. Leaving it unmapped is a fine answer — that status simply won't mirror.

Only prompt for the genuinely ambiguous rows. Batch the questions where you can.

## 3. Write the map
Assemble the accepted rows into one JSON object `{"<aind-status>":"<state>", …}` (omit any left
unmapped) and write it:
```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-states.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" write <<'EOF'
{"Generating plan":"Active","In implementation":"Active","Implementation complete":"Closed"}
EOF
```
(Use the states you actually resolved — the above is only an illustration.)

## 4. Report
Tell the user: which AIND statuses were auto-mapped (and to which state), which you asked about, and
which were left unmapped. Remind them the AIND tag stays the source of truth — the native State is a
best-effort mirror, and an unmapped or failed transition never blocks the flow. Point out they can
re-run `/aind:map-states` after any change to the project's states.

## Notes
- Needs the project config loaded (`.claude/aind.settings.json` + a PAT in `.claude/aind.env`) — run
  `/aind:onboard` first if it isn't set up.
- Several AIND phases share the `InProgress` category (planning through implementing), so they
  intentionally collapse onto the same "active"-style state. That is the expected coarse rendering,
  not a bug.
