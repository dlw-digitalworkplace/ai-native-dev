# D54 — Usage-telemetry session-file resolution hardened (exhaustive slug class + a bounded multi-line `cwd` scan)

- **Area:** Per-phase usage telemetry on the Claude agent host (fixes D42's collector; touches `aind-usage.sh`'s `_claude_file` only)
- **Date:** 2026-09-04
- **Status:** Active

## Decision
**The Claude transcript slug is now derived with the host's own rule — every character outside `[a-zA-Z0-9]` becomes one `-` — and the slug-independent `cwd` fallback scans a bounded window of records instead of only the first line. Either bug alone silenced telemetry entirely for an affected repo, and the second was the safety net that should have absorbed the first.**

Reported symptom: in a project named `AI.TranslatorAgent`, every phase ended with
`no session events file found for this repo (host may not expose usage) — telemetry skipped`,
despite `telemetry.enabled: true`. The host *was* exposing usage — the transcript existed and carried
36 records with `output_tokens` inside that phase's window. Consequence: no token-breakdown attachment
and no duration accumulation for **any** phase in that repo, and silently, because telemetry is
best-effort by design (warn and return 0, never fail a phase).

**Bug 1 — the slug transform under-replaced.** It mapped only `:`, `\` and `/` to `-`, so a repo path
containing any *other* non-alphanumeric character produced a directory name that does not exist:

```
repo root       : /c/Users/<u>/source/repos/<org>/AI.TranslatorAgent
computed (old)  : C--Users-<u>-source-repos-<org>-AI.TranslatorAgent   <- no such dir
actual on disk  : C--Users-<u>-source-repos-<org>-AI-TranslatorAgent
```

The `[[ -d "$dir" ]]` guard then failed and the fast path was skipped. **Widening the class to the
reported `.` would have been an under-fix:** on the machine where this was diagnosed, three of eight
real project directories were unresolvable — the dot repo, a repo with a **space** in its name
(`AI Sales Agents`), and one with **both** (`DLWR.DataSync internship`). So the class is deliberately
the **negated alphanumeric set**, not an enumerated list of separators, and must stay that way.

**Bug 2 — the `cwd` fallback only ever read line 1.** It extracted `.cwd` with `head -n1 | jq`, but a
session's opening record is a `mode` record that carries no `cwd`; the first record that does sits a
few lines in (measured at lines **3–13** across 47 live transcripts). So the fallback matched nothing,
for every candidate, always. It now reads a bounded prefix of each file and takes the first record
carrying a `cwd`.

Two smaller pieces ride along, both in service of the same failure mode:

**Slug length cap.** The host truncates a slug over 200 characters and appends a hash of its own. That
hash is not reproducible here, so an over-long slug is matched on its surviving 200-character
**prefix** (newest transcript wins), with the `cwd` scan still behind it.

**A diagnosable warning.** The old text asserted `host may not expose usage`, which is what sent the
reported investigation after the host instead of our own resolver. That hypothesis is now stated only
when neither agent host has a session store at all; otherwise the warning names the checkout and the
exact directory that was searched. Still one line, still best-effort.

## Rationale
The load-bearing choice is **encoding the host's rule rather than the reported symptom**. The rule was
read out of the shipping host binary — `k(e) = e.replace(/[^a-zA-Z0-9]/g,"-")`, wrapped by a
200-character cap with a hash suffix — and then differentially tested against a direct execution of
that same expression over 400 randomised paths, so the transform is faithful by construction instead
of by enumeration of the separators someone happened to hit. That matters because the failure is
**silent**: a repo whose name contains a character nobody thought to list loses telemetry with no
signal beyond a warning that blames the host.

Keeping the `cwd` scan **bounded** is the counterweight. It is the slug-independent net that catches
everything the transform can't reproduce — the truncated-and-hashed long slug, non-ASCII (the host
counts UTF-16 units where `sed` here substitutes per byte), and any future drift in the host's
internal naming — so it must actually work; but it runs once per candidate session file and transcript
lines are individually large, so it cannot read whole files. A ceiling at 40 records is ~3× the deepest
`cwd` observed on a live machine, which buys headroom without turning the net into a full scan.

Both fixes stay strictly inside file **resolution**. The telemetry data model is untouched — the
per-model map shape, the attachment format, the duration-field accumulation, and the phase mapping are
all as D42 left them — and the Copilot resolver is untouched, since it behaved correctly (it found no
match because the session genuinely was a Claude one). Telemetry remains best-effort: every new path
warns and returns 0, and the `set +e` discipline in `report` is preserved, so a resolution miss still
cannot fail a phase or move a work item's status.

## Status / validation
Offline-validated (`bash -n` clean across `scripts/` and `hooks/`; the repo runs no shellcheck):

- **Slug table, asserted against real directory names** harvested from a live `~/.claude/projects`
  paired with the `cwd` recorded inside each transcript — the dot repo, a plain name, a name with
  spaces, one with both, existing hyphens preserved, plus a POSIX `/home/u/src/repo` root
  (`cygpath` absent → `-home-u-src-repo`) and the runs-not-collapsed case (`C:\a\b` → `C--a-b`).
  10/10, and each expected slug confirmed to be an existing directory.
- **Differential test against the host's own rule:** 400 randomised paths through both the shipping
  `replace(/[^a-zA-Z0-9]/g,"-")` and the `sed` transform — byte-identical.
- **Resolver paths, 8/8:** dot-in-name resolves via the slug dir; `cwd` on line 5 and on line 13 found
  by the fallback; `cwd` past the scan ceiling correctly *not* matched (the bound is real); a
  never-carries-`cwd` 5000-line transcript not matched and not fully read; a foreign `cwd` not matched;
  a plain repo name still resolving (regression); an absent `projects/` dir failing cleanly.
  A truncated-and-hashed >200-char slug is matched via the prefix glob.
- **Both warning branches** exercised (no store anywhere → the host hypothesis; store present but no
  match → the checkout and searched slug named).
- **Before/after on four real repos:** the base branch missed three of them (dot, space, dot+space)
  and resolved the fourth; the fix resolves all four — so the regression bar (no new misses) holds.
- **End-to-end** in the affected repo against a scratch `file` tracker (no live work item touched):
  `begin 999 intake` → work → `report 999 intake` wrote a real token breakdown attachment
  (`{"models":{"claude-opus-5":{"input":16,"output":6214,"cacheWrite":36116,"cacheRead":372041}}}`)
  and accumulated `durationSeconds: 3`, where the base branch emitted exactly the reported warning and
  wrote nothing.

**Not verified:** the ADO write path (attachment upload + numeric duration field) was exercised only
through the `file` tracker backend — reaching a live work item was deliberately avoided — and this fix
does not touch that code. Nothing was run on macOS/Linux or under Copilot CLI; POSIX behaviour is
covered only by the `cygpath`-absent slug case above, and the Copilot resolver is unchanged.
