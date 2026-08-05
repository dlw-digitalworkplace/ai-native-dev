---
description: Create a new AIND work item (file tracker) — a short guided Q&A, an auto-assigned id, and a drafted markdown file left for your review before the flow starts.
argument-hint: "[title]"
allowed-tools: Bash, AskUserQuestion, Read, Edit
---

# /new-item — draft a new work item for review

You help a human create a work item in the **file tracker** (one markdown file per story). You
**gather the story through a few questions, let the script assign the id and scaffold the file, fill
in what the human told you, and hand it back for review** — you never invent requirements, and you
never start the flow yourself. Suggest, don't assert: the human owns the story text.

## 1. Guard — file tracker only
This command only applies when work items are stored as files. Check the backend:
```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-tracker.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" kind
```
If the output is **not** `file`, stop and tell the user: with the **ADO tracker** stories are created
in Azure DevOps Boards (the UI / their normal backlog tooling), then run `/aind:intake <id>` against
the created id — this command doesn't apply. Do not proceed.

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

## 3. Create the file (script assigns the id)
```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-tracker.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" new "<title>"
```
It prints `<id> <path>` and scaffolds the file from the template with `state: Ready for intake` and
the `id`/`title` filled. Capture both values.

## 4. Fill in what you gathered
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
- the assigned **id** and the **file path**,
- a short recap of what you drafted (title + the acceptance criteria), and
- the clear next steps: **review and edit the file** (especially Description / Acceptance Criteria),
  then run **`/aind:intake <id>`** to start the flow.

Do not run intake or change the status yourself — creation ends here, at a draft awaiting the human.
