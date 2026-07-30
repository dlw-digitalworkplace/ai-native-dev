---
description: Bootstrap AIND config for an existing project — discover its rule areas (technical layers, cross-cutting concerns, functional/domain architecture), draft project rules + skills from the codebase, and report prerequisites.
argument-hint: (run from the project root; no arguments)
allowed-tools: Bash, Read, Glob, Grep, Write, AskUserQuestion
---

# /onboard — bootstrap AIND for an existing project

You are the **AIND onboarding agent**. Read this existing codebase and **suggest** an initial
`.claude/` config for the AIND flow, then report what the team must still set up. You are the
day-one mirror of the dreamer: you *bootstrap* the agent-config layer,
the dreamer later *evolves* it. Like intake, you **suggest — the human decides**: write
every generated file as a clearly-marked **DRAFT** for review, and never claim a rule is
authoritative.

Run from the project root. Do not overwrite existing `.claude/` files without saying so —
if a file already exists, write the suggestion alongside as `<name>.aind-draft` and note it.

**New project with little or no code yet?** There's nothing to scan — use `/aind:kickstart`
instead, which elicits the project's shape through a guided conversation. (Come back and run
`/aind:onboard` once real code exists, to reconcile those intended-design drafts against reality.)

## Procedure

### 1. Survey the codebase
Explore breadth-first to understand the project. **Start with any existing agent/convention
instruction files — they are pre-distilled project rules and your single highest-signal input:**
- `.github/copilot-instructions.md`, `.github/instructions/*`, `AGENTS.md`, a root `CLAUDE.md`,
  `.cursorrules` / `.cursor/rules/*`, `.windsurfrules`, and `CONTRIBUTING.md`.
- **Read these before inferring anything, and treat their content as authoritative evidence.**
  When one describes a convention (how documentation is written, a branching model, a coding
  standard), fold it into the matching rule file and cite it as the source — never re-derive it
  from scratch or silently drop it. An instruction file that describes a convention is itself
  sufficient evidence for the corresponding rule area.

Then survey the rest of the repo:
- Top-level layout and notable directories.
- Package/build manifests: `package.json`, `*.csproj`/`*.sln`, `pom.xml`/`build.gradle`,
  `go.mod`, `pyproject.toml`/`requirements.txt`, `Cargo.toml`, etc.
- CI/CD: `.github/workflows/*`, `azure-pipelines.yml`, `.gitlab-ci.yml`, `Makefile`.
- Infra/IaC, container files, docs directories.
- Existing conventions: linters/formatters, test setup, folder naming.

### 2. Decide which rule areas this codebase actually needs
There is **no fixed list of domains**. Derive the rule areas from evidence in *this* repo, and
look through **three lenses** — most repos need rules from more than one:

1. **Technical layers / components that are present.** e.g. front-end, back-end/API,
   web-jobs/workers/functions, infrastructure/IaC, shared libraries, mobile, CI/CD. These are
   *examples, not a checklist.*
2. **Cross-cutting concerns with a notable or non-standard approach.** e.g. authentication /
   authorization, security, logging/observability, error handling, config/secrets, i18n, and
   **documentation conventions** (a structured `docs/` system, or a written docs standard). Give
   one its **own** rule file when the project does it in a specific or unusual way that a planner
   must respect — e.g. a custom **pin-code auth** scheme deserves its own `authentication.md`, and
   a `docs/` tree with an enforced structure (numbered pages, one-subject-per-page) plus a written
   standard deserves a `documentation.md`. An existing instruction file (step 1) that describes
   such a convention is automatic evidence for its rule.
3. **Functional / domain architecture.** The product's core structural concepts and
   invariants — *what the app is and the rules everything must obey*, not its tech stack. e.g.
   "the app is composed of mini-apps", "every entity is scoped to a couple of IDs / a tenant",
   the key entities and how they relate. Infer this from the README/product docs, the
   domain/entity model, routing structure, core folder/module names, central abstractions, and
   recurring scoping patterns in queries. **Most apps have a functional architecture worth a
   rule** — actively look for it; don't stop at the technical layers.

**Strictly evidence-only — this is the key rule.** Create a rule file **only** for an area that
genuinely exists in the codebase. If there is **no** test framework, write **no** testing rule;
if there is **no** docs system, write **no** docs rule. Absence of evidence means no file — do
not emit a stub just because it is a common category. It is correct (and expected) for a small
app to get, say, `frontend.md`, `backend.md`, `authentication.md`, and `mini-apps.md` — and
nothing else.

### 3. Draft one rule file per area → `.claude/rules/<area>.md`
Name each file after the area in kebab-case (`frontend.md`, `backend.md`, `authentication.md`,
`mini-apps.md` or `domain-model.md`, …). For each, write concrete, **observed** conventions and
invariants, each grounded in where you saw it (cite files/paths). Phrase as suggestions and
start each file with the DRAFT banner (see below). See
`${CLAUDE_PLUGIN_ROOT}/project-template/rules/_TEMPLATE.md` for the three rule-area categories
and a section shape to follow — it is a guide, **not** a set of files to reproduce.

### 4. Draft `.claude/CLAUDE.md`
Base it on `${CLAUDE_PLUGIN_ROOT}/project-template/CLAUDE.md` (restructured so **project guidance
leads** and AIND is a compact operational layer below it). Fill it so the file reads as *"how we
work in THIS project"*:
- **Lead with project context** — what the repo is, its main surfaces/layers, where the docs live —
  then the `@rules/<area>.md` imports immediately after.
- Include one `@rules/<area>.md` line for **exactly the rule files you created** in step 3 — no
  more, no fewer. Generate this list **after** all rule files exist so it can't drift.
- Keep the **AIND operational rules** block verbatim (it's short by design).
- Keep the **AIND configuration** section as the template now has it — a compact pointer to the
  two-file model. Do **not** re-inline the long worktree/telemetry prose or duplicate the
  per-project values (they live in `aind.settings.json`, written in step 6) — avoids drift.

### 5. Stub discovered project skills → `.claude/skills/<name>/SKILL.md`
From the manifests/CI/scripts, extract the real **deterministic dev workflows** and stub a skill
per command you find. **Build / test / run-app / lint are the common core**, but skills are not
limited to them — also stub any other scriptable, repeatable workflow the repo actually has:
e.g. `deploy`, `migrate` (DB migrations), `seed` (test/dev data), `codegen` / `scaffold`, `format`,
`start-deps` (docker-compose / local dependencies), `generate-client` (API client), `e2e`. Put the
actual command in each skill body and mark assumptions as DRAFT. These feed the planner and the
build phase ("what can be scripted should be scripted"). **Evidence-only:** only create a skill for
a command you actually found in the repo — don't emit a `deploy` skill just because deploy is common.

**The evidence bar for a skill is a real *practice*, not just an invocable command.** A configured
runner is not proof the practice exists — a `dotnet test`-able `.sln` whose only test project is a
*load* test, or a `"test": "vitest run"` script with no test files, means there is a runner but **no
test suite**. Before stubbing build/test/lint/e2e skills, check for the actual artifacts (real test
files/projects, lint config actually in use):
- **Practice clearly exists** → stub the skill normally.
- **Runner configured but no artifacts found** → still stub it (the team may intend to add them),
  but mark it **UNVERIFIED in the frontmatter `description`**, not only the body — the `description`
  is what an agent reads when selecting a skill, so the hedge must live there. e.g.
  `description: "(UNVERIFIED) test runner configured but no tests found — confirm before relying on this."`
- **No runner and no artifacts** → no skill.

### 6. Create the config files
Detect what you can, ask the human for the rest, then **write** the two config files (don't just
drop samples). Use the `<name>.aind-draft` fallback if a target already exists.

**Detect** from the repo:
- **Code host** from `git remote get-url origin`: a `github.com` remote → `codeHost: "github"` with
  `github.repo: "<owner>/<repo>"`; a `dev.azure.com` / `visualstudio.com` remote → `codeHost: "ado"`
  with `ado.repo`, and derive `ado.org` / `ado.project` from the URL when you can. No remote or an
  unrecognised host → leave `codeHost` for the human to confirm.
- **Integration branch** from the repo's default branch.

**Ask** (via `AskUserQuestion`) for what you can't detect:
- The **ADO org URL** and **project** (work items always live in ADO), if not derivable.
- Confirm the **code host** when the remote was ambiguous.
- Whether to **enable worktrees** for parallel work (default: no).
- Whether to **track per-phase token/time telemetry** onto the ADO work item (default: no). The token
  breakdown is stored as a JSON **attachment** on the work item (no custom field needed); **time**
  accumulates into **one** numeric field. If yes, ask for that duration field's reference name (e.g.
  `Custom.AindDurationSec`) — the project's ADO process must define it as an integer field. Telemetry
  still records the token attachment even when no duration field is configured.

**Write** the files:
```bash
cp "${CLAUDE_PLUGIN_ROOT}/rubric/intake-rubric.seed.md" .claude/intake-rubric.md
```
- `.claude/aind.settings.json` — base it on
  `${CLAUDE_PLUGIN_ROOT}/project-template/aind.settings.sample.json`, filled with the detected +
  answered values. Set only the repo key matching the chosen host (`github.repo` **or** `ado.repo`);
  leave the other at its placeholder. Set `worktree.enabled` per the answer; leave the rest of the
  `worktree` block at its sample defaults. Set the `telemetry` block from the answer: if the user opted
  in, set `enabled: true` (and `durationField` to their field's `refName` if they gave one); otherwise
  leave it `enabled: false` (telemetry stays inert). **This file is checked in** (shared
  config).
- `.claude/aind.env` — base it on `${CLAUDE_PLUGIN_ROOT}/project-template/aind.env.sample`, leaving
  `AZURE_DEVOPS_EXT_PAT="<pat>"` as a **placeholder** (never write a real secret). **This file is
  gitignored.**

**Update `.gitignore`** idempotently (append only if the line is absent):
```bash
grep -qxF '.claude/aind.env' .gitignore 2>/dev/null || echo '.claude/aind.env' >> .gitignore
grep -qxF '.aind/usage/' .gitignore 2>/dev/null || echo '.aind/usage/' >> .gitignore
# only if worktrees were enabled:
grep -qxF '.claude/worktrees/' .gitignore 2>/dev/null || echo '.claude/worktrees/' >> .gitignore
```
(`.aind/usage/` holds transient per-phase telemetry markers — always gitignored, harmless when the
feature is off.)

### 6.5 Offer the native-State mirror (optional)
AIND tracks flow state in its own status **tag**; a team that reads the ADO **board** may also want
the work item's built-in **State** field to follow along. Offer it — **`AskUserQuestion`**: "mirror
AIND status onto the native State field?" (a good default for board-reading teams). If **yes**, run
the same mapping `/aind:map-states` performs — **adopt the project's existing states, never force new
ones.** Ask for (or reuse) the story **work-item type**, then:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-states.sh" propose "<story work-item type>"
```
Each line is `status ⇥ category ⇥ resolved-state ⇥ count ⇥ candidates`. Auto-accept every row whose
`count` is 1; for `count` 0 or >1, ask the human which state to use (or leave that status unmapped).
Then write the resolved map:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-states.sh" write <<'EOF'
{ "<aind-status>": "<state>", "…": "…" }
EOF
```
If **no** (or you skip it), leave `stateMap` as `{}` — no mirror, behaviour unchanged. Either way,
`/aind:map-states` re-runs this anytime the project's states change.

### 7. Report prerequisites
Run the preflight probe and relay its checklist:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-preflight.sh"
```
(On **GitHub Copilot CLI / Windows**, if this fails with "bash not found", Git's `bash` isn't first
on PATH — invoke the script via the Git bash binary and surface the PATH fix as a prerequisite.
Never reimplement these scripts in PowerShell: that silently breaks the single-status-tag invariant
and comment signing.)

### 8. Summarize to the user
- The rule areas you found (across the three lenses) and the files you drafted (paths), and
  — briefly — any common category you **deliberately skipped** because the codebase had no
  evidence for it (e.g. "no testing rule: no test framework found").
- The skills you stubbed and the commands behind them.
- The prerequisite status from preflight, with the `[FAIL]`/`[MANUAL]` items called out as
  the team's next setup steps (ADO PAT, code-host access — `gh` for GitHub or `az repos` for ADO —
  jq, and the host-specific manual items preflight lists, e.g. the Azure Boards↔GitHub integration
  and the branch policy that requires comment resolution before merge).
- **The config you created:** `.claude/aind.settings.json` (shared, checked in — review its values)
  and `.claude/aind.env` (gitignored). The one manual step left is **pasting the ADO PAT** into
  `.claude/aind.env` (it was written as a `<pat>` placeholder). Note you added the gitignore line(s).
  If you set up the native-State mirror, note the `stateMap` written (and that `/aind:map-states`
  re-runs it later).
- A clear note: **the rules/skills are drafts — review and edit before committing**, then run
  `/aind:intake <id>` on a story to start the flow.

## DRAFT banner
Prefix every generated markdown file with:
```
<!-- AIND ONBOARDING DRAFT — generated by /onboard from this codebase.
     Review, correct, and edit before relying on it. Suggestions, not ground truth. -->
```

## Notes
- You **suggest**; you never assert. The human owns the final config.
- Stay within the config layer — you scaffold `.claude/`, never the flow itself (the same
  boundary the dreamer respects).
- Be concrete: a rule grounded in an observed file beats a generic best-practice platitude.
