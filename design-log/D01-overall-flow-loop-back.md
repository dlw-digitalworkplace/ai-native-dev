# D1 — Overall flow + loop-back

- **Area:** Overall flow + loop-back
- **Date:** 2026-06-17
- **Status:** Active

## Decision
**Intake (story gate) runs FIRST; human plan review (plan gate) runs LAST.** Rejections route by **root cause**, not always back to the story: bad story → edit & re-intake; plan-level gap → planner revises *in the PR*; story problem found at plan review → back to intake **and close the stale plan PR**.

## Rationale
The intake gate must be unskippable and sit before any planning cost. Routing by root cause avoids over-rotating to the story for every plan failure.
