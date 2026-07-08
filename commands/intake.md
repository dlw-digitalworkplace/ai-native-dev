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
   - **Verdict:** `Intake approved` **iff every objective criterion passes _and_ the dependency
     gate (step 4) is clear**; otherwise `Intake declined`. Judgment criteria never block on
     their own.
   - **Readiness score (0–100, informational only — it does NOT change the gate).** Computed
     generically over whatever the rubric contains:
     - `objective_fraction` = (objective criteria passed) / (objective criteria total); use `1`
       if the rubric has no objective criteria.
     - `judgment_fraction` = (sum of judgment ratings) / (judgment criteria total), scoring
       **Good = 1, Partial = 0.5, Poor = 0**; use `1` if there are no judgment criteria.
     - `score = round( 100 × (0.5 × objective_fraction + 0.5 × judgment_fraction) )`.
     A story can score well and still be **declined** if any objective criterion fails — the
     score reflects design quality, the verdict is the gate. **The dependency gate (step 4)
     does not enter this formula at all:** a story that is perfectly defined can score **100**
     and still be declined solely because a story it depends on is not implemented yet.

4. **Run the dependency gate (a hard gate, separate from the rubric and the score).** A story
   that links to other stories it *depends on* (ADO **Predecessor** links) must not enter the
   flow before those dependencies are actually implemented — planning and building on top of
   unfinished work is the failure this catches. Resolve them deterministically:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-deps.sh" "$1"
   ```
   The script lists each dependency with its ADO state and AIND status, classifies it
   `IMPLEMENTED` / `NOT IMPLEMENTED` / `UNKNOWN` (implemented = AIND status
   `Implementation complete`, or — for a dependency not tracked by AIND — a done-like ADO
   state), and prints a final `DEPS_VERDICT:` line. Apply it:
   - **`DEPS_VERDICT: NONE`** (no dependency links) or **`MET`** (all implemented) → the gate is
     clear; the verdict is decided by the objective criteria alone.
   - **`DEPS_VERDICT: UNMET`** (any `NOT IMPLEMENTED` or `UNKNOWN`) → **the verdict is
     `Intake declined`**, *even if every objective criterion passes and the readiness score is
     100*. The story text may be flawless; it simply isn't ready to start yet.

   This gate **never changes the readiness score** (that stays purely rubric-driven) — it only
   affects the verdict, and the comment must say *why* (the specific unmet dependencies). It is
   also **not** a rubric criterion, so don't add a row for it in the score table; report it in
   its own section (below).

5. **Post the signed verdict as a table** via the signing script (never post comments any other
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

   ### Dependencies
   <If there are no dependency links, write "No linked dependencies." Otherwise list each
   dependency and its status, and — when the story is declined for an unmet dependency — state
   plainly that the story is well-defined but cannot start until the dependency below is
   implemented. Omit this section only if there are no dependency links AND nothing to note.>

   | Dependency | Status | Notes |
   |---|---|---|
   | AB#<id> — <title> | <IMPLEMENTED\|NOT IMPLEMENTED\|UNKNOWN> | <ADO state / AIND status> |

   ### Suggested fixes
   <concrete, actionable suggestions for the author; omit if approved and clean. An unmet
   dependency is a sequencing issue, not a story-text fix — note it in Dependencies above, not
   here, unless the story fails to even declare the dependency.>
   EOF
   ```
   Fill in the **real** criteria and results from the rubric — do not post the template
   literally, and do not invent criteria the rubric doesn't list.

   - **Rendering:** the comment field is HTML; the script converts a markdown subset —
     headings, `-`/`1.` lists, `**bold**`, `` `code` ``, paragraphs, and **pipe tables** (as
     above). Stay within it; avoid nested lists and links.

6. **Set the status tag** to match the verdict:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-status.sh" "$1" "Intake approved"   # or "Intake declined"
   ```

7. **Emit a lesson if the run taught you something reusable** (dreaming phase). If scoring surfaced a
   real, recurring signal — a rubric criterion that is ambiguous or hard to apply, a story-format gap
   you keep hitting — record it as a self-report so the dreamer can later synthesise it. **Emit
   nothing if there is no genuine lesson** (don't manufacture noise). State what happened and *why*,
   never a proposed fix. One command, body on stdin:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-emit-lesson.sh" "$1" intake observation self-report .claude/intake-rubric.md <<'EOF'
   <what happened + why — e.g. "criterion X is ambiguous because …"; the cause, not a fix>
   EOF
   ```

8. **Report** a one-line summary to the user: the verdict, the readiness score, and (if
   declined) the failing objective criteria **and/or the unmet dependencies**.

## Notes
- A declined story is edited by the human and resubmitted as `Ready for intake`, which
  re-runs `/intake`. The gate is unskippable.
- **A story declined only for an unmet dependency needs no text edit** — nothing is wrong with
  it. It becomes ready once the dependency is implemented; the human re-runs `/intake` then and
  the dependency gate clears. Say this in the report so the author doesn't hunt for a story
  problem that isn't there.
- Keep the comment factual and specific; cite the exact missing/weak element so the author
  can act without guessing.
