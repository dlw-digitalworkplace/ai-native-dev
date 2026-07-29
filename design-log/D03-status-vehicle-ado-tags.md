# D3 — Status vehicle

- **Area:** Status vehicle (cross-cutting)
- **Date:** 2026-06-17
- **Status:** Active

## Decision
Express status via **ADO tags** for v1 (not a custom field or the State machine), namespaced under `AIND` (AI Native Dev) — see D4.

## Rationale
Custom-field/process customization may be unavailable to the team; tags need zero setup. Namespacing makes them filterable and collision-free. **Known limitation:** tags are additive and uncontrolled — handled by the single-tag rule in D4.
