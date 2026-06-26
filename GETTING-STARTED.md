# Getting started — AIND on an existing project

A step-by-step walkthrough for adopting the AIND plan-phase flow on any existing GitHub
codebase. The smart order is **onboard first** (it only reads your code and writes draft
config — no auth needed — and then tells you exactly what's left to set up), then wire up the
auth/config the flow needs.

> **Command names are namespaced.** Plugin slash commands are prefixed with the plugin name:
> `/aind:onboard`, `/aind:intake`, `/aind:plan`, `/aind:approve-plan`. Typing bare `/onboard`
> will *not* find it — type `/aind` (or `/` and scroll) to see them all. See
> [Troubleshooting](#troubleshooting) if they don't appear.

In the commands below, replace `<...>` placeholders with your own values:
`<plugin-dir>` = where you cloned this plugin, `<owner>/<repo>` = your GitHub repo,
`<your-ado-org>` / `<your-ado-project>` = your Azure DevOps org and project.

---

## 1. Open your project and load the plugin

From the root of the project you want to onboard:

```bash
claude --plugin-dir <plugin-dir>      # e.g. /path/to/ai-native-dev
```

- `--plugin-dir` points at the **plugin root** (the directory that contains
  `.claude-plugin/plugin.json`).
- It loads for **this session only**; no install, marketplace, or restart needed.
- Run Claude Code **from your project root** — `/aind:onboard` scaffolds into the current
  project's `.claude/`.

Confirm it loaded: type `/aind` — you should see `onboard`, `intake`, `plan`, `approve-plan`.

## 2. Bootstrap the config — `/aind:onboard`

```
/aind:onboard
```

It reads the codebase, discovers the domains that actually exist, and **drafts** into
`.claude/`: per-domain `rules/*.md`, a wired `CLAUDE.md`, project skills for the build/test/run
commands it finds, and a copy of the intake rubric. It finishes by running a **preflight**
probe and printing a prerequisites checklist.

**This step needs no ADO/GitHub auth.** When it's done, **review and edit the drafts** (they're
suggestions, marked `AIND ONBOARDING DRAFT`), then commit the ones you want.

## 3. Resolve the preflight items

Preflight reports what's missing. Common items:

- **Install `jq`** — `brew install jq` (macOS) / `apt install jq` (Linux) /
  `winget install jqlang.jq` (Windows). Required by the signed-comment path.
- **GitHub access** — make sure `gh` is authenticated as an account that can see your repo:
  `gh repo view <owner>/<repo>`. If not, `gh auth login` (or `gh auth switch`) to the right
  account.
- **ADO auth** — create a Personal Access Token in your Azure DevOps org with **Work Items
  (Read & Write)** + **Code (Read & Write)**, and set it as `AZURE_DEVOPS_EXT_PAT`.

## 4. Fill in config

```bash
cp .claude/aind.env.sample .claude/aind.env     # onboard placed the sample
# edit .claude/aind.env: set AIND_ADO_ORG, AIND_ADO_PROJECT, AIND_GH_REPO,
#   AIND_INTEGRATION_BRANCH, and AZURE_DEVOPS_EXT_PAT
echo ".claude/aind.env" >> .gitignore           # it holds the secret PAT — never commit it
```

The AIND scripts **auto-load `.claude/aind.env`** (walk-up from the working directory), so you
don't need to `source` it by hand — just run the commands from inside the project. (An
already-set environment wins, so CI or a parent shell can override it.)

Re-check it's green by re-running the preflight (the `aind-preflight` skill, or directly):

```bash
bash <plugin-dir>/scripts/aind-preflight.sh
```

## 5. Two one-time repo settings

Preflight lists these as `[MANUAL]` because they can't be auto-checked:

- **Azure Boards ↔ GitHub integration** connected — so a PR mentioning `AB#<id>` links to the
  work item (D17). Confirm with a test PR.
- **Branch protection** on the integration branch: enable **"require conversation resolution
  before merging"** (D5). This is what makes the planner's assumption threads actually block
  the merge until you resolve them.

## 6. Run the flow

Tag an ADO user story `AIND status - Ready for intake`, then:

```
/aind:intake <work-item-id>        # scores the story, posts a signed verdict, sets the tag
/aind:plan <work-item-id>          # once Intake approved: drafts the plan, opens the plan PR
# review/approve & merge the plan PR in GitHub, then:
/aind:approve-plan <work-item-id>  # sets Ready for implementation
```

---

## Troubleshooting

**`/onboard` (or any command) doesn't appear.**
Plugin commands are namespaced — use `/aind:onboard`, not `/onboard`. Type `/aind` to list
them.

**Still nothing under `/aind`.**
1. Confirm the path is the plugin root (contains `.claude-plugin/plugin.json`):
   `--plugin-dir <plugin-dir>` (not a parent directory).
2. Validate the manifest: `claude plugin validate <plugin-dir>`
   (should say *Validation passed*).
3. Launch with `--debug` and look for plugin-load errors:
   `claude --plugin-dir <plugin-dir> --debug`.

**`aind-comment` fails / `jq: command not found`.**
Install `jq` (see step 3) — it's required to JSON-encode comments.

**ADO calls fail with auth errors.**
Ensure `AZURE_DEVOPS_EXT_PAT` is set in `.claude/aind.env` (the scripts auto-load it) and that
the PAT has Work Items + Code read/write on your ADO org. Precedence note: auto-load is skipped
entirely when `AIND_ADO_ORG` is already set in your shell (so CI / a parent shell can override
the file) — so if you exported stale values earlier, the file won't reload over them; unset
`AIND_ADO_ORG` (or use a fresh shell) to let `.claude/aind.env` take effect.

**Scripts not executable in a fresh clone.**
After committing the plugin, set the exec bit once:
`git update-index --chmod=+x scripts/*.sh hooks/*.sh`.
