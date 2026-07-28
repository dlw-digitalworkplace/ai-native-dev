# D20 — Role packaging

- **Area:** Role packaging (supersedes D19)
- **Date:** 2026-06-26
- **Status:** Supersedes D19

## Decision
**Revert intake and the planner from cold subagents back to in-session slash commands** (`/aind:intake`, `/aind:plan`); the `agents/intake.md` / `agents/planner.md` subagents are deleted. Per-role model selection — D19's decisive driver — is obtained instead by **choosing the session model per invocation** (`claude --model …` or `/model`), which is natural because intake and planning are separated by the human plan-review gate and are never run in one continuous session. **Cold subagents remain reserved for the genuinely independent checks** (reviewer, test-writer, E2E, dreamer), where independence from the work being checked is the whole point.

## Rationale
Live testing showed D19's drivers did not hold up. Headless runs work fine from a command (`claude -p "/aind:intake <id>"`), so automation never needed a subagent; "redundant warmth" only established that cold was *possible*, not better; and per-role model — the one strong driver — is met more simply by per-session model choice, since the two phases share no session (they are gated apart by human plan review). Against near-zero benefit, the subagent form imposed real friction: a fresh subagent context does **not** inherit the session's permission approvals, so the scripts re-prompted on every run; the command→Task→subagent indirection was less stable; and cold re-grounding cost tokens and latency for roles that *author* artifacts a human then reviews rather than *independently verifying* another agent's work. Industry practice favors the simplest architecture that works — reserve subagents for parallelism, hard context limits, or independent verification — none of which intake/planner need. The revert also sharpens the cold/warm line: **cold = independent verification only; warm command = human-facing authoring**. The fan-out case (orchestrating many stories at once) is out of current manual scope (D6); a subagent can be reintroduced then if that need is real.
