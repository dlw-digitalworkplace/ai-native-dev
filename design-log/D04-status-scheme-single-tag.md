# D4 — Status scheme

- **Area:** Status scheme (cross-cutting)
- **Date:** 2026-06-17
- **Status:** Active

## Decision
A single **`AIND status - <state>`** tag tracks the coarse phase. **Exactly one AIND-status tag per item at any time; every transition = remove-old-then-add-new, atomic.** States: `Ready for intake` / `Intake declined` / `Intake approved` / `Generating plan` / `Plan ready for review` / `Ready for implementation` / `In implementation` / `Implementation complete`. ADO tag = coarse phase; each GitHub PR (plan PR, then code PR) owns its fine-grained iteration (no PR-review states mirrored into tags). `Generating plan` and `In implementation` are kept as progress/diagnostic flags with a staleness timeout. Human-set: `Ready for intake`, `Ready for implementation`; agent-set: intake/plan states plus `In implementation`; set on merge: `Implementation complete` (mechanism resolved in D13).

## Rationale
Namespaced, queryable, respects request/assert. Coarse/fine split prevents two drifting sources of truth. The diagnostic in-progress flag aids trigger debugging (Q2).
