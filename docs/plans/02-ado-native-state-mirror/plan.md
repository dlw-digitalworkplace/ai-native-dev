# PR-02 — Mirror AIND status into the native ADO work-item State

_Status: planned (re-based 2026-07-28 onto v0.18.0 / D42; **reshaped 2026-07-29 in a sparring
session** — the mapping is now **discovered and auto-adopted** from the project's existing states,
not hand-authored config; see Implementation approach). Extends D4 (single AIND status tag) without
replacing it. New D-entry required (D43+)._

## Context
The AIND status tag (`AIND status - <state>`) is the flow's state machine, but it is invisible to
anyone reading the board columns — a PM or functional analyst sees the native State field
(New/Active/Resolved/Closed or the project's process-template equivalents), not tags. Requirement:
when the harness moves a story through its phases, the native ADO State should follow where a
mapping exists — `/plan` → an "in planning"-like state, plan approval → its state, `/implement` →
Active/Doing, `/complete` → Done/Closed.

## Keep it simple (non-goals)
- The AIND tag remains the **source of truth** for the flow; the native State is a *mirror*,
  never read back by any gate or precondition. No agent decision ever depends on the native State.
- We **adopt the states the project already has** — never create, rename, or require specific
  states, and never force our own onto a template. The map is *produced* by discovering the
  project's states (below), not hand-authored; an AIND status with no sensible existing state is
  left unmapped and silently skipped (mirror is best-effort).
- No mirroring of intermediate/error states (`Needs attention`, `Intake declined`) in v1 — those
  are flow-internal; add later if wanted.

## Implementation approach
Two parts. **(1) Discover-and-adopt (the new heart of this feature).** A standalone command
discovers the project's actual work-item states and their **categories** — `Proposed` / `InProgress`
/ `Resolved` / `Completed` / `Removed`, the universal buckets every process template shares — then
**auto-maps** each AIND status to the sensible existing state by category (e.g. `In implementation`
→ the `InProgress` state, `Implementation complete` → the `Completed` state). It writes the resolved
map to `aind.settings.json` and **only prompts the human on serious doubt**: a category with no state
or several plausible candidates (suggest-don't-assert). The human almost never types or picks a
state — we work with what exists, so there is no per-project/per-org burden of forcing our own.
**(2) Mirror at runtime (unchanged shape).** `aind-status.sh` reads the resolved map and moves the
native State after each tag write, so mirroring rides every existing call site for free; the only
new surface is the discovery command that *produces* the map.

## Task breakdown
1. **New** `scripts/aind-states.sh` — `discover`: query the project's work-item-type states +
   categories via the ADO REST API (`…/wit/workItemTypes/{type}/states`, PAT auth the plugin
   already uses). `map`: auto-resolve each AIND status to the sensible existing state **by category**
   (the AIND-status→category *intent* is fixed in the flow; the concrete state *name* comes from the
   project), picking automatically when a category has one obvious candidate and **only asking
   (`AskUserQuestion`) when a category has zero or several**; then write the resolved `stateMap` into
   `.claude/aind.settings.json`. Best-effort, idempotent, re-runnable.
2. **New** `commands/map-states.md` (`/aind:map-states [work-item-type]`) — thin command:
   discover → auto-map → confirm only the ambiguous rows → write. Re-run it whenever an org/template
   changes its states (the drift path). This is the "capture existing states and map them to our
   process" command.
3. `commands/onboard.md` / `commands/kickstart.md` — call the mapping step as one optional,
   human-gated action (offer to mirror the native State → run discovery/map), instead of asking the
   human to hand-author anything.
4. `scripts/aind-status.sh` — after writing the tag (existing behavior, unchanged), look up the
   status in `AIND_STATE_MAP`; if mapped, `az boards work-item update --state "<value>"`.
   **Tag write first, mirror second; a mirror failure warns and exits 0** — the flow must never fail
   because a board column couldn't move — **and emits a lesson** (`aind-emit-lesson.sh`, severity
   `observation`, area = the state map), so recurring mirror failures cluster in the next dream cycle
   instead of rotting in a lost stderr line while the board quietly diverges.
5. `scripts/aind-common.sh` — surface the settings `stateMap` as **`AIND_STATE_MAP`** (D41), so the
   env-var interface `aind-status.sh` reads is unchanged.
6. `design-log/` — D-entry: **adopt-existing-states-via-categories** (work with what the template
   has; never force our own — the burden-avoidance rationale) and **auto-map, ask only on serious
   doubt** (suggest-don't-assert); **projection, not dual truth** — the tag is fine-grained machine
   state, the native State a coarse human rendering (a CI pipeline projecting onto a commit status,
   not two competing sources), which answers "why not just use the ADO State?" (too coarse —
   `Generating plan` and `Plan ready for review` are both just `InProgress`); best-effort + lesson
   semantics; unmapped = skip. Reading rule: agents read tags, humans read columns.

## Assumptions & open questions
- **Which work-item type?** Discovery needs the type the flow's stories use (User Story / Product
  Backlog Item / Issue / custom). Detect it from a sample story on the board, or take it as the
  command arg / ask once. Recommend detect-then-confirm.
- **Many AIND statuses → one state is expected, not a bug.** Several AIND phases (`Generating plan`,
  `Plan ready for review`, `Ready for implementation`, `In implementation`) share the `InProgress`
  category, so they collapse to the one Active-ish state — the intended coarse rendering.
- **Error/edge statuses** (`Needs attention`, `Intake declined`): usually no clean category match →
  left unmapped (skip) unless the human maps them at the ambiguity prompt. Matches the non-goal.
- **Categories are the signal, concrete names the value** — relies on the states API returning each
  state's `category`; verify the field's name/shape live (the plugin's "trust a live run" habit).

## Definition of done
- [ ] `/aind:map-states` on a real project discovers its states and writes a correct `stateMap`
      **without prompting** when each category is unambiguous.
- [ ] It prompts **only** when a category is empty or has several candidates.
- [ ] With a mapping present, each phase transition moves the native State; the board reflects flow.
- [ ] With no mapping (default / command never run), behavior is byte-identical to today.
- [ ] A failing native-state write never fails the calling command (warn-only) and emits a lesson.
- [ ] Re-running after a template change re-maps cleanly. D-entry recorded.

## Files affected
`scripts/aind-states.sh` (new: discover/map), `commands/map-states.md` (new),
`scripts/aind-status.sh`, `scripts/aind-common.sh` (map `stateMap` → `AIND_STATE_MAP`),
`project-template/aind.settings.sample.json` (example only — the map is produced, not required),
`commands/onboard.md`, `commands/kickstart.md`, `design-log/`.
