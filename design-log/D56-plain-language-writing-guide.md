# D56 — Plain-language writing guide + per-project `writing` config

- **Area:** Config / packaging — every text-producing command and agent; new `writing/guide.md`,
  `scripts/aind-writing.sh`, `project-template/writing-guide.md`; the settings loader, preflight,
  onboard/kickstart, the reviewer Bash hook, and the docs site
- **Date:** 2026-09-25
- **Status:** Active — offline-validated; live-validation pending

## Decision
**Every AIND command and agent that writes text a human reads loads one plugin-owned writing guide
at the start of its run and follows it. Output is always English. A project sets the reading level
with `writing.level` in `aind.settings.json` (`plain` | `standard` | `technical`) and may add its
own rules in an optional `.claude/writing-guide.md`, which wins on conflict.**

- **The guide** (`writing/guide.md`) is runtime plugin data, not a copied seed, so plugin upgrades
  improve it for every project. Its rules are checkable, not aspirational: lead with the ask
  (`What I need from you:` + numbered yes/no questions), one idea per sentence, ≤3-sentence
  paragraphs, common words, jargon explained once, no hedging, `Found:` vs `Assumed:`. Console output
  ends each run with a fixed **Done / Needs you / Next** block. A level table sets sentence length
  and jargon tolerance. A *Technical documents* section makes plans and PR text follow the same
  rules (exact names in backticks, plain sentences around them), and a *Language* rule fixes English.
- **The resolver** (`aind-writing.sh`) prints the effective guide: the active level, the default
  guide, then the project rules. It is best-effort and always exits 0 — a bad level degrades
  to `standard`, a missing guide to a built-in fallback — so it can never block a phase.
- **Wiring** is one "Writing style" step per text-producing command/agent (intake, plan,
  approve-plan, implement, complete, dream, new-item, research, onboard, kickstart, reviewer,
  dreamer), using the standard portable resolver preamble so the existing single allow-rule covers
  it. The reviewer's read-only Bash hook now also allows `aind-writing.sh` (it only prints text).
- **Project override lives at `.claude/writing-guide.md`, not in `.claude/rules/`.** The reviewer
  reads every `rules/*.md` as a code rule and the planner cites rules per task; a prose-style rule
  there would leak into code review. Placed beside the intake rubric (a data file) instead. It is
  under `.claude/`, so the dreamer can already propose edits to it — no scope change needed.

## Rationale
Users reported the flow's text was hard to review: long sentences, heavy words, the ask buried.
Nothing in the shipped prompts said how to write for a human, so every agent used its default dense
style. A single guide fixes the cause at the source for all output surfaces (work-item comments, PR
bodies/threads, plan files, console), including console text, which no script sees.

This is a **config-layer** change: the flow, gates, status model and PR contract are untouched.

**English only — an output-language setting was built and removed.** The first version had a
`writing.language` key. A live run with `language: nl` produced Dutch console text but an English,
technical plan, and the user decided against multilingual output altogether: one language keeps
plans, PRs, lessons and review threads consistent for every reader and agent. The guide now says
"always write in English", whatever language the story or the human uses.

**The plan needed a point-of-use fix.** The same live run showed the planner ignoring the guide for
`plan.md`: `/aind:plan` step 3 said "write for a coding agent", which the model read as licence for
dense technical prose, and the guide was loaded ~100 lines earlier. Step 3 now names **two readers**
(a human approves it first; a coder acts on it later) and points back at the guide; the revise and
local-flow steps repeat a one-line reminder.

**Rejected / deferred.** *Hooks that check or rewrite text* — per-host duplication (Claude and
Copilot hook formats differ), and a block-on-score gate causes retry loops. *A cold "editor"
subagent* — cost and an extra hop, and cold roles are checks, not authors. *Style checks in the code
reviewer* — mixes prose into the code gate. *A warn-only length/ask lint in the comment/PR scripts* —
deferred (the scripts are the natural chokepoint if the guide alone proves insufficient; it would not
cover console text either way).

## Status / validation
Offline-validated: `bash -n` on the new/edited scripts; resolver fixtures — no settings →
`standard`; `" PLAIN "` → `plain`; `foo` → `standard` + WARN; a CRLF
`.claude/writing-guide.md` found by walk-up from a subdirectory and appended under "Project rules";
missing default guide → fallback + WARN, exit 0. Reviewer hook: `aind-writing.sh` and
`aind-review-pr.sh` allowed, `git push` still blocked.

**Live (partial):** one `/aind:plan` run with `level: plain` — the console followed the guide; the
plan did not, which led to the step-3 fix above. **Not verified:** a re-run of `/aind:plan` after
that fix, `/aind:intake` / `/aind:implement` output, and Copilot CLI.
