---
name: aind-preflight
description: Check the local environment for the AIND prerequisites (tools, auth, env vars, connectivity) and print a PASS/WARN/FAIL/MANUAL checklist. Use during onboarding or any time before running AIND commands to confirm setup.
allowed-tools: Bash
---

# AIND preflight check

Run the prerequisite probe. It is read-only and always exits 0 — it reports status, it does
not gate:

```bash
bash -c 'R="$1"; shift; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; "$R/scripts/aind-preflight.sh" "$@"' _ "${CLAUDE_PLUGIN_ROOT}"
```

It checks: required tools (`az`, `gh`, `git`, `curl`, `jq`, the azure-devops extension),
authentication (`gh`, `AZURE_DEVOPS_EXT_PAT`), the AIND env vars, and best-effort
connectivity to the GitHub repo and ADO org. Two prerequisites can't be auto-verified and are
listed as `[MANUAL]`: the Azure Boards ↔ GitHub integration and the integration
branch's "require conversation resolution" rule.

Config in `.claude/aind.env` is **auto-loaded** (walk-up from the working directory), so the
env-var and connectivity checks are meaningful without sourcing anything by hand. An
already-set environment (CI / parent shell) takes precedence.
