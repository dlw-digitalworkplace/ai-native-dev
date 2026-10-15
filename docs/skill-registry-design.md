# The AIND Knowledge Registry — design v2 (constraint-corrected)

_A central, governed **skill-per-project knowledge repo** shared across every AIND harness instance.
Companion to `azelis-comparison.md` (Goals 3 + 4). Realizes the parked D25 "standards plugin" and the
deck's "skills as software" (slides 33–34)._

Status: **design, not built.** 2026-07-13. **Supersedes v1 (same date).**

**Why a v2:** v1 was derived without the owner's full constraint set (stated outside the session) and
drifted into building a package manager — resolver CLI, lockfile, semver, generated catalog, eval CI.
The trigger insight was even present in v1 ("Claude Code's skill system already *is* the list-then-bind
discovery mechanism") but was used to justify the tooling instead of deleting it. v2 re-derives from
the constraints. Deletions are logged in Appendix A for traceability.

---

## 0. Constraints (the brief — treat as the oracle for every design choice)

1. **Portability** — dual-host today (Claude Code + GitHub Copilot CLI), unknown hosts tomorrow.
   Skills are the durable asset; the agent is the runtime.
2. **Low-to-no friction** — a consultant on any project starts using this with one git command.
3. **No infrastructure to maintain** — no stateful machinery (lockfiles, version resolution, catalog
   generation, protocol servers). Fire-and-forget scripts in the AIND style are acceptable; anything
   that can drift and need babysitting is not. Content curation (reviewing PRs, refreshing dossiers)
   is in scope and cannot be automated away — that is harness work, not infra work.
4. **One place, one mechanism** — no split across a registry product for some kinds and git for others.
5. **Brownfield and greenfield** — onboard and kickstart must both feed it.
6. **Knowledge capture is a primary value stream**, not a by-product.

**Plan A: plain git.** **Plan B: Tessl private registry** — better tooling, but requires accounts/
onboarding for the whole team, which conflicts with tool-independence until investigated. Tripwires
that promote plan B are in §8.

---

## 1. Why — two value streams from one artifact

1. **Compounding capability (reuse).** A proven **pattern skill** ("how we build a .NET MCP tool",
   "MSAL iframe-safe auth in React") authored once on project A becomes discoverable on project B.
   The harness improves across the org, not just within one repo. Models improve for free; the
   pattern library is the moat.
2. **Organizational intelligence (the capability map).** Every project publishes a **dossier** — a
   functional + technical explanation with stack/domain/people tags. Today there is **zero
   cross-pollination** between projects; consultants re-invent solutions and cannot find who solved
   what. The dossier's primary job is **routing to humans and prior art**: find the project, read what
   it does, see who worked on it, go ask. It is a map of where knowledge lives, not a container for
   all of it — tacit knowledge stays in people; the dossier tells you which people.

Honesty note for any pitch built on this: early on, the map covers **harness-adopting projects only**,
not delaware. Coverage grows with adoption; say so.

---

## 2. What lives in it — everything is a skill, two kinds

One artifact type (a skill), one discovery mechanism (frontmatter description), one governance path
(PR). A skill's `kind` tells consumers how to use it:

| Kind | What it is | Consumption | Example id |
|---|---|---|---|
| **pattern** | A reusable, **generalized** code pattern + checklist | Loaded on demand by the host (progressive disclosure) | `pattern/dotnet-mcp-tool` |
| **project-knowledge** | The full functional + technical dossier of one project | Loaded on demand as context | `project/azelis-salesagents` |

**Workflow skills stay per-project** (v1 change): `workflow/build`, `workflow/deploy` are
project-specific by v1's own admission — onboard already stubs them into each project's `.claude/`.
Centralizing them pollutes the shared catalog with entries nobody else can use. Deleted from scope.

**Generalization is mandatory for a pattern skill.** Azelis's `mcp-tool-pattern.md` bakes in
project-specifics (`SourcedResponse<T>`, `userCountry`, `SalesAgentsTelemetry`). A canonical skill
separates the **generalizable core** from **clearly-marked specialization slots** the consuming
project fills. The **agent leads the generalization; a named maintainer approves the PR** (§7).
**Provenance is retained** — every canonical skill records the source project(s), so "how Azelis
actually did it" is one link away.

**One file per skill.** Structured tags (stack, domain, people, provenance, maturity) live in the
`SKILL.md` YAML frontmatter alongside `name`/`description` — no `skill.yaml` sidecar, no mirror files.
Hosts that read frontmatter get discovery natively; everything else is greppable.

---

## 3. Repo structure — flat, no machinery

A dedicated private git repo, `aind-knowledge`:

```
aind-knowledge/
  README.md                                # what this is + how to consume; NOT a generated index
  skills/
    pattern/
      dotnet-mcp-tool/
        SKILL.md                           # frontmatter: kind, description, tags, provenance, maturity
        assets/                            # optional: reference snippets, templates
    project/
      azelis-salesagents/
        SKILL.md                           # THE DOSSIER (§5); frontmatter carries the queryable tags
```

Invariants:
- **No `versions/` directories, no semver.** Skills are prose; a git SHA identifies any state exactly.
  History, diff, blame, and revert are the version model.
- **No `catalog.json`.** Discovery is the host scanning frontmatter (Claude Code does this natively)
  or a grep. At the current and foreseeable scale (tens of skills), a generated index solves nothing.
- **Publishing is a PR reviewed by a named maintainer.** Nothing else gates entry (see §7, §8).

---

## 4. Distribution & discovery — the deleted package manager

The whole consumption model, in three git-native moves:

- **In a harness project:** `aind-knowledge` is a **git submodule** at `.claude/skills/shared/`
  (restoring the previously-settled submodule decision v1 silently dropped). The host's native skill
  scan discovers every shared skill's description; bodies load on demand — progressive disclosure
  already *is* "install only what a task needs." The **pin is the submodule SHA**: one pointer, atomic,
  reproducible, updated explicitly (`git submodule update --remote` + commit) when the project chooses.
- **Cold start (consultant not in any harness project):** `git clone` the repo, open an agent in it,
  ask. That is the entire "talk to the registry" surface — the agent greps frontmatter and reads
  dossiers. Zero new code.
- **Copilot CLI side:** no native frontmatter scan — the project's AIND rules include one line telling
  the agent to scan `.claude/skills/shared/**/SKILL.md` frontmatter when looking for capabilities.
  A grep, not a package manager.

**The closed loop — how the flow consumes what it produces.** Discovery alone isn't consumption; the
flow is wired to the registry at three points:
- **Plan phase** — while co-forming the plan, the plan agent scans skill frontmatter (shared submodule
  + project-own) and **names in the plan which skills the story will use**, making skill choice part of
  the sparred contract instead of an implement-time accident. If the registry holds a relevant newer
  skill than the pinned submodule SHA, the planner **proposes** a pin update — explicit, human-gated.
  **Adoption is the planner's disposition:** when a scanned local skill carries an `overlaps:` flag
  (set by the dreamer, below) and the story touches that area, the planner proposes adopting the
  canonical skill — for this story's new code only; migrating existing code that followed the old
  local skill is a separate backlog item, never silent scope creep in the current plan. Adopt-on-use
  keeps every adoption inside a story's full validation chain (plan contract → build → cold review →
  dev review) instead of merging on faith.
- **Implement phase** — loads the bodies of exactly the skills the plan named (progressive disclosure
  does this natively); the cold review then checks **conformance to the named pattern skills** as a
  third oracle alongside plan and brief.
- **Dream phase** — closes the loop back to the registry via the diff model (§6.2).

Deleted relative to v1 (see Appendix A): the `aind-skill.sh` resolver and all its verbs, the
`aind.skills.lock` lockfile, per-skill version pinning, `catalog.json` + generator, the eval CI
runner, and the MCP façade question (moot — nothing to front).

What this genuinely gives up, and why that's acceptable at current scale:
- **Structured tag queries** → frontmatter grep. Fine at 5–10 projects; a §8 tripwire at ~25.
- **Per-skill pinning** → repo-level pinning. At this scale that is *more* reproducible, not less.
- **Eval-gated publishing** → named-maintainer review. Eval-gating was deferred in v1 anyway, and
  "what is a good eval for a prose skill" is an unsolved problem (the harness's own circular-test
  lesson, one level up). Revisit under plan B.

---

## 5. The project-knowledge skill (the dossier)

**Onboarding does not produce a dossier — it produces understanding.** Onboard's job (brownfield) is
inward: the harness gets to know a legacy project and writes what it learns into the project's local
`.claude/`. Kickstart (greenfield) elicits the same understanding from conversation. **Publishing the
dossier is a separate, explicit, human-gated step** that distills that local understanding into
`project/<name>` and opens a PR. Timing:
- **Brownfield:** MAY be offered right after onboard — a real codebase was surveyed — still `seed`.
- **Greenfield:** NEVER at kickstart; there is nothing to describe yet. Earliest trigger is the
  **first merged PR**; later in the project is fine.
Sections:

- **Functional summary** — what the product is and does: domain, users, core entities and invariants,
  main capabilities.
- **Technical summary** — architecture layers and how they fit, runtime topology, key decisions and
  why, external integrations, build/deploy shape.
- **Cross-cutting concerns** — auth, security, observability, data boundaries; any non-standard rule a
  planner must respect (e.g. Azelis's `userCountry` data-silo rule).
- **Patterns & skills in use** — links to the `pattern/*` skills used or contributed.
- **People & status** — leads/contributors **with an as-of date**, harness version, flow maturity.

Frontmatter carries the greppable projection: `kind`, `description` (tuned for discovery), `stack`,
`layers`, `domain`, `patterns_in_use`, `cross_cutting`, `people`, `maturity`, `updated`.

**Seed rule (applies to both brown- and greenfield):** every first-published dossier is marked
`maturity: seed`. A brownfield seed is richer (real code was surveyed) but first-contact understanding
is unvalidated either way — the harness hasn't tested it against actual work yet. The dreamer's
drift-check (§6) is REQUIRED to mature seeds: it corrects what onboarding misread and grows what
kickstart couldn't know, promoting `seed` → `validated` once the dossier has survived real stories.
Without it, seed dossiers are permanent first impressions.

**People-data honesty:** people fields rot on organizational time (roll-offs, departures), which no
code-driven refresh can see. They are timestamped best-effort routing hints — a stale name is still
usually one hop from the right person. If people data must be reliable, it needs a non-harness refresh
signal; do not pretend the dreamer solves this.

---

## 6. The capture pipeline — where the complexity budget actually goes

v1 spent its budget on distribution (trivial at this scale) and underdesigned capture (the actual
bottleneck). Reversed:

1. **Onboarder upgrades** — (a) brownfield only: after onboard completes, MAY **offer** the
   dossier-publish step (`maturity: seed`), human-gated. Kickstart never offers it; for greenfield the
   offer comes from the completion phase after the **first merged PR** (or later); (b) flag candidate
   **pattern skills** from recurring code shapes as `maturity: draft` — canonicalization
   (generalization + maintainer approval) happens later, not at first contact.
2. **Dreamer promotion = a registry diff, not creation from scratch.** The dreamer compares the
   project's local skills (and lesson-validated patterns) against what `aind-knowledge` already holds
   and disposes each finding into one of two registry-bound outcomes: **promote** — the project skill
   fills a registry gap → generalize it (specifics → marked slots, provenance kept) and open a PR;
   **improve** — it overlaps an existing canonical skill and the local version learned something →
   propose a delta to the canonical skill instead of a duplicate. Agent leads, maintainer approves.
   **The dreamer detects but never proposes adoption:** when the diff finds a local skill duplicating
   a canonical one, it flags it (`overlaps: pattern/<id>` in the local skill's frontmatter, via its
   normal local-`.claude` PR) and stops — disposition belongs to the planner at the next story that
   touches the area (§4 closed loop), where the swap gets validated by a real story rather than merged
   on faith. Detection lives where the visibility is (dreamer: whole project, cold); adoption lives
   where the context and validation are (planner: in-story, sparred). Diff-first prevents the
   fork/duplicate explosion a write-only promotion loop would create, and realizes the parked D25 path.
3. **Dreamer drift-check (new)** — during dreaming, re-run the onboard lenses **in diff mode** against
   the current dossier: new integrations, stack bumps, changed cross-cutting rules. Drift found → PR
   updating the dossier. This is the anti-rot mechanism, and it is out-of-band curation with human
   approval — the same shape as dreaming itself. Known limit: it only runs where the harness runs;
   a dormant project's dossier freezes as a valid snapshot (acceptable — its architecture froze too),
   except for people data (§5).
4. **Meta-lessons** — lessons about the harness itself route to a harness-improvement backlog in
   `aind-knowledge`, so the plugin learns, not just projects.

---

## 7. Governance & trust

- **Named maintainers or it rots.** A CODEOWNERS file in `aind-knowledge`: at least one named owner
  for `skills/pattern/**` and one per `skills/project/<name>/`. "Human review" without named humans
  is drive-by LGTM. This is the single non-negotiable governance element.
- **Publish = PR + maintainer approval + generalization done (patterns) + provenance recorded.**
- **Curated, private, first-party only.** No third-party skills — that is a §8 tripwire, because
  third-party content is where release-age/security gates (a registry product's job) stop being
  optional.
- **Client-IP basis must be recorded.** Pattern skills are consultant-distilled know-how —
  defensible. Dossiers *describe client systems* (architecture, integrations, security mechanisms like
  the `userCountry` rule) in an org-wide repo. Record the contractual basis per dossier, or define a
  sanitization line for the dossier kind. One retroactive client objection poisons the pattern; decide
  this before seeding, not after.

---

## 8. Plan B (Tessl) — tripwires that promote it

Keep every skill in the standard portable format so migration is a publish script, not a
restructuring. Promote plan B when any of these fires:

1. **Scale** — the catalog outgrows whole-repo-submodule ergonomics or frontmatter-grep discovery
   (rough marker: ~25+ projects / hundreds of skills).
2. **Third-party skills wanted** — security scanning, release-age gates, and approval policies become
   necessary, and building them violates constraint 3.
3. **Non-technical consumers** — managers/pre-sales need seatless catalog access outside git.
4. **Eval-gating becomes worth its cost** — a mature catalog worth protecting, and the prose-eval
   problem has a workable answer (Tessl ships the tooling).

Until one fires, plain git is not a compromise — at the current size it is the right-sized design.
The Tessl account/pricing/team-onboarding investigation stays worth doing in the background so plan B
is executable when a tripwire fires.

---

## 9. Phased build plan

1. **Repo + seed** — create `aind-knowledge` (host: §10), CODEOWNERS, README. Seed with (a) the
   `project/azelis-salesagents` dossier authored from the real codebase, and (b) Azelis's 3 pattern
   skills generalized into the first canonical `pattern/*` entries with provenance. Proves both value
   streams on real content; no tooling required to be useful on day one.
2. **Submodule wiring** — onboard/kickstart add `aind-knowledge` as a submodule at
   `.claude/skills/shared/` and add the Copilot-side scan rule. (One-time; per-project cost is one
   git command.)
3. **Onboarder upgrades** — dossier authoring + pattern-skill drafting (§6.1).
4. **Dreamer extensions** — promotion/generalization PRs + the drift-check + meta-lesson routing
   (§6.2–6.4).
5. **(Background) Plan-B investigation** — Tessl accounts, private-registry terms, team onboarding
   cost; parked until a §8 tripwire.

---

## 10. Open decisions

- **Registry repo host** — Azure DevOps (where projects and work items live) or GitHub (where AIND
  ships). Leaning ADO for proximity; note submodule auth ergonomics differ per host — pick whichever
  the team already authenticates against daily.
- **Client-IP basis for dossiers** (§7) — contractual green light per client, or a sanitization line
  for the dossier kind. Blocks seeding.
- **People-data policy** — include (routing value, timestamped best-effort) or omit (privacy-simpler).
  Leaning include-with-as-of-date; needs the same review as the IP question.
- **Maintainer names** — who owns `pattern/**`? Unassigned = the design's biggest rot risk.

---

## Appendix A — decision log: what v2 deleted from v1, and why

| v1 element | v2 disposition | Reason |
|---|---|---|
| `aind-skill.sh` resolver (search/install/read/list/query) | **Deleted** | Progressive disclosure already provides list-then-load; getting folders onto disk is git's job. Custom stateful tooling violates constraint 3. |
| `aind.skills.lock` per-skill pinning | **Deleted** → submodule SHA | One atomic pin, no lockfile drift, restores the previously-settled submodule decision. |
| `versions/x.y.z/` + semver | **Deleted** → git SHAs | Prose has no API surface; semver is package-registry cosplay. |
| `catalog.json` + generator | **Deleted** → frontmatter scan/grep | Generated index solves nothing at tens of skills; generation is maintenance. |
| Eval CI gating | **Deferred to plan B** | Was deferred in v1 anyway; prose-skill evals are an unsolved oracle problem; Tessl ships this if ever needed. |
| `workflow/*` kind in central repo | **Removed from scope** | Project-specific by v1's own admission; lives per-project where onboard already puts it. |
| MCP façade (deferred in v1) | **Moot** | Nothing to front; a non-git consumer is a §8 tripwire, answered by plan B, not by building a server. |
| "Talk to it" query CLI | **Replaced** → clone + ask the agent | The conversational surface is the agent over greppable files; no verb layer needed. |

What v2 kept from v1 unchanged: the two value streams, everything-is-a-skill, mandatory agent-led
generalization with provenance, the dossier structure, the dreamer promotion loop, meta-lessons
routing, private-first-party-only curation.
