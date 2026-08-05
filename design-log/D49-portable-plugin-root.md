# D49 — Portable plugin-root resolution across agent hosts

- **Area:** Script-invocation mechanics / dual-host packaging (the D22 *agent-host* axis; script-only, does not touch the flow, status model, gates, or PR contract of D1–D15)
- **Date:** 2026-08-05
- **Status:** Active

## Decision
Every place a command / skill / agent invokes a plugin script is changed from the host-specific
form

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-<name>.sh" <args>
```

to a **portable resolver** that works identically on Claude Code and GitHub Copilot CLI:

```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-<name>.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}" <args>
```

Resolution order for the plugin root `R`:
1. **`${CLAUDE_PLUGIN_ROOT}` passed as the top-level positional arg `$1`.** On Claude this is a
   command-string **macro** the Bash tool substitutes before running, so `$1` arrives as the real
   plugin dir. On Copilot the token is not substituted and PowerShell expands it to empty, so `$1`
   arrives blank — harmlessly — and resolution falls through.
2. **`$AIND_PLUGIN_ROOT`** — an optional explicit override (env var or a value a project pins),
   for non-standard installs.
3. **Self-location** by globbing the known install layout: Copilot
   `~/.copilot/installed-plugins/*/*ai-native-dev`, Claude `~/.claude/plugins/*/*ai-native-dev`.
   `$HOME` is deliberately **not** trusted (it can be a mapped drive under MSYS); the home dir is
   derived from `USERPROFILE` via `cygpath -u`.

Deliberate properties:

- **Constant preamble → tight allowlisting preserved.** Every call shares a **byte-identical**
  preamble (`R="$1"; shift; …`), so a single permission rule (`Bash(bash -c 'R="$1"; shift;*)`)
  covers all plugin-script calls and nothing else — the same one-rule posture the old
  `Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/*)` gave, not a blanket `bash -c` allow. Onboarding
  writes this rule; the docs carry it.
- **Heredoc call sites keep working.** For `aind-comment.sh` / `aind-states.sh write` the heredoc is
  attached to the **outer** `bash -c`; the inner script inherits fd 0, so the body flows through
  unchanged. Verified.
- **Everything runs inside a single `bash -c '…'` with the payload single-quoted**, so PowerShell
  (Copilot's shell tool) neither expands `${…}` prematurely nor mis-parses redirections
  (`>/dev/null` → `Out-File C:\dev\null` was an observed failure of the old top-level form).
- **The resolver is byte-identical to `/aind:env-probe` test [4].** That command is retained as the
  permanent dual-host validator: a green `[4] RESOLVER OK` on a host literally certifies the shipping
  invocation on that host. Re-run it after any Claude/Copilot CLI upgrade.

**Explicitly out of scope — hooks are unchanged.** `hooks.claude.json` and `hooks.copilot.json`
reference `$CLAUDE_PLUGIN_ROOT` in the **hook** environment, which *both* hosts inject (this is why
comment-signing enforcement already works on Copilot). Only the **command→shell-tool** path lacked a
working root; hooks keep `$CLAUDE_PLUGIN_ROOT`. Scripts that source siblings via `dirname "$0"` are
likewise untouched.

## Rationale
The flow "didn't work" on Copilot because the plugin's entire script layer hung on
`${CLAUDE_PLUGIN_ROOT}`, and empirical in-command probing (via a throwaway-then-kept `/aind:env-probe`)
showed the mechanism is host-specific in a way the prior notes got wrong:

- On **Claude Code**, `${CLAUDE_PLUGIN_ROOT}` is **not an environment variable** — a bare
  `$CLAUDE_PLUGIN_ROOT` inside bash reads empty even mid-command. It is a **string macro** the Bash
  tool substitutes into the command text (confirmed: the braced token at top level *and* nested
  inside a single-quoted `bash -c` both resolved to the real dir; the unbraced env reference did
  not).
- On **Copilot CLI**, the shell tool is PowerShell, which performs **no** such substitution and
  exposes **no** plugin-root variable at all (only `COPILOT_AGENT_SESSION_ID` / `COPILOT_CLI` /
  `COPILOT_CLI_BINARY_VERSION` / `COPILOT_LOADER_PID`). So `bash "${CLAUDE_PLUGIN_ROOT}/scripts/…"`
  became `bash "/scripts/…"` → not found; the agent then silently reimplemented phases in PowerShell
  (observed: a plan phase that hand-wrote `plan.md` and skipped the PR/threads/tagging entirely).

The earlier lesson *"`${CLAUDE_PLUGIN_ROOT}` works under Copilot"* was true only for the **hook env**
(hooks are a separate spawn Copilot does populate) and was wrongly generalised to the command path.
It looks like a Copilot regression and/or a hook-vs-shell conflation — either way the fix must not
depend on any injected variable in the shell path.

Options weighed:
- **Env-var only** (set `CLAUDE_PLUGIN_ROOT`/`AIND_PLUGIN_ROOT` in the user's profile): rejected as
  the *sole* mechanism — brittle per-machine, breaks on reinstall/version change, and doesn't fix the
  PowerShell `${…}`/redirection mis-parse. Kept only as the optional override (step 2).
- **Per-host branching in each command** (two invocation forms): rejected — violates the single
  behavior layer (D22) and doubles the maintenance surface.
- **A shim on PATH**: rejected — adds install/setup burden and a PATH-ordering trap of its own.
- **Self-location keyed on the repo-name glob**: accepted as the portable core. The glob hardcodes
  the plugin's *own* repo name (`ai-native-dev`), which is plugin-identity, not consumer-project
  configuration, so it stays within the "no project-specific values" rule. Robustness rests on the
  empirically-confirmed install layout; `$AIND_PLUGIN_ROOT` is the escape hatch for anything exotic.

This is a script-invocation-mechanics change on the D22 agent-host axis (orthogonal to D36's code
host and D46's tracker). It touches no flow node, status, gate, or PR contract.
