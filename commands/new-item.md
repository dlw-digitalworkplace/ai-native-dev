---
description: Create a new AIND work item — a short guided Q&A, then a drafted file (file tracker) or a created Azure DevOps story (ADO tracker), left for your review before the flow starts.
argument-hint: "[title]"
allowed-tools: Bash, AskUserQuestion, Read, Edit
---

# /new-item — draft a new work item for review

You help a human create a work item. You **gather the story through a few questions, let the script
create it (assigning the id), fill in what the human told you, and hand it back for review** — you
never invent requirements, and you never start the flow yourself. Suggest, don't assert: the human
owns the story text.

This works on **either tracker**: the **file** backend scaffolds one markdown file per story; the
**ADO** backend creates the story directly in Azure DevOps Boards. Step 1 tells you which.

## 1. Detect the tracker backend
```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-tracker.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" kind
```
`file` → follow the **file** path in steps 3–5; `ado` → follow the **ADO** path. The gathering in
step 2 is the same either way.

## 2. Gather the story (a few concise questions)
Use `$ARGUMENTS` as the starting **title** if the user supplied one. Elicit, briefly and
conversationally (plain questions in chat — not a rigid form), only what you don't already have:

- **Title** — one line, imperative (e.g. "Add CSV export to the reports page").
- **Description** — what needs to happen and *why*; a sentence or two of context plus the specifics.
- **Acceptance criteria** — the observable conditions that make it "done"; one per line. If the user
  is vague, ask once for a concrete example rather than inventing criteria — leave a `TODO` if they
  genuinely don't know yet.
- **Dependencies (optional)** — ids of other items that must be **Implementation complete** before
  this one starts. Only ask if it's plausibly relevant; default to none.

Keep it short — this is a drafting aid, not an interrogation. Don't fabricate content the user didn't
give you; a thin-but-honest first draft they refine beats a padded one.

## 3. Create the item (script assigns the id)

### File tracker
```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-tracker.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" new "<title>"
```
It prints `<id> <path>` and scaffolds the file from the template with `state: Ready for intake` and
the `id`/`title` filled. Capture both values, then **fill it in (file step 4)**.

### ADO tracker
The story's description and acceptance criteria go on **stdin** in one heredoc, separated by a line
reading exactly `---AIND-AC---` (description before it, acceptance criteria after). Add
`--deps "<id>,<id>"` only if the user named dependencies (omit it otherwise). One command, no pipe:
```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-tracker.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" new "<title>" <<'EOF'
<description — a sentence or two of what and why>

---AIND-AC---
- <acceptance criterion 1>
- <acceptance criterion 2>
EOF
```
It creates the story (as the configured work-item type, default **User Story**), sets
`AIND status - Ready for intake`, links any `--deps` as predecessors, and prints `<id> <url>`.
Capture both. If the user gave no acceptance criteria yet, still include the `---AIND-AC---` line
with a single `- TODO` under it. **ADO stories are edited in the ADO web UI — there is no file to
edit, so skip step 4 and go to step 5.**

**If the create fails, surface the script's error to the user verbatim — do not silently fall back to
drafting the story for manual entry in the Boards UI.** The most common failure is a work-item type
mismatch: an error like `VS402323: Work item type <X> does not exist in project …` means this
project's process template doesn't have that type. Tell the user to set **`ado.workItemType`** in
`.claude/aind.settings.json` to a type the project actually has (e.g. `Product Backlog Item` for the
Scrum process, `Issue` for Basic, `User Story` for Agile) and re-run. Do not guess the type by editing
their config yourself.

## 4. Fill in what you gathered *(file tracker only)*
`Read` the created file, then `Edit` **only**:
- the `## Description` section body — replace the placeholder comment with the description.
- the `## Acceptance Criteria` section body — replace the placeholder with the criteria (one `-` per
  line).
- if the user gave dependencies, the front-matter `dependsOn:` line → `dependsOn: <id>, <id>`
  (comma-separated ids; leave it empty otherwise).

Leave the rest of the front-matter (`state`, `links`, `attachments`, `durationSeconds`) and the
`## Comments` section exactly as scaffolded — the flow drives those. Preserve the file's structure
(the front-matter fences, the `##` headings); don't reorder or rename sections.

If any dependency id has no matching item file yet, note it to the user (intake will later flag it as
UNKNOWN) — don't block on it.

## 5. Hand it back for review
Show the user:
- the assigned **id** and the artifact — the **file path** (file tracker) or the **ADO URL** (ADO
  tracker),
- a short recap of what you drafted (title + the acceptance criteria), and
- the clear next steps: **review and edit the story** (the file's Description / Acceptance Criteria,
  or the ADO story in the web UI), then run **`/aind:intake <id>`** to start the flow.

Do not run intake or change the status yourself — creation ends here, at a draft awaiting the human.
