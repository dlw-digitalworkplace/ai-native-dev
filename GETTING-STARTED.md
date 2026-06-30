# Getting started

How to set up and use AIND on an existing GitHub codebase. The smart order is **onboard first**
(it only reads your code and writes draft config — no auth needed — then tells you exactly
what's left to set up), then wire up the auth/config the flow needs.

> **Command names are namespaced.** Plugin slash commands are prefixed with the plugin name:
> `/aind:onboard`, `/aind:intake`, `/aind:plan`, `/aind:approve-plan`. Bare `/onboard` won't
> resolve — type `/aind` (or `/` and scroll) to see them. See [Troubleshooting](#troubleshooting).

In the commands below, replace `<...>` placeholders with your own values: `<your-ado-org>` /
`<your-ado-project>` = your Azure DevOps org and project; `<owner>/<repo>` = **your project's**
GitHub repo (the codebase you're onboarding).

---

## Prerequisites

Most of these are checked automatically by `/aind:onboard`'s preflight probe, which reports
what's missing.

- **Tools:** `az` (+ the `azure-devops` extension), `gh`, `git`, `curl`, `jq`, `bash`.
  - Install `jq`: `winget install jqlang.jq` (Windows) · `brew install jq` (macOS) · `apt install jq` (Linux).
- **GitHub auth:** `gh` authenticated as an account that can access your repo — verify with
  `gh repo view <owner>/<repo>`. (`gh auth login` / `gh auth switch` if needed.)
- **ADO auth:** a Personal Access Token with **Work Items (Read & Write)** + **Code (Read & Write)**.
  It goes in `.claude/aind.env` as `AZURE_DEVOPS_EXT_PAT` (see step 3) — the scripts read it from there.
- **Azure Boards ↔ GitHub integration** connected, so a PR mentioning `AB#<id>` links to the work
  item (D17). Confirm with a test PR.
- **Branch protection** on your integration branch: enable **"require conversation resolution
  before merging"** (D5) — this is what makes the planner's assumption threads block the plan-PR
  merge until you resolve them.

### Validate prerequisites — run the preflight

A read-only probe checks the tools, auth, config, and connectivity above and prints a
`[PASS] / [WARN] / [FAIL]` checklist with a summary. It never changes anything (always exits 0).

- **In a Claude Code or Copilot session** (easiest): ask it to **"run the AIND preflight check"**.
  It also runs automatically as the final step of `/aind:onboard`.
- **From a terminal**, run it **from your project root** (so it auto-loads `.claude/aind.env` — no
  `source` needed):
  ```bash
  bash <plugin-dir>/scripts/aind-preflight.sh    # <plugin-dir> = the dir containing .claude-plugin/plugin.json
  ```

Resolve every **`[FAIL]`** before running the plan-phase commands. **`[WARN]`** is usually config
you haven't filled in yet (see step 3), and **`[MANUAL]`** items (the Boards↔GitHub integration and
branch-protection rule) can't be auto-verified — confirm those by hand.

> **Using GitHub Copilot CLI instead of Claude Code?** The plugin installs there too
> (`copilot plugin install <owner>/<repo>`) and its commands appear namespaced (`/aind:intake`, …).
> One extra requirement **on Windows**: Copilot's shell tool is PowerShell, but the plugin's
> mechanics are Bash scripts — so **Git's `bash` must be the `bash` that resolves in the shell that
> launches `copilot`**.
>
> Two gotchas make this trickier than "add Git to PATH":
> 1. The usual Git installer only puts `Git\cmd` (which has `git`, not `bash`) on PATH.
> 2. Windows ships a **WSL `bash.exe` in `System32`** that *shadows* Git's bash — and because
>    `System32` is on the machine PATH (searched before your user PATH), **appending** `Git\bin` to
>    your user PATH is **not enough**; the WSL bash still wins (and fails with "No such file or
>    directory" if you have no WSL distro). Git's bash must come **first**.
>
> The reliable fix is to **prepend** `Git\bin` in your PowerShell profile, so every new shell (and any
> `copilot` launched from it) resolves Git's bash first:
>
> ```powershell
> $line = '$env:PATH = "C:\Program Files\Git\bin;" + $env:PATH'   # adjust if Git is elsewhere
> if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
> if (-not (Select-String -Path $PROFILE -SimpleMatch 'Program Files\Git\bin' -Quiet)) { Add-Content $PROFILE $line }
> ```
>
> Then open a **new** terminal (fully reopen Windows Terminal / VS Code — a new tab reuses the cached
> environment) and **verify which bash wins**:
>
> ```powershell
> (Get-Command bash).Source        # must print C:\Program Files\Git\bin\bash.exe, NOT System32\bash.exe
> ```
>
> Launch `copilot` only once that check passes. Without Git's bash resolving first, Copilot can't run
> the scripts and may improvise the ADO/GitHub calls in PowerShell — which bypasses comment signing
> and the single-status-tag rule. (Claude Code is unaffected; it finds bash on its own.)

---

## 1. Load the plugin

Run Claude Code **from the root of the project you're onboarding** — the plugin scaffolds into
that project's `.claude/`. Load it either remotely or from a local clone:

```bash
# Remote (no local copy needed) — loads the published release for this session:
claude --plugin-url https://github.com/dlw-digitalworkplace/ai-native-dev/releases/latest/download/aind.zip

# …or local, if you've cloned the plugin:
claude --plugin-dir <plugin-dir>      # the dir containing .claude-plugin/plugin.json
```

**Using GitHub Copilot CLI instead?** Install the plugin once (it persists across sessions), then
run `copilot` from the project root:

```bash
copilot plugin install dlw-digitalworkplace/ai-native-dev     # from GitHub
# …or from a local clone:
copilot plugin install "C:/path/to/ai-native-dev"
```

On Windows, make sure Git's `bash` is on PATH first — see the Copilot note under
[Prerequisites](#prerequisites). (Re-install after pulling plugin updates — a local install is a snapshot.)

Confirm it loaded: type `/aind` — you should see `onboard`, `intake`, `plan`, `approve-plan` (namespaced as `/aind:onboard`, etc.).

## 2. Bootstrap the config — `/aind:onboard`

```
/aind:onboard
```

It reads the codebase, discovers the rule areas that actually exist, and **drafts** into
`.claude/`: per-domain `rules/*.md`, a wired `CLAUDE.md`, project skills for the build/test/run
commands it finds, and a copy of the intake rubric. It finishes with a **preflight** checklist.

**No ADO/GitHub auth needed for this step.** When it's done, **review and edit the drafts**
(marked `AIND ONBOARDING DRAFT`), then commit the ones you want.

## 3. Fill in config

```bash
cp .claude/aind.env.sample .claude/aind.env     # onboard placed the sample
# edit .claude/aind.env: set AIND_ADO_ORG, AIND_ADO_PROJECT, AIND_GH_REPO,
#   AIND_INTEGRATION_BRANCH, and AZURE_DEVOPS_EXT_PAT
echo ".claude/aind.env" >> .gitignore           # holds the secret PAT — never commit it
```

The scripts **auto-load `.claude/aind.env`** (walk-up from the working directory), so you don't
need to `source` it by hand — just run the commands from inside the project. (An already-set
environment wins, so CI or a parent shell can override it.)

Re-check everything is green by re-running preflight (ask Claude to "run the AIND preflight
check", or run it directly):

```bash
bash <plugin-dir>/scripts/aind-preflight.sh
```

## 4. Run the flow

Tag an ADO user story `AIND status - Ready for intake`, then drive it through the plan phase:

| Command | Phase | Effect |
|---|---|---|
| `/aind:intake <id>`       | 0 | Score the story; post a signed verdict + readiness score; tag → `Intake approved` / `Intake declined`. |
| `/aind:plan <id>`         | 1 | Write `plans/<id>/plan.md`; open the plan PR (`AB#`, `AIND-LINKS`); post assumptions as resolvable threads; tag → `Plan ready for review`. |
| `/aind:approve-plan <id>` | 2 | After you approve **and merge** the plan PR in GitHub: tag → `Ready for implementation`. |

A declined story is edited and re-tagged `Ready for intake`, which re-runs intake. Plan-review
revisions happen in the PR and don't change the tag.

**End-to-end check:** run `/aind:intake` on an under-designed story (expect a decline with the
failing criteria), fix it, re-run (expect approval + a single status tag). Then `/aind:plan`,
and confirm the plan PR carries the `AIND-LINKS` block, a native `AB#` link to the work item,
and one resolvable thread per assumption — and that branch protection blocks the merge until the
threads are resolved. Merge, then `/aind:approve-plan`.

---

## Publish updates to GitHub (maintainers)

`deploy.sh` publishes the plugin so it can be loaded remotely (the `--plugin-url` above). It
builds a root-structured `aind.zip` from `HEAD`, uploads it as a **Release asset**, and publishes
the diagram (`docs/index.html`) as the **GitHub Pages** site.

```bash
./deploy.sh        # prereqs: public repo committed+pushed, gh authed (admin for Pages), git + gh
```

- The zip is a **snapshot** — re-run after changes. Bump `version` in `.claude-plugin/plugin.json`
  for a fresh release tag.
- Loaders always get the latest deploy via `releases/latest/download/aind.zip`.
- If it can't auto-enable Pages, set it once in **Settings → Pages** (source = your branch, `/docs`).

---

## Troubleshooting

**`/onboard` (or any command) doesn't appear.**
Plugin commands are namespaced — use `/aind:onboard`, not `/onboard`. Type `/aind` to list them.

**Still nothing under `/aind`.**
1. (Local) confirm `--plugin-dir` points at the plugin root (contains `.claude-plugin/plugin.json`),
   not a parent dir. (Remote) confirm the zip URL returns HTTP 200.
2. Validate the manifest: `claude plugin validate <plugin-dir>` (should say *Validation passed* —
   one warning about a root `CLAUDE.md` not being loaded as context is expected and harmless).
3. Launch with `--debug` and look for plugin-load errors.

**`aind-comment` / `aind-status` fail with `jq: command not found`.**
Install `jq` (see Prerequisites) — the plugin runtime needs it to build JSON. (`deploy.sh` does not.)

**ADO calls fail with auth errors.**
Ensure `AZURE_DEVOPS_EXT_PAT` is set in `.claude/aind.env` (the scripts auto-load it) and that the
PAT has Work Items + Code read/write on your ADO org. Precedence note: auto-load is skipped when
`AIND_ADO_ORG` is already set in your shell (so CI / a parent shell can override the file) — if you
exported stale values earlier, unset `AIND_ADO_ORG` (or use a fresh shell) to let the file load.

**Scripts fail with `$'\r': command not found`.**
The scripts must be LF, not CRLF. `.gitattributes` enforces `*.sh eol=lf`; if you hit this, run
`git add --renormalize . && git checkout -- scripts hooks`.
