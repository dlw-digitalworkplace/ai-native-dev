# How to write project rules (guide — not a set of files to copy)

> This is a **guide**, not a fixed list of domains. Create a `rules/<area>.md` file **only for
> areas that actually exist in your codebase** — and skip the rest. A small app might have only
> `frontend.md`, `backend.md`, `authentication.md`, and `mini-apps.md`, and that is correct.
> `/aind:onboard` generates these for you from the code; this file shows the shape to follow.

Each rule file is read by the planner and (later) the reviewer, so keep rules **concrete,
observed, and enforceable** — a rule grounded in a real file beats a generic best-practice.
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

## Lens 3 — Functional / domain architecture *(almost always worth one)*
Capture *what the app is and the rules everything must obey* — not the tech stack. Examples:
"the app is composed of mini-apps", "every entity is scoped to a couple of IDs / a tenant", the
core entities and how they relate. Infer from the README, the domain/entity model, routing,
core module names, and recurring scoping patterns. Typical sections:

```markdown
# <Domain concept> rules  (e.g. Mini-apps & ID scoping)
- The core concept (e.g. app-of-mini-apps; each scoped to <ids>):
- Key entities and relationships:
- Invariants every feature must respect (e.g. always scope queries to <ids>):
- Where this shows up in the code:
```

> **Evidence-only:** no test framework → no `testing.md`; no docs system → no `docs.md`.
> Absence of evidence means no file — never emit a stub just because a category is common.
