# WS-00 — Create and seed the aind-knowledge registry repo

_Status: planned. NOT a PR to this repo — a new private repo, the prerequisite for PR-05…PR-10.
Design authority: `docs/skill-registry-design.md` (v2)._

## Context
The registry design (v2) is settled: one private git repo, everything is a skill (two kinds:
`pattern/`, `project/`), no resolver/lockfile/catalog machinery, consumed as a submodule, governed
by PR + named maintainers. This workstream stands the repo up and seeds it with real content so
every downstream PR lands against something that exists.

## Keep it simple (non-goals)
Per the v2 design's Appendix A: no `versions/` dirs, no `catalog.json`, no eval CI, no
`workflow/` kind, no MCP façade, no resolver script. Plain files + PRs.

## Task breakdown
1. **Create the repo** (host decision required — see open questions): `aind-knowledge`, private.
2. **Layout + governance:** `README.md` (what this is, how to consume: submodule for harness
   projects, clone+ask for cold-start consultants), `CODEOWNERS` (**named** owner for
   `skills/pattern/**`; per-project owner for each `skills/project/<name>/`), branch protection
   (PR required, CODEOWNERS review required).
3. **Seed patterns:** generalize the 3 Azelis pattern skills (`mcp-tool-pattern` →
   `pattern/dotnet-mcp-tool`, plus the MSAL-auth and DI-scaffold patterns) — generalizable core
   with clearly-marked specialization slots, `provenance:` to Azelis, `maturity: canonical` only
   after the maintainer's review; frontmatter carries `kind`, `description`, tags.
4. **Seed one dossier:** `skills/project/azelis-salesagents/SKILL.md` — the v2 §5 sections
   (functional / technical / cross-cutting / patterns-in-use / people with as-of date),
   frontmatter tags, `maturity: seed`.
5. **Record the IP basis** (v2 §7): one line per dossier naming the contractual basis, or the
   sanitization rule applied. **Blocks seeding per the design — resolve first.**

## Assumptions & open questions
- **Host: ADO or GitHub?** (v2 §10 leans ADO for proximity; submodule auth ergonomics should
  decide — pick the host the team already authenticates against daily.)
- **Maintainer names** for CODEOWNERS — unassigned is the design's named biggest rot risk.
- People-data policy: include with as-of date (recommended) or omit.

## Definition of done
- [ ] Repo exists with CODEOWNERS + branch protection; a test PR requires the named review.
- [ ] 3 generalized pattern skills + 1 seed dossier merged, provenance + IP basis recorded.
- [ ] A cold clone + "which projects use .NET 10 / who worked on Azelis" answered by an agent
      grepping frontmatter (the acceptance test for the whole consumption model).
