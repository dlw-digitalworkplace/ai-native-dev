# PR-08 — /publish-dossier: distill the project-knowledge skill to the registry

_Status: planned. Depends on PR-05 (submodule wiring) and WS-00 (registry). Design authority:
`docs/skill-registry-design.md` v2 §5. New D-entry required._

## Context
The dossier (`kind: project-knowledge`) is the capability-map half of the registry: a narrative
functional + technical explanation of one project, with greppable frontmatter tags, published so
consultants can route to projects, patterns, and people. Settled timing rules: **onboarding
produces understanding, never a dossier**; publication is a separate, explicit, human-gated step.
Brownfield MAY be offered it right after `/onboard` (a real codebase was surveyed); greenfield
NEVER at kickstart — earliest after the **first merged PR**. Every first publication is
`maturity: seed`; the dreamer's drift-check (PR-10) matures it.

## Keep it simple (non-goals)
- No auto-publish, ever. The command is human-invoked; the offers (from onboard / complete) are
  one-line suggestions, not actions.
- People data: timestamped best-effort routing hints (as-of date) per the v2 design; no attempt at
  reliable staffing data.
- The dossier PR targets the **registry repo**; this plugin never pushes to a project's registry
  submodule directly.

## Task breakdown
1. **New** `commands/publish-dossier.md` — procedure: (a) preconditions: registry submodule
   configured; refuse on greenfield-shaped projects with no merged story yet (detectable: the
   kickstart DRAFT banner present in `.claude/` AND no `plans/*/plan.md` on the integration
   branch — cheap, honest heuristic; overridable with an explicit flag the human passes);
   (b) distill: from `.claude/CLAUDE.md` + rules + skills + the codebase (the onboard §2 three
   lenses, run in summarize mode), draft `skills/project/<name>/SKILL.md` per v2 §5 sections +
   frontmatter tags (`kind`, `description` tuned for discovery, `stack`, `layers`, `domain`,
   `patterns_in_use`, `cross_cutting`, `people` with as-of date, `maturity: seed`, `updated`);
   (c) present the full draft to the human, iterate, then on approval branch-and-PR it **to the
   registry repo** (clone/worktree of the registry, not the submodule) and print the PR URL;
   (d) record the IP-basis line (v2 §7) — ask the human for it; refuse to open the PR without it.
2. `commands/onboard.md` — final step gains the **offer** (brownfield only): "run
   `/aind:publish-dossier` to publish this project's knowledge skill — optional, human-gated."
3. `commands/complete.md` — after the terminal tag, when the registry submodule is configured and
   no dossier exists yet for this project (check `shared/skills/project/<name>/`), print the
   one-line offer (this is the greenfield-and-later path).
4. **New** `scripts/aind-dossier.sh` — the deterministic mechanics: registry clone/worktree,
   branch, commit, and PR-open **through the `aind-forge.sh` verbs (D36)** rather than a raw
   `gh`/`az repos` call — but driven by a **registry-host selector distinct from the project's
   `AIND_CODE_HOST`** (its own setting, e.g. `AIND_KNOWLEDGE_HOST`, defaulting to the registry URL's
   host): the registry may live on a different host than the project's code (prerequisite decision
   #1). Plus the existence check used by step 3. Signed like every posting script.
5. `design-log/` — D-entry: publish-as-explicit-step, the brownfield/greenfield timing rule and
   its rationale (first-contact understanding is unvalidated; a story is the validation vehicle),
   seed maturity.

## Assumptions & open questions
- Project name/id for `skills/project/<name>`: derive from the repo name, confirm with the human.
- Re-publish (dossier exists): v1 refuses and points at the drift-check (PR-10) — or allows a
  human-driven refresh? Recommend refuse in v1; drift-check is the sanctioned update path.

## Definition of done
- [ ] Brownfield project post-onboard: offer appears; command produces a reviewed dossier PR to
      the registry with all v2 §5 sections + tags + IP basis; `maturity: seed`.
- [ ] Greenfield project pre-first-merge: command refuses with the timing rationale; after the
      first `/complete`, the offer appears and the command works.
- [ ] No registry configured → command refuses cleanly; offers never appear.
- [ ] D-entry recorded.

## Files affected
`commands/publish-dossier.md` (new), `scripts/aind-dossier.sh` (new), `commands/onboard.md`,
`commands/complete.md`, `design-log/`.
