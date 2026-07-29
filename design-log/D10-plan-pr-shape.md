# D10 — Plan PR shape

- **Area:** Plan PR shape
- **Date:** 2026-06-24
- **Status:** Active

## Decision
**Separate plan-PR, merged to the project's integration branch first.** The plan is its own PR on its own branch and **merges to whatever branch the project treats as its integration/working trunk** (e.g. `main`, `develop`, or a `release/x.y` branch — the branch name is deliberately left to each project's branching strategy) **before any code branch exists**; the code PR comes later on a separate branch and targets the same integration branch. **Not** same-branch (plan + code co-evolving on one branch/PR). The plan markdown lives at **`/plans/<work-item-id>/plan.md`**, and it is **permanent living documentation** — it stays in the repo after the code ships, not a throwaway. This makes "the merged spec" that D7/D8/D9's cold agents re-ground from a concrete, stable, addressable artifact.

## Rationale
The entire build phase rests on a **frozen spec**: the cold reviewer (D7), cold test-writer (D8), and cold E2E agent (D9) all re-ground "from the merged spec," which only means something if the spec is genuinely merged and immutable before build begins. Same-branch would make the spec a moving target on the branch and turn the plan gate soft. The only cost — a second PR per story — is cheap next to the independence guarantee it buys. The branch name is left open because branching strategy is per-project (trunk-based, git-flow, release branches) and pinning it centrally would impose a workflow we don't own; the design only requires that the plan merges to the integration branch *first*. A stable `/plans/<id>/plan.md` path gives every cold agent a deterministic re-grounding source; keeping it as living docs means the spec stays discoverable next to the code it produced.
