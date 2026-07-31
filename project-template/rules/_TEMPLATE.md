# How to write project rules (guide — not a set of files to copy)

> This is a **guide**, not a fixed list of domains. Create a `rules/<area>.md` file **only for
> areas that actually exist in your codebase** — and skip the rest. A small app might have only
> `frontend.md`, `backend.md`, `authentication.md`, and `mini-apps.md`, and that is correct.
> `/aind:onboard` generates these for you from the code; this file shows the shape to follow.

Each rule file is read by the planner and (later) the reviewer, so keep rules **concrete, grounded,
and enforceable** — a rule tied to a real file beats a generic best-practice. **Write them as
directives, not observations:** "New abstractions **must** live in a `Contracts/` folder (see
`…/Contracts/IGraphDataService.cs`)" — not "some code observes interfaces in Contracts folders." The
draft as a whole is a suggestion you review and prune; each rule you keep is a requirement the flow
enforces, so its text should read like one.

**Capture coding conventions, not just the repo map.** Structural rules ("keep code in the right
layer") are table stakes; the valuable rules are the implementation patterns a contributor must
match. Write a rule for each pattern that genuinely recurs (evidence-only — skip what isn't there).
These prompts lean toward a service/web app — **translate them to whatever your project actually is
(a library, a CLI, a script collection, a data pipeline, IaC…) and go beyond them:**
logging/observability (or a script's output convention), error/exception handling, naming,
folder/module organisation, interface/abstraction or public-API placement, composition/wiring
(DI, a registry, an entry point), imports/references, I/O & data patterns, state management
(front-end), the public contract of a unit (params, return shapes, exit codes, back-compat),
validation, config/secrets access, and test patterns. For anything already enforced by tooling
(`.editorconfig`, eslint, `ruff`, `PSScriptAnalyzer`, …), point to the tool rather than restating it.

**Flag conflicting conventions as a decision.** When the repo has competing patterns for the same
concern, don't silently pick one. Record it as a decision the human resolves (onboarding asks during
its run); keep the chosen rule as the directive and the alternatives as a short note:

```markdown
> **Convention decision (resolved <date> / to resolve):** <the competing patterns seen, with a file
> for each>. Chosen: <the rule now in force above>. Alternatives considered: <option B>, <option C>.
```

Look through three lenses; most repos need files from more than one:

## Lens 1 — Technical layers / components *(only those present)*
One file per layer the repo actually has. Examples: `frontend.md`, `backend.md`,
`web-jobs.md`, `infrastructure.md`, `mobile.md`, `ci-cd.md`. Typical sections:

```markdown
# <Layer> rules
- Language / framework / version:
- Structure & key directories:
- Conventions (naming, patterns, state, styling, …):
- What "done" looks like for a change here:
```

## Lens 2 — Cross-cutting concerns *(only those with a notable approach)*
Give a concern its own file when the project does it in a specific or unusual way a planner
must respect — e.g. a custom **pin-code auth** scheme → `authentication.md`. Candidates:
authentication/authorization, security, logging/observability, error handling, config/secrets,
i18n. Typical sections:

```markdown
# <Concern> rules  (e.g. Authentication)
- How it works here (the specific mechanism, e.g. pin-code auth):
- Where it lives (entry points, middleware, helpers):
- Invariants every change must uphold:
- Common mistakes to avoid:
```

## Lens 3 — Functional / domain architecture *(the most commonly missed — almost always worth one)*
Capture *what the app is and the rules everything must obey* — not the tech stack. This is the lens
that gets skipped when you stop at "backend/frontend" rules, and it's usually the most valuable.
Examples: "connectors extend a base model and plug into a shared orchestrator", "the app is composed
of mini-apps", "every entity is scoped to a couple of IDs / a tenant". Infer from the product docs,
the domain/entity model, central abstractions, dispatchers/registries, base/marker types, and
recurring scoping patterns. Typical sections:

```markdown
# <Domain concept> rules  (e.g. Connectors & orchestration)
- The core domain abstraction & its extension/variability model (what the code is organised around):
- Key entities and relationships:
- Invariants every feature must respect (e.g. always scope queries to <ids>):
- How to add a new unit of the domain (the extension recipe — a new connector / mini-app / plugin):
- Where this shows up in the code:
```

> **If you wrote only technical-layer + cross-cutting rules, stop and re-check the domain** — you
> probably missed the functional lens. A repo with genuinely no domain model (e.g. a pure utility
> library) is the rare exception, not the norm.

> **Evidence-only:** no test framework → no `testing.md`; no docs system → no `docs.md`.
> Absence of evidence means no file — never emit a stub just because a category is common.
