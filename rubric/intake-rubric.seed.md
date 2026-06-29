# Intake readiness rubric — AIND core (seed)

> **This is the seeded core (AIND framework default).** A project installs the AIND
> plugin and copies this file to `.claude/intake-rubric.md`, then **edits it in place**
> to add project-specific criteria.
>
> The core is a **strong default, not an enforced floor**: because the
> project copy is a single editable file, a team *can* remove or change core items —
> nothing structurally prevents it. If enforcement is ever needed, promote the core to a
> read-only merged layer.

The intake agent scores a story against this rubric and records its reasoning as a
signed comment on the work item. It **suggests** fixes but never edits the story —
the human owns the story text.

The rubric is **hybrid**:

- **Objective criteria are pass/fail.** Any miss → `Intake declined`. These are the hard gate.
- **Judgment criteria are advisory.** The agent surfaces them as comments, never as a hard
  fail — consistent with "the agent suggests, it does not author."

A story passes intake (→ `Intake approved`) **iff every objective criterion passes**.
Judgment criteria never block on their own; they are recorded as advice for the author.

> **Contract with the `/intake` command (keep this when you edit).** The command does **not**
> hardcode any criteria — it reads *this file* and scores whatever it finds. All it relies on is
> the structure: an **Objective** section (heading containing the word "Objective") whose entries
> are pass/fail, and a **Judgment** section (heading containing "Judgment") whose entries are
> advisory. List one criterion per table row (or list item) under each. Add, remove, or rename
> criteria freely; just keep the two section headings so the command can find them. **How** the
> results are scored and rendered (the readiness score, the table) is the command's job, not the
> rubric's.

---

## Objective criteria (pass/fail — any miss declines the story)

| # | Criterion | How to check |
|---|-----------|--------------|
| O1 | **Title present and non-trivial** | Title exists and is more than a placeholder ("test", "fix", "tbd", a single word). |
| O2 | **At least one acceptance criterion exists** | The story body or AC field contains ≥1 concrete acceptance criterion. |
| O3 | **Intent is stated** | A user-story form ("As a … I want … so that …") *or* a clear problem/goal statement. The "As a…" form is **not** forced rigidly. |
| O4 | **No unresolved placeholders** | No `TODO`, `???`, or `TBD` (case-insensitive) anywhere in the body or ACs. |
| O5 | **Dependencies/blockers are named or explicitly "none"** | The story names its dependencies/blockers, or explicitly declares there are none. Silence is a miss. |

## Judgment criteria (advisory — surfaced as comments, never a hard fail)

| # | Criterion | What good looks like |
|---|-----------|----------------------|
| J1 | **ACs are testable/observable** | Each AC is verifiable, not subjective ("works well", "fast enough", "looks nice"). |
| J2 | **Single-sized, not an epic in disguise** | The story is one deliverable, not a bundle of features that should be split. |
| J3 | **Internally coherent** | Title, intent, and ACs agree with one another — no contradictions. |
| J4 | **Enough context for a planner** | A planner can act on the *what* without guessing; the *how* is explicitly the planner's job, not the story's. |
