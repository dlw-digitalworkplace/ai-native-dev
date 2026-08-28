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

**Then read real source — this is not optional.** Manifests and directory listings only reveal the
*map* of the repo; the actual coding conventions live in the code. Open a **representative sample**
of the project's real units and read it properly. **What a "unit" is depends entirely on the
project type — adapt the sample to what this repo actually is, don't force a web-app shape onto it:**
- a web back-end/front-end → a few services, an endpoint/controller/function, a component, a hook;
- a **library / package** → the public API surface, the main modules, a couple of internal
  implementations, the packaging manifest;
- a **script collection** (PowerShell/Bash/Python) → several representative scripts end-to-end —
  param/arg handling, error handling, output/logging style;
- a **CLI**, **data pipeline / notebooks**, **infra/IaC**, **mobile app**, etc. → the equivalent
  core units for that kind of project.

Also open the tooling configs that encode a style (whatever the stack uses — `.editorconfig`,
`eslint`/`prettier`, `ruff`/`black`/`flake8`, `PSScriptAnalyzer`, `Directory.Build.props`,
`tsconfig`, …). You are reading to extract the **recurring patterns a new contributor would be
expected to follow** — see the convention checklist in step 3. Skimming file names is the mistake
that produces shallow, map-only rules.

**Separately, read for the functional/domain architecture — this is the lens most often missed.**
The convention-reading above finds *how code is written*; this pass finds *what the app is and how
it's structured as a domain*. Trace it deliberately — reading a service and a component tells you the
tech, not the domain:
- The **core domain abstraction and its extension/variability model** — the thing the codebase is
  organised *around* and how you plug new behaviour into it. e.g. a base connector + pluggable
  per-connector orchestrators behind a dispatcher; an app-of-mini-apps; a plugin registry; a
  library's public API + strategy interfaces; a CLI's command set. Find it via the central
  abstractions, the dispatcher/registry/orchestrator, marker/base types, and the product docs.
- The **main flow/pipeline** end-to-end, and where variability plugs in.
- The **key entities, their relationships, and the invariants** every feature must uphold.
- **How you add a new "unit" of the domain** (a new connector / mini-app / plugin / command) — the
  concrete extension recipe. This is the single highest-value functional rule for the planner and
  coder, because whole stories map directly onto it.
This applies to any project type — a library's extension points, a pipeline's stage model, an IaC
repo's module topology are all "functional architecture." See lens 3 in step 2.

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
   "the app is composed of mini-apps", "connectors extend a base model and plug into a shared
   orchestrator", "every entity is scoped to a couple of IDs / a tenant". Capture the **core domain
   abstraction and its extension model**, the main flow, the key entities/invariants, and **how you
   add a new unit of the domain** (see the functional-architecture reading pass in step 1). Infer it
   from the product docs, the domain/entity model, central abstractions, dispatchers/registries,
   base/marker types, and recurring scoping patterns. **This is the most commonly missed lens and
   often the most valuable — do not stop at the technical layers.** Name the file after the domain
   concept (`connectors.md`, `mini-apps.md`, `domain-model.md`), not after a tech layer.

**Completeness check before you finalize:** most repos need **at least one lens-3
(functional/domain) rule** — if you drafted only technical-layer and cross-cutting rules, that is a
red flag you stopped at the map. Re-examine the domain and either add the functional rule or state
explicitly in the summary (step 8) why this repo genuinely has none (rare — e.g. a pure utility
library with no domain model).

**Strictly evidence-only — this is the key rule.** Create a rule file **only** for an area that
genuinely exists in the codebase. If there is **no** test framework, write **no** testing rule;
if there is **no** docs system, write **no** docs rule. Absence of evidence means no file — do
not emit a stub just because it is a common category. It is correct (and expected) for a small
app to get, say, `frontend.md`, `backend.md`, `authentication.md`, and `mini-apps.md` — and
nothing else.

### 3. Draft one rule file per area → `.claude/rules/<area>.md`
Name each file after the area in kebab-case (`frontend.md`, `backend.md`, `authentication.md`,
`mini-apps.md` or `domain-model.md`, …). For each, write concrete conventions and invariants, each
grounded in where you saw it (cite files/paths), and start each file with the DRAFT banner (below).
See `${CLAUDE_PLUGIN_ROOT}/project-template/rules/_TEMPLATE.md` for the rule-area categories and a
section shape — a guide, **not** a set of files to reproduce.

**Write rules as directives, not as hedged observations.** The whole draft is a suggestion (the
human reviews and decides which rules survive — that is what the DRAFT banner and step 8 handoff
cover). But each rule that stays *will be enforced* by the planner and reviewer, so its text must
read as a **requirement**: "New service abstractions **must** live in a `Contracts/` folder"
(grounded in a cited example) — **not** "some code observes interfaces in Contracts folders." Do not
use "suggested/observed conventions" as section headers. Imperative + cited evidence is the target.

**Go past the map — capture the *coding* conventions.** Structural rules ("keep code in the right
layer") are necessary but not sufficient; the high-value rules are the implementation patterns a
coder must match. From the source you read in step 1, write a rule for **every pattern that genuinely
recurs** (evidence-only — no evidence, no rule).

The list below is a **prompt to think with, not a boundary or a checklist to complete** — and it
leans toward a service/web app. **Translate each item to whatever THIS project is, and go beyond the
list** to whatever conventions actually matter for this kind of code. The point is to capture *this
repo's* real rules, whatever shape they take:
- **Logging / observability** — e.g. message-template logging, scopes, correlation ids; for a script
  it might be a `Write-Verbose`/output convention.
- **Error / exception handling** — how failures are caught, wrapped, surfaced; what context is kept.
- **Naming** — modules, files, types, functions, symbols.
- **Folder / module organisation** — what each folder or module is *for* (e.g. abstractions vs
  implementations vs models; a library's public API vs internals).
- **Interface / abstraction / public-API placement** — where contracts or exported surfaces live.
- **Composition / wiring** — dependency injection, a plugin registry, a script's entry/dispatch, etc.
- **Imports / references** — path aliases vs relative, module import style, namespacing.
- **I/O & data patterns** — the standard request/response/error flow, DB access, file/stream handling.
- **State management** (front-end) — local vs server-cache vs global store, and when.
- **Public contract of a unit** — for a library/CLI/script: parameters, return shapes, exit codes,
  argument parsing, versioning/back-compat expectations.
- **Validation**, **config/secrets access**, and **test patterns** where a convention exists.

For a Python library, a PowerShell script set, a CLI, a data pipeline, or an IaC repo the *items*
differ but the *job is identical*: read the real code, find what recurs, and write it as a rule.
- **Lint / format baseline** — read `.editorconfig`/eslint/prettier and state the baseline; where a
  convention is already machine-enforced, **point to the tool** rather than restating the rule (keeps
  rule files about what tooling can't catch, and avoids bloat).

Bias toward conventions that (a) recur, (b) a contributor could plausibly get wrong, and (c) aren't
already enforced by tooling — that keeps rule files sharp rather than exhaustive.

**Detect and resolve conflicting conventions.** A real repo often has *competing* patterns for the
same concern (two state-management approaches, two error-handling styles, a folder convention applied
inconsistently). Don't silently pick one and don't bury it as a vague note. For each **material**
conflict (one that changes how a coder would write code):
1. Ask the human to resolve it **during this run** via `AskUserQuestion` — present the concrete
   competing options (a copy-pasteable candidate rule for each), with your recommended default first.
2. Write the **chosen** option as the imperative rule in the relevant rule file, and keep a short
   **Convention decision** note beneath it recording the alternatives that were considered (so the
   choice is auditable and revisitable).
Immaterial/cosmetic inconsistencies that tooling already normalises don't need a question — just note
the baseline. Ask about the ones that matter; don't turn onboarding into an interrogation.

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

**Required frontmatter — every `SKILL.md` must start with a `name` *and* a `description`** (a
missing `name` triggers a host "Skill should provide a name" warning). `name` must match the skill's
directory (`backend-build/SKILL.md` → `name: backend-build`); add `allowed-tools: Bash` for a skill
that runs a command:
```
---
name: backend-build
description: Build the .NET backend solution.
allowed-tools: Bash
---
```

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
- The **work-item tracker** — where stories live (suggest, don't assert). This is a **closed choice of
  exactly two options** — present only these; **do not offer any other tracker** (in particular there
  is **no GitHub Issues / GitHub PRs work-item backend** — a GitHub project still stores stories in
  `file` or `ado`, never in GitHub Issues). The tracker is a **separate axis from the code host**:
  choosing GitHub as the code host does **not** add a "GitHub Issues" tracker choice.
  - **`ado`** — Azure DevOps Boards work items (the default). Choose this when the project has an ADO
    backlog you can reach. Default-highlight it when the code host is ADO.
  - **`file`** — a local **markdown file per work item** (no external tracker). Choose this when there
    is **no backlog / no ADO access** (e.g. code-only access via a PAT, or a GitHub-hosted project
    with no ADO Boards). Default-highlight it when the code host is not ADO. Then ask for the
    **item-store directory**, defaulting to `.aind/items` inside the repo; make clear **any absolute
    path is accepted, including outside the repo** (a synced folder, a home dir) for the code-only case.
- If tracker = `ado`: the **ADO org URL** and **project**, if not derivable.
- Confirm the **code host** when the remote was ambiguous.
- Whether to **enable worktrees** for parallel work (default: no).
- Whether to **track per-phase token/time telemetry** onto the work item (default: no). The token
  breakdown is stored as a JSON **attachment** (an ADO work-item attachment, or a file under the
  item store's `attachments/`); **time** accumulates into a duration total. For the `ado` tracker, if
  yes, ask for a numeric duration field's reference name (e.g. `Custom.AindDurationSec`) — the ADO
  process must define it as an integer field; telemetry still records the token attachment without
  one. For the `file` tracker no field is needed (time accumulates in the item's `durationSeconds`).

**Write** the files:
```bash
cp "${CLAUDE_PLUGIN_ROOT}/rubric/intake-rubric.seed.md" .claude/intake-rubric.md
```
- `.claude/aind.settings.json` — base it on
  `${CLAUDE_PLUGIN_ROOT}/project-template/aind.settings.sample.json`, filled with the detected +
  answered values. Set `tracker` to the chosen backend. For `ado`: fill the `ado` block and drop
  `trackerDir`. For `file`: set `trackerDir` to the chosen path (an absolute path if outside the repo;
  the in-repo default `.aind/items` otherwise) and leave the `ado` block at its placeholders (unused).
  Set only the repo key matching the chosen host (`github.repo` **or** `ado.repo`); leave the other at
  its placeholder. Set `worktree.enabled` per the answer; leave the rest of the `worktree` block at its
  sample defaults. Set the `telemetry` block from the answer: if the user opted in, set `enabled: true`
  (and, for the `ado` tracker, `durationField` to their field's `refName` if they gave one); otherwise
  leave it `enabled: false` (telemetry stays inert). **This file is checked in** (shared config).
- `.claude/aind.env` — base it on `${CLAUDE_PLUGIN_ROOT}/project-template/aind.env.sample`. For the
  `ado` tracker, leave `AZURE_DEVOPS_EXT_PAT="<pat>"` as a **placeholder** (never write a real secret).
  For the `file` tracker no work-item PAT is needed (a code-host token may still be — e.g. `gh` auth
  or an ADO Code PAT). **This file is gitignored.**
- **File tracker only** — create the item store and seed the template so `new` works and the human
  can see the fixed structure. Only add the gitignore line when the store is the in-repo default (an
  external path is never touched by gitignore logic):
  ```bash
  bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-tracker.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" require   # resolves + creates the item dir
  cp "${CLAUDE_PLUGIN_ROOT}/project-template/item-template.md" "<item-dir>/_TEMPLATE.md"  # reference copy
  ```
  Tell the human to create the first story with **`/aind:new-item`** (a guided draft-for-review; or
  `bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-tracker.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" new "<title>"` for the bare scaffold) and then
  edit its Description / Acceptance Criteria; the AIND phases drive its `state` automatically.

**Update `.gitignore`** idempotently (append only if the line is absent):
```bash
grep -qxF '.claude/aind.env' .gitignore 2>/dev/null || echo '.claude/aind.env' >> .gitignore
grep -qxF '.aind/usage/' .gitignore 2>/dev/null || echo '.aind/usage/' >> .gitignore
# only when the research dir is the in-repo default (not an external absolute path):
grep -qxF '.aind/research/' .gitignore 2>/dev/null || echo '.aind/research/' >> .gitignore
# only if worktrees were enabled:
grep -qxF '.claude/worktrees/' .gitignore 2>/dev/null || echo '.claude/worktrees/' >> .gitignore
# only for the file tracker AND only when the item store is the in-repo default (not an external path):
grep -qxF '.aind/items/' .gitignore 2>/dev/null || echo '.aind/items/' >> .gitignore
```
(`.aind/usage/` holds transient per-phase telemetry markers and `.aind/research/` holds local
pre-story research findings — both always gitignored, harmless when unused.)

### 6.5 Offer the native-State mirror (optional — ADO tracker only)
**Skip this step entirely when the tracker is `file`** — the file backend stores the AIND state
directly as the item's `state:` field, so there is no separate native State to mirror.
AIND tracks flow state in its own status **tag**; a team that reads the ADO **board** may also want
the work item's built-in **State** field to follow along. Offer it — **`AskUserQuestion`**: "mirror
AIND status onto the native State field?" (a good default for board-reading teams). If **yes**, run
the same mapping `/aind:map-states` performs — **adopt the project's existing states, never force new
ones.** Ask for (or reuse) the story **work-item type**, then:
```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-states.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" propose "<story work-item type>"
```
Each line is `status ⇥ category ⇥ resolved-state ⇥ count ⇥ candidates`. Auto-accept every row whose
`count` is 1; for `count` 0 or >1, ask the human which state to use (or leave that status unmapped).
Then write the resolved map:
```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-states.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" write <<'EOF'
{ "<aind-status>": "<state>", "…": "…" }
EOF
```
If **no** (or you skip it), leave `stateMap` as `{}` — no mirror, behaviour unchanged. Either way,
`/aind:map-states` re-runs this anytime the project's states change.

### 7. Report prerequisites
Run the preflight probe and relay its checklist:
```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-preflight.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}"
```
(On **GitHub Copilot CLI / Windows**, if this fails with "bash not found", Git's `bash` isn't first
on PATH — invoke the script via the Git bash binary and surface the PATH fix as a prerequisite.
Never reimplement these scripts in PowerShell: that silently breaks the single-status-tag invariant
and comment signing.)

### 8. Summarize to the user
- The rule areas you found (across the three lenses) and the files you drafted (paths), and
  — briefly — any common category you **deliberately skipped** because the codebase had no
  evidence for it (e.g. "no testing rule: no test framework found"). **Explicitly name the
  functional/domain rule you wrote** — or, if you wrote none, why this repo has no domain model.
- The skills you stubbed and the commands behind them.
- Any **convention conflicts** you resolved with the human during the run, and the option chosen for
  each (each also recorded as a Convention decision note in the rule file).
- The prerequisite status from preflight, with the `[FAIL]`/`[MANUAL]` items called out as
  the team's next setup steps (ADO PAT, code-host access — `gh` for GitHub or `az repos` for ADO —
  jq, and the host-specific manual items preflight lists, e.g. the Azure Boards↔GitHub integration
  and the branch policy that requires comment resolution before merge).
- **The config you created:** `.claude/aind.settings.json` (shared, checked in — review its values,
  including the chosen `tracker`) and `.claude/aind.env` (gitignored). For the **`ado` tracker**, the
  one manual step left is **pasting the ADO PAT** into `.claude/aind.env` (written as a `<pat>`
  placeholder). For the **`file` tracker**, no work-item PAT is needed — note the item-store path and
  how to create the first story (`aind-tracker.sh new "<title>"`). Note you added the gitignore
  line(s). If you set up the native-State mirror (ADO only), note the `stateMap` written (and that
  `/aind:map-states` re-runs it later).
- A clear note: **the rules/skills are drafts — review and edit before committing**, then run
  `/aind:intake <id>` on a story to start the flow.

## DRAFT banner
Prefix every generated markdown file with:
```
<!-- AIND ONBOARDING DRAFT — generated by /onboard from this codebase.
     The rules below are written as requirements the flow will enforce once kept; this DRAFT status
     means YOU review and decide which to keep, correct, or drop before relying on them. -->
```

## Notes
- You **suggest**; you never assert. The human owns the final config.
- Stay within the config layer — you scaffold `.claude/`, never the flow itself (the same
  boundary the dreamer respects).
- Be concrete: a rule grounded in an observed file beats a generic best-practice platitude.
