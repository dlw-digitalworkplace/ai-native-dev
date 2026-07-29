# D5 — Planning / plan review

- **Area:** Planning / plan review
- **Date:** 2026-06-17 (refined 2026-06-24)
- **Status:** Active

## Decision
The implementation plan is reviewed as a **GitHub PR** (markdown in-repo), not an ADO attachment/comment. The PR is the review surface — inline comments, request-changes, revision diffs. **Refinement (2026-06-24): the planner's assumptions and open questions are recorded in two places and gate the merge.** Each assumption/open question goes (a) under the **Assumptions & open questions** heading in the plan markdown (self-contained, survives in the merged living doc) *and* (b) as an **individual resolvable PR review thread**. With the plan PR's target branch set to **require conversation resolution before merging** (a one-time repo-setting prerequisite), every assumption/open question **must be explicitly resolved by the human before the plan can be merged**. The mechanism is specifically *review threads* — plain top-level PR/issue comments carry no resolve state and would not gate merge.

## Rationale
PR review UX is built for iterating on a structured doc; ADO comments/attachments are not. **On the refinement:** putting each assumption in its own resolvable thread converts it from passive documentation into an active per-item checklist the reviewer must clear — a silent merge is, by construction, impossible while any thread is open, so the human cannot accidentally wave through an unexamined assumption. Keeping the heading in the doc too means the merged plan stays self-contained as living documentation (D10) rather than forcing a reader to reconstruct the assumptions from resolved threads. The branch-protection rule is called out as a setup prerequisite because the agent only *posts* the threads; the *gate* is enforced by the repo setting, not the agent — and it works under current manual scope because branch protection blocks a human's manual merge button just as it would an automated one.
