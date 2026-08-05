---
description: Diagnostic — how this host resolves the plugin root, and whether the portable resolver works (dual-host).
argument-hint: "[probe-arg]"
allowed-tools: Bash
---

# /env-probe — plugin-root resolution diagnostic

A **keep-around** diagnostic. Claude Code and GitHub Copilot CLI resolve the plugin's script
directory by different mechanisms, and those mechanisms have changed between CLI versions. Run
this on **each host** after a CLI upgrade (or when scripts stop resolving) to see, from *inside a
running command*, exactly what works.

Key facts it verifies (measurement only — it changes nothing):

- On **Claude Code**, `${CLAUDE_PLUGIN_ROOT}` is a **command-string macro** the Bash tool
  substitutes before running — it is *not* an environment variable a child process can read.
- On **Copilot CLI**, the shell tool is **PowerShell**, which performs **no** such substitution
  and exposes **no** plugin-root variable — so `${CLAUDE_PLUGIN_ROOT}` blanks to empty and a bare
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/…"` invocation fails.
- The **portable resolver** (test 4) reconciles both: it takes the macro as a top-level positional
  arg (works on Claude, safely empty on Copilot) and self-locates the install dir when that's empty.

## Procedure

Run each of the following as its own Bash tool call, **verbatim**, and report the **raw output of
every call** with no summarising or reformatting. Each is fully wrapped so PowerShell (Copilot)
cannot mangle redirections or expansions.

**[1] Are any plugin-root values environment variables in bash?**
```
bash -c 'echo "[1] bash-env: CLAUDE=[$CLAUDE_PLUGIN_ROOT] COPILOT=[$COPILOT_PLUGIN_ROOT] PLUGIN=[$PLUGIN_ROOT] AIND=[$AIND_PLUGIN_ROOT]"'
```

**[2] Is the macro substituted when the token sits at the top level of the command?**
```
echo "[2] top-level-macro=[${CLAUDE_PLUGIN_ROOT}]"
```

**[3] Is the macro substituted when the token is nested inside a single-quoted `bash -c`?**
```
bash -c 'echo "[3] nested-macro=[${CLAUDE_PLUGIN_ROOT}]"'
```

**[4] Does the candidate portable resolver find the scripts dir?** (top-level macro → positional
arg `$1`; falls back to `AIND_PLUGIN_ROOT`, then self-locates the install dir):
```
bash -c 'R="$1"; [ -d "$R/scripts" ] || R="${AIND_PLUGIN_ROOT:-}"; up="$(cygpath -u "${USERPROFILE:-$HOME}" 2>/dev/null)"; [ -d "$R/scripts" ] || R="$(ls -d "$up"/.copilot/installed-plugins/*/*ai-native-dev "$up"/.claude/plugins/*/*ai-native-dev 2>/dev/null | head -1)"; if [ -f "$R/scripts/aind-common.sh" ]; then echo "[4] RESOLVER OK root=[$R]"; else echo "[4] RESOLVER FAIL root=[$R]"; fi' _ "${CLAUDE_PLUGIN_ROOT}"
```

**[5] Status-quo check — does the current shipping invocation form resolve?** (documents the
failure on Copilot):
```
bash -c 'f="$1/scripts/aind-common.sh"; [ -f "$f" ] && echo "[5] current-form OK: $f" || echo "[5] current-form FAIL: [$1]"' _ "${CLAUDE_PLUGIN_ROOT}"
```

**[6] Argument substitution — which macro does this host fill?** Run this command **with an
argument**, e.g. `/aind:env-probe probe-arg`. The command passes the `$ARGUMENTS` macro as bash `$1`
and the positional `$1` macro as bash `$2`, then echoes both:
```
bash -c 'echo "[6] ARGUMENTS=[$1] DOLLAR1=[$2]"' _ "$ARGUMENTS" "$1"
```

## How to read it

| Result | Claude Code (healthy) | Copilot CLI (healthy) |
|---|---|---|
| **[1] bash-env** | all `[]` — none are env vars | all `[]` — none are env vars |
| **[2] top-level-macro** | a real path (macro substituted) | `[]` (PowerShell blanks it) |
| **[3] nested-macro** | a real path *or* `[]` — tells us whether the macro survives nesting | `[]` |
| **[4] RESOLVER** | `OK` with a valid root | `OK` (via self-location) |
| **[5] current-form** | `OK` | `FAIL` — the reason the flow breaks on Copilot today |
| **[6] arg-macros** | `ARGUMENTS=[probe-arg] DOLLAR1=[probe-arg]` — both filled | `ARGUMENTS=[probe-arg] DOLLAR1=[]` — only `$ARGUMENTS` |

**[4] is the plugin-root pass/fail gate:** if it reports `OK` on *both* hosts, the portable resolver
is the fix to roll out across the commands. If [4] fails on a host, capture the raw output — the
combination of [2]/[3]/[5] on that host tells us which assumption broke (macro no longer substituted,
install path moved, etc.).

**[6] is the argument pass/fail gate:** it is why commands identify the work item with `$ARGUMENTS`
(filled by both hosts), never the positional `$1`/`$2` (Claude-only). If a host ever shows
`ARGUMENTS=[]`, argument passing on that host has changed — the commands would need re-checking.
