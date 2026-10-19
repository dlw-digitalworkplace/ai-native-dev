# D58 — STE100-style procedural text + project glossary (amends D56)

- **Area:** Config / packaging — `writing/guide.md`, the `aind-writing.sh` fallback, the
  `project-template/writing-guide.md` starter, onboard/kickstart, the planner's step 3, the docs site
- **Date:** 2026-10-19
- **Status:** Active — offline-validated; live-tested by the user on a real story (2026-10-19)

## Decision
**The writing guide adopts the parts of ASD-STE100 (Simplified Technical English) that D56 lacked,
in two layers. It applies the strict form only to procedural text. Each project's glossary takes
the role of STE's controlled dictionary.**

- **Core rules for all text** (rules 10–12): active voice and present tense, one term per concept
  (use the project Glossary's *Use* column), no semicolons.
- **A new *Procedural text* section** for the plan's Task breakdown and Definition of done, test and
  verify steps, the "how to fix" part of review findings, and the console `Next:` line. Write it
  "about 80% of the way to ASD-STE100": imperative verb first, one instruction per step, ≤20 words
  (or the level's limit if shorter), condition first, articles kept, no noun-as-verb. Backticked
  names stay exact. Rationale, Considerations, risks and trade-offs are **excluded**. They keep the
  core rules, because STE's flat style removes the hedging those sections need.
- **Glossary seeding.** `/aind:onboard` proposes 3–10 domain terms plus the synonyms it found in the
  codebase. `/aind:kickstart` proposes them from the domain lens, with undecided terms as `TODO`
  rows. Each one creates `.claude/writing-guide.md` **only if the human accepts** (before this
  change, both told the human about the file but did not create it). The dreamer already has the
  file in scope.
- **Point of use.** `/aind:plan` step 3 names the *Procedural text* rules next to the *Technical
  documents* rules. This follows D56's finding that the planner ignores a guide loaded far earlier
  unless the step names it.

## Rationale
Andrej Karpathy reported that LLM output reads better when the model is asked for ASD-STE100, at
about 80% strictness. AIND is an oversight flow: humans read agent text at every gate. So the idea
fits. D56 already covered most of STE (short sentences, common words, no hedging, facts vs guesses).
What it lacked were the rules that make **steps** unambiguous, and consistent terminology. Naming
the standard in the guide also cheaply invokes a rule set the model already knows.

**Rejected.** *A `writing.style: ste` toggle or an `ste` level.* STE runs on a different axis from
audience, so a level would mix two things. A toggle adds config for a benefit no one has measured,
on top of a D56 guide that is only partly live-validated. *STE for all text.* It flattens trade-off
and risk discussion. *The 900-word STE dictionary.* It is licensed, and models do not reliably know
it. The project glossary is the useful, local form of that idea. *Hooks or a lint.* The same reasons
as in D56: per-host duplication and retry loops. *Prose checks in the code reviewer.* These would
mix prose into the code gate.

This is a **config-layer** change. The flow, gates, status model and PR contract are untouched.

## Status / validation
Offline: `bash -n` on `aind-writing.sh`. The resolver prints the new rules and section. The fallback
path carries the new lines and exits 0. The no-decision-ID guard grep over the shipped dirs is clean.
**Live:** the user tested it on a real story and reported that the output looked good. The bar was:
Task breakdown and DoD steps are verb-first, one instruction each and ≤20 words. Considerations
still carries the trade-offs. Terms stay consistent. The glossary proposal in `/aind:onboard` was
not reported on separately.
