# PR-07 — Plan co-forming: interactive sparring when attended, threads when not

_Status: **implemented 2026-07-30 (D44)** — re-based onto v0.18.0 and built; the attended/headless
run mode is **configurable** (added from review — see the resolved detection question). Independent
of the registry chain. Reconciles D5/D23's proceed-on-assumption doctrine — the invariant is *no
silent decision*, not "never ask"._

## Context
The plan phase is designed as "never block waiting for an answer — proceed on assumption, record
it as a thread." That is correct for headless runs, but it makes the attended experience "hey AI,
create a plan," when the intended model is co-forming: the agent asks the relevant questions
live, the dev supplies vision and decisions, and the plan is formed together — the plan PR then
being the *record* of decisions already made, its threads carrying only what genuinely stayed
open. Kickstart already proves the mechanism (`AskUserQuestion`, batched, adaptive).

## Keep it simple (non-goals)
- Headless behavior is untouched: no interactive capability → today's proceed-on-assumption path,
  byte-identical. This PR adds a mode, it does not replace the doctrine.
- Sparring elicits **decisions**, not the whole plan interactively — the agent still drafts first;
  the conversation resolves the drafted assumption list before the PR carries it.
- No new command; `/aind:plan` create mode gains the pass.

## Implementation approach
**Triage, steer, draft, spar — planning proportional to the story.** Attended planning becomes a
rhythm whose weight the agent proposes and the dev confirms. **Triage:** during early grounding,
judge the story's real size on evidence (single-file surface, no data boundary, no cross-cutting
rules touched, ACs trivially checkable). Clearly trivial → propose fast-track in one line — "this
is a simple null check; I suggest skipping the questions: micro-plan, approve and implement
immediately. OK?" — one tap. Accepted → skip steer and spar, write the **micro-plan** (the D23
template already collapses on trivial stories: context + task + DoD, no fabricated sections), open
the plan PR, and tell the dev it's ready for immediate `/approve-plan`. Proportionality, never
exemption: **the plan artifact and the cold-review oracle chain are never skipped — they shrink.**
**Steer** (non-trivial, attended): before drafting — and before the dev sees any agent proposal —
one open question: the dev's own take (approach, constraints, landmines, prior art), or "go". This
keeps the dev the *author* of the intent and captures the ground truth no artifact holds (client
context, upcoming refactors, prior attempts). **Draft:** the planner grounds and drafts exactly as
today (proceed-on-assumption, unchanged) — the steer is **input, never contract**: it is validated
against the codebase, and wherever the draft deviates from the steer or the code argues against
it, that disagreement becomes an explicit spar item, never a silent override and never silent
deference. **Spar:** present the drafted **Assumptions & open questions** list interactively and
resolve each either/or live. Resolved items are rewritten into the plan body as decisions;
deferred items stay and become threads exactly as today. **One planning engine, two resolution
channels:** attended and headless run the identical drafting process and produce the identical
artifact — only where inputs arrive and where assumptions get resolved differ. Question quality is
the existing thread bar (genuine either/or, both options named — D5/D23), not new machinery.

## Task breakdown
_Re-base note (2026-07-28): the step labels below (`1.4`, `1.5`, `4.5`) were drafted against the
pre-v0.18.0 `commands/plan.md`; that file has since grown (D42 telemetry `begin`/`report` brackets;
the D40 worktree grounding note — "work in the worktree freely; close-out returns you to main").
Treat the labels as **relative positions** (triage before grounding, steer before drafting, spar
after the assumptions list and before the PR opens) and re-derive the actual numbers against the
current file. The progressive-disclosure concern below is sharper now that plan.md is heavier._

1. `commands/plan.md` frontmatter — add `AskUserQuestion` to allowed-tools.
2. `commands/plan.md` — new step 1.4 **"Triage (attended only)"**: judge size on evidence from the
   story + a quick code look; clearly trivial → propose fast-track via AskUserQuestion (one tap:
   fast-track / full). Accepted → skip steps 1.5 and 4.5, write the micro-plan, open the PR, report
   "trivial — ready for immediate /approve-plan". Declined or not clearly trivial → full path. The
   triage criteria are listed in the prompt (evidence, not vibes); when in doubt, full path.
3. `commands/plan.md` — new step 1.5 **"Steer (attended only)"**, after triage, before grounding:
   ONE open prompt — "Your take before I draft? Approach, constraints, things to avoid, prior art —
   or say go." "Go" is a fully respected answer, three seconds, zero follow-up. A given steer is
   recorded in the plan's **Context** (one line, provenance: dev-seeded) and guides grounding (read
   what the steer points at). The steer is input, not contract: any draft deviation from it, and
   any codebase evidence against it, MUST surface as a spar item / thread ("you suggested X; the
   existing pattern is Y because Z — A or B?") — never silently obeyed, never silently overridden.
   When a steer beats what a rule implied, emit a lesson (the rule is stale).
4. `commands/implement.md` — one guard line ("everything is a null check until it isn't"): when a
   story's plan is a fast-track micro-plan and the change grows beyond it mid-build — a new file, a
   data contract, a cross-cutting rule touched — the coder STOPS and flags for a full re-plan
   rather than quietly expanding the micro-plan; emit a `correction` lesson (the triage was wrong).
5. `commands/plan.md` — new step 4.5 **"Spar (attended only)"**, after the plan is written and the
   assumptions listed, before the PR opens: present each *Assumptions & open questions* item via
   AskUserQuestion (one batch — the items are already phrased either/or per step 4, so this is a
   channel change, not new question machinery). Each answered item is rewritten into the plan body
   as a decision with a one-line provenance note and removed from the section; each deferred or
   unanswered item stays and becomes a thread as today. Tool unavailable → triage, steer, and spar
   are all skipped (the headless path, byte-identical to today). Revise mode (B) is unchanged.
6. `commands/plan.md` step 4 — one clarifying line: threads carry only what the spar pass left
   open (deferred items, headless runs).
7. `design-log/` — D-entry: triage–steer–draft–spar as proportional attended planning;
   suggest-don't-assert triage (agent proposes the weight, dev holds a one-tap veto);
   proportionality-never-exemption (the plan artifact and oracle chain shrink but never vanish —
   the skipped-plan drift failure is the counterexample); the mid-build escalation guard;
   authorship rationale for the steer; steer-is-input-not-contract; attended vs headless as two
   resolution channels of one doctrine ("no *silent* decisions" is the invariant).

## Assumptions & open questions
- **Detection of "attended" — RESOLVED (configurable, from review).** The run mode is
  `attended | headless | auto`, precedence **command arg (`/aind:plan <id> headless`) > `planning.mode`
  (settings / `AIND_PLAN_MODE`) > auto-detect** (AskUserQuestion present + not `claude -p`).
  Auto-detection alone was insufficient — a dev may want to force **headless** in an interactive
  session (kick off planning before bed, review the PR next morning). Resolved by
  `scripts/aind-planmode.sh` + the `planning.mode` config key.
- Ceiling: one batch is the default (the empirical base rate is 2–5 assumption items per plan in
  this repo's own runs); allow a second round only when an answer invalidates other items.
- Does Copilot CLI support an AskUserQuestion equivalent? If not: attended co-forming is
  Claude-host-only for now and the D-entry says so (behavior fork by capability, not by design).

## Benefit signal (shifted-cost accounting)
Dev pays at most one triage tap + one steer moment + one spar batch in-session; trivial stories
pay one tap total. The proof, per plan, from the plan artifact itself: fast-track proposals
accepted vs overridden; fast-tracked stories that escalated mid-build (should be rare — a high
rate means the triage bar is too loose); reviewer findings on fast-tracked PRs vs normal (the
quality guard); steers given vs "go"; items drafted → resolved in spar → still threaded → second
rounds. Success looks like trivial stories flowing in two commands and a tap, steered plans
needing visibly less redirection, and most spar items resolving in-session. If devs routinely say
"go" AND defer everything, steer and spar are ceremony — drop them and let the threads carry the
load; if fast-track escalations or reviewer findings climb, tighten the triage criteria.

## Definition of done
- [ ] Attended run: the dev is asked the genuine either/or choices before the plan is written;
      the resulting plan's assumption-thread count drops accordingly; deferred items still thread.
- [ ] Headless run (`claude -p "/aind:plan <id>"`): byte-identical to today.
- [ ] D-entry recorded reconciling co-forming with proceed-on-assumption.

## Files affected
`commands/plan.md` (mode resolution + steps 1.5/4.5 + `AskUserQuestion`), `commands/implement.md`
(micro-plan escalation guard), `scripts/aind-planmode.sh` (new), `scripts/aind-common.sh`
(`planning.mode` → `AIND_PLAN_MODE`), `project-template/aind.settings.sample.json` +
`project-template/CLAUDE.md` (the `planning` key), `design-log/D44`.
