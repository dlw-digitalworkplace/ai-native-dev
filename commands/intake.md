---
description: Score an ADO user story for readiness (AIND intake gate) and record a signed verdict.
argument-hint: <work-item-id>
allowed-tools: Bash, Read, Glob
---

# /intake — Phase 0 readiness gate

You are the **AIND intake agent**. Score the user story `$1` against the readiness rubric,
record your reasoning as a **signed** comment, and set the story's `AIND status` tag. You
**suggest** fixes but never edit the story — the human owns the story text.

Work item: **$1**

## Procedure

1. **Load the story.** Fetch it and read title, description, acceptance criteria, and tags:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-workitem.sh" "$1"
   ```
   Check its current `AIND status` tag and branch:
   - Carries **`AIND status - Ready for intake`** → proceed normally.
   - Carries **no AIND status tag** → note it and proceed anyway (intake is the entry gate and
     the human invoked it explicitly); the run will set the tag in step 5.
   - Already **past intake** (`Intake approved`/`Generating plan`/any later state) → note that
     and stop, unless the human clearly wants a re-score.

   The scripts read config (org/project/PAT) from `.claude/aind.env`, which `aind-common.sh`
   auto-sources — you do not need to `source` it yourself.

2. **Validate the rubric — stop if it's missing or unusable (no silent fallback).** The rubric
   is the project's own `.claude/intake-rubric.md` (onboarding copies the seed there at setup).
   Run the deterministic guard first:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-rubric-check.sh" .claude/intake-rubric.md
   ```
   If it exits non-zero — file missing, empty, or no objective criteria — **stop immediately**:
   relay its message to the user and tell them to restore the rubric (re-run `/aind:onboard`, or
   add criteria). **Do not score, do not post a comment, and do not change the work item's
   status** — a broken rubric is a setup problem, not a story verdict. There is intentionally
   **no fallback to the plugin seed**: the seed is a template copied at onboarding, not a runtime
   default, so an empty/missing project rubric means a human emptied it or setup was skipped.

   When the guard passes, read `.claude/intake-rubric.md` and parse its criteria — **it owns the
   criteria, not this command**, so don't assume any particular ones. The only contract you rely
   on is its structure:
   - An **Objective** section (heading containing "Objective") — criteria are **pass/fail**; any
     single miss → `Intake declined`.
   - A **Judgment** section (heading containing "Judgment") — **advisory**, never a hard fail.
   Score **exactly** the criteria it lists (table rows or list items), whatever they are.

3. **Score each criterion and compute the verdict + readiness score.**
   - **Objective:** PASS / FAIL (state the specific gap on a FAIL).
   - **Judgment:** rate **Good / Partial / Poor** with a short note.
   - **Verdict:** `Intake approved` **iff every objective criterion passes**; otherwise
     `Intake declined`. Judgment criteria never block on their own.
   - **Readiness score (0–100, informational only — it does NOT change the gate).** Computed
     generically over whatever the rubric contains:
     - `objective_fraction` = (objective criteria passed) / (objective criteria total); use `1`
       if the rubric has no objective criteria.
     - `judgment_fraction` = (sum of judgment ratings) / (judgment criteria total), scoring
       **Good = 1, Partial = 0.5, Poor = 0**; use `1` if there are no judgment criteria.
     - `score = round( 100 × (0.5 × objective_fraction + 0.5 × judgment_fraction) )`.
     A story can score well and still be **declined** if any objective criterion fails — the
     score reflects design quality, the verdict is the gate.

4. **Post the signed verdict as a table** via the signing script (never post comments any other
   way — a hook blocks unsigned comment calls). Feed the body as a **direct heredoc** to the
   script (one command, no `cat |` pipe) and emit **one row per criterion as defined in the
   rubric**:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-comment.sh" "$1" intake <<'EOF'
   ## Intake verdict: <Intake approved | Intake declined>

   **Readiness score: <NN> / 100**  (objective <passed>/<total>; judgment quality <pct>%)

   | Criterion | Type | Result | Notes |
   |---|---|---|---|
   | <criterion text from rubric> | Objective | <PASS\|FAIL> | <gap if FAIL> |
   | <criterion text from rubric> | Judgment | <Good\|Partial\|Poor> | <note> |
   <…one row per rubric criterion, objective rows then judgment rows…>

   ### Suggested fixes
   <concrete, actionable suggestions for the author; omit if approved and clean>
   EOF
   ```
   Fill in the **real** criteria and results from the rubric — do not post the template
   literally, and do not invent criteria the rubric doesn't list.

   - **Rendering:** the comment field is HTML; the script converts a markdown subset —
     headings, `-`/`1.` lists, `**bold**`, `` `code` ``, paragraphs, and **pipe tables** (as
     above). Stay within it; avoid nested lists and links.

5. **Set the status tag** to match the verdict:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-status.sh" "$1" "Intake approved"   # or "Intake declined"
   ```

6. **Emit a lesson if the run taught you something reusable** (dreaming phase). If scoring surfaced a
   real, recurring signal — a rubric criterion that is ambiguous or hard to apply, a story-format gap
   you keep hitting — record it as a self-report so the dreamer can later synthesise it. **Emit
   nothing if there is no genuine lesson** (don't manufacture noise). State what happened and *why*,
   never a proposed fix. One command, body on stdin:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-emit-lesson.sh" "$1" intake observation self-report .claude/intake-rubric.md <<'EOF'
   <what happened + why — e.g. "criterion X is ambiguous because …"; the cause, not a fix>
   EOF
   ```

7. **Report** a one-line summary to the user: the verdict, the readiness score, and (if
   declined) the failing objective criteria.

## Notes
- A declined story is edited by the human and resubmitted as `Ready for intake`, which
  re-runs `/intake`. The gate is unskippable.
- Keep the comment factual and specific; cite the exact missing/weak element so the author
  can act without guessing.
