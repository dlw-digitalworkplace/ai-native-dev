# D47 — Documentation restructure — a user-facing multi-page site vs. an internal decision log

- **Area:** Documentation structure (cross-cutting; packaging / docs side of the D1–D15 line; relates to D22, D36, D41, D42, D46)
- **Date:** 2026-07-31
- **Status:** Active

## Decision
**Documentation is split into two explicit surfaces, and each gets its own home.** *Internal
decision/design docs* (for maintainers) live under **`design-log/`**: the `D<N>-<slug>.md` decision
files, `design-log/design-doc.md` (how the flow works), and `design-log/STATUS.md` (fluid status +
the at-a-glance implementation-status matrix). *User-facing usage docs* (for consumers) live in a
**multi-page GitHub Pages site under `docs/`** plus a lean `README.md` landing page.

Concretely: `design-doc.md` and `STATUS.md` moved from the repo root into `design-log/`; the
README's large implementation-status table moved into `design-log/STATUS.md`; the standalone
`GETTING-STARTED.md` was **removed**, its content becoming the site's Getting-started page; and the
stray root `implementation-plan-ado-code-host.md` moved into `files/` (with the other completed
implementation plans).

## The `docs/` site
Three pages sharing one extracted stylesheet (`docs/assets/aind.css`) and a shared top nav
(Home · Getting started · Docs):

- **`index.html` (Home)** — the existing interactive SVG flow diagram, preserved as the "current
  content" (including its per-node "governing decisions" panel), refactored onto the shared CSS/nav
  and refreshed for the pluggable work-item tracker (D46).
- **`getting-started.html`** — prerequisites, install/load, `/aind:onboard` vs `/aind:kickstart`,
  running the flow, and troubleshooting, with a **Claude Code / GitHub Copilot CLI host chooser**
  that toggles the host-specific bits.
- **`docs.html`** — a two-column left-nav reference documenting every command, sub-agent, and skill,
  plus all `aind.settings.json` / `aind.env` options.

`deploy.sh` already serves the whole `<branch>/docs` folder as Pages, so the multi-page site needed
no deploy change (its only assertion is that `index.html` exists).

## Rationale
The README had grown into a mix of a landing page, a repo-layout dump, and a ~20-row
implementation-status matrix; setup lived in a separate markdown file; and the Pages site was a
single diagram with no navigation and no reference/config content. Consumers had to read
maintainer-oriented material to find usage docs, and the design decisions (`D<N>`, `design-log/`)
leaked into user-facing prose. Splitting the surfaces makes each audience's docs findable, lets the
user-facing pages **explain how without citing why**, and keeps the README a thin, stable landing
page. This is purely a docs/packaging change on the config side of the D1–D15 line: the flow, status
model, gates, and PR contract are untouched.

## Consequence for future work
`CLAUDE.md` gains a **Documentation convention**: a user-visible change must update the `docs/` site
in the **same** PR (a command/agent/skill → `docs.html`; a config key → `docs.html` Config + the
`project-template` samples; prerequisites/install/flow → `getting-started.html`; a phase/gate/status
change → the `index.html` node data). Decision IDs stay barred from `README.md` and the `docs/` site
(the Home diagram's existing governing-decisions panel is the single exception), and the README stays
free of status/progress/layout prose — that lives in `design-log/STATUS.md`.
