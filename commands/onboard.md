---
description: Bootstrap AIND config for an existing project — discover its rule areas (technical layers, cross-cutting concerns, functional/domain architecture), draft project rules + skills from the codebase, and report prerequisites.
argument-hint: (run from the project root; no arguments)
allowed-tools: Bash, Read, Glob, Grep, Write
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
Explore breadth-first to understand the project. Look at:
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
   authorization, security, logging/observability, error handling, config/secrets, i18n. Give
   one its **own** rule file when the project does it in a specific or unusual way that a
   planner must respect — e.g. a custom **pin-code auth** scheme deserves its own
   `authentication.md`.
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
Base it on `${CLAUDE_PLUGIN_ROOT}/project-template/CLAUDE.md`, then:
- Keep the **AIND operational rules** block verbatim.
- Fill the **AIND configuration** table with what you can detect. **Detect the code host** (where
  the code + pull requests live) from `git remote get-url origin`:
  - a `github.com` remote → `AIND_CODE_HOST=github` and `AIND_GH_REPO=<owner>/<repo>`;
  - a `dev.azure.com` / `visualstudio.com` remote → `AIND_CODE_HOST=ado` and `AIND_ADO_REPO=<repo>`
    (also derive `AIND_ADO_ORG` / `AIND_ADO_PROJECT` from the remote URL when you can).
  - no remote or an unrecognised host → leave `AIND_CODE_HOST` as a placeholder for the human and
    say so. Only set the repo var that matches the chosen host; leave the other unset.
  Propose `AIND_INTEGRATION_BRANCH` from the repo's default branch. Leave the ADO org/project (when
  not derivable) and the PAT as placeholders for the human.
- Replace the placeholder `@rules/*` imports with one `@rules/<area>.md` line for **exactly the
  rule files you created** in step 3 — no more, no fewer.

### 5. Stub discovered project skills → `.claude/skills/<name>/SKILL.md`
From the manifests/CI/scripts, extract the real **deterministic dev workflows** and stub a skill
per command you find. **Build / test / run-app / lint are the common core**, but skills are not
limited to them — also stub any other scriptable, repeatable workflow the repo actually has:
e.g. `deploy`, `migrate` (DB migrations), `seed` (test/dev data), `codegen` / `scaffold`, `format`,
`start-deps` (docker-compose / local dependencies), `generate-client` (API client), `e2e`. Put the
actual command in each skill body and mark assumptions as DRAFT. These feed the planner and the
build phase ("what can be scripted should be scripted"). **Evidence-only:** only create a skill for
a command you actually found in the repo — don't emit a `deploy` skill just because deploy is common.

### 6. Copy the seed rubric and env sample
```bash
cp "${CLAUDE_PLUGIN_ROOT}/rubric/intake-rubric.seed.md" .claude/intake-rubric.md
cp "${CLAUDE_PLUGIN_ROOT}/project-template/aind.env.sample" .claude/aind.env.sample
cp "${CLAUDE_PLUGIN_ROOT}/project-template/aind-worktree.config.sample.json" .claude/aind-worktree.config.sample.json
```
(Use the `<name>.aind-draft` fallback if a target already exists.) Remind the human to create
`.claude/aind.env` from the sample and **gitignore it** (it holds the PAT). **Worktrees (optional):**
if the team wants to work multiple stories in parallel from one clone, tell them to copy
`aind-worktree.config.sample.json` → `.claude/aind-worktree.config.json` (its presence opts in) and
add `.claude/worktrees/` to `.gitignore`. Leaving the file out keeps single-tree behaviour.

### 7. Report prerequisites
Run the preflight probe and relay its checklist:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-preflight.sh"
```

### 8. Summarize to the user
- The rule areas you found (across the three lenses) and the files you drafted (paths), and
  — briefly — any common category you **deliberately skipped** because the codebase had no
  evidence for it (e.g. "no testing rule: no test framework found").
- The skills you stubbed and the commands behind them.
- The prerequisite status from preflight, with the `[FAIL]`/`[MANUAL]` items called out as
  the team's next setup steps (ADO PAT, code-host access — `gh` for GitHub or `az repos` for ADO —
  jq, and the host-specific manual items preflight lists, e.g. the Azure Boards↔GitHub integration
  and the branch policy that requires comment resolution before merge).
- A clear note: **these are drafts — review and edit before committing**, then run
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
