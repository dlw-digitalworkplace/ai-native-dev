# D7 — Build phase

- **Area:** Build phase (coder → review)
- **Date:** 2026-06-18
- **Status:** Active (CI portion amended by D34)

## Decision
**Once the plan PR merges, the build phase runs entirely in a code PR.** A **coding agent** implements the spec (`In implementation`); a **polish agent** (warm — shares the coder's context) does in-context cleanup (style, formatting, self-consistency) — not an independent check, by design. The coder opens the **code PR**; **CI** owns the objective gates *(amended by **D34**: CI is not a flow gate — the coder getting build + tests green **before** the PR is the objective gate, and any project CI on the PR is orthogonal to AIND)*. A **reviewer agent** — *cold: separate invocation, re-grounded only from PR diff + spec + project rules, never the coder's transcript* — reviews spec alignment + missed edge cases. Coder↔reviewer iterate in the PR for **≤3 reviewer passes** (a pass = reviewer comments → coder fixes or rebuts in-thread); the loop **exits early on reviewer approval**. Unresolved after the 3rd pass → **a human reads the threads and posts a verdict; the coder executes it; one final reviewer pass; then merge**. None of this loop moves the tag (coarse/fine split, D4) — the item stays `In implementation` until merge → `Implementation complete`. Coder and reviewer are each modelled as a single agent here, but either may be split into skill-specific agents per project.

## Rationale
Mirrors the plan-phase pattern: fine iteration in the PR, coarse state in ADO. The polish/reviewer split avoids paying twice for one checklist — warm polish does what the coder's context makes cheap (style, consistency); cold review is the genuine independent gate (spec, edge cases). Independence is enforced structurally, not by instruction. The cap with thread-visible disagreement hands the human the real exchange, not a synthesized summary; human-as-tiebreaker (verdict, coder executes) keeps the "agents do the work" pattern intact.
