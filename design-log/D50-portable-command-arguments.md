# D50 — Portable command arguments across agent hosts

- **Area:** Slash-command argument passing / dual-host packaging (the D22 *agent-host* axis; command-prompt only, does not touch the flow, status model, gates, or PR contract of D1–D15). Sibling of D49.
- **Date:** 2026-08-05
- **Status:** Active

## Decision
Commands stop identifying the work item (and other user arguments) with the positional macro `$1`
(and `$2`), and use **`$ARGUMENTS`** — the whole raw argument string — instead. `$ARGUMENTS` is
substituted by **both** Claude Code and GitHub Copilot CLI; positional `$1`/`$2` are a **Claude-only**
macro that Copilot leaves empty.

Two shapes, by how many arguments a command takes:

1. **Single-argument / free-text commands** (`/aind:intake`, `/aind:approve-plan`,
   `/aind:implement`, `/aind:map-states`; `/aind:research` and `/aind:new-item` already used
   `$ARGUMENTS`): the macro `$1` is replaced verbatim by
   `$ARGUMENTS` in prose and in the resolver's trailing args. For a one-argument command
   `$ARGUMENTS` ≡ `$1` on Claude, so this is a **no-op on Claude** and a fix on Copilot. The
   bash-internal `R="$1"` of the D49 resolver is **left untouched** — that is bash's own positional
   (the plugin root), not the command macro.

2. **Two-positional commands** (`/aind:plan <id> [attended|headless]`, `/aind:complete <id>
   [pr-number]`): a naïve `$1`→`$ARGUMENTS` swap would break the two-argument case on *both* hosts
   (`$ARGUMENTS`="19 headless" → `plans/19 headless/plan.md`). These derive the tokens **inside the
   resolver** from the single `$ARGUMENTS` string, which carries *all* the arguments on both hosts:

   ```bash
   bash -c 'R="$1"; shift; A="$1"; shift; …self-locate…; "$R/scripts/aind-<name>.sh" … "${A%% *}" …' _ "${CLAUDE_PLUGIN_ROOT}" "$ARGUMENTS"
   ```

   - `A` is the raw argument string; `${A%% *}` is the **work-item id** (first whitespace token).
   - `/aind:complete verify` additionally computes the optional PR number as the second token
     (`P="${A#* }"; [ "$P" = "$A" ] && P=""`).
   - `/aind:plan`'s run-mode word is prose-only (never passed to a script); the command reads it from
     `$ARGUMENTS` and the `aind-planmode.sh` call takes no id (a plain no-id resolver).
   - Prose paths use a `<id>` placeholder, defined once at the top as "the first whitespace token of
     `$ARGUMENTS`", so the authoring agent writes `plans/<id>/plan.md` correctly on either host.

Deliberate properties:

- **Permission allowlist preserved.** The extraction adds `A="$1"; shift;` *after* the D49 prefix
  `R="$1"; shift;`, so every call still matches the single rule
  `Bash(bash -c 'R="$1"; shift;*)`. Nothing else about D49 changes.
- **No regression on Claude.** Single-arg swaps are value-identical; the two-arg extraction yields
  the same id/pr Claude's `$1`/`$2` did, for both one- and two-argument invocations.
- **`/aind:env-probe` gains an argument test** (`[6]`) as the permanent dual-host validator for this
  axis, mirroring D49's `[4]` for plugin-root resolution.

## Rationale
After D49 fixed *plugin-root* resolution on Copilot, `/aind:implement 1` still failed there: the
work item never reached the command. The transcript showed the resolver invoked with an empty id
(`aind-revise-code-pr.sh "" status`) and the body rendered `Work item: ****` — i.e. the `$1` macro
blanked. Claude Code substitutes positional `$1`/`$2` **and** `$ARGUMENTS`; Copilot CLI (codex-based
prompt expansion) substitutes only `$ARGUMENTS` (the raw text after the command name). So every
argument-taking command was broken on Copilot, not just `implement` — they all keyed off `$1`.

`$ARGUMENTS` is the one token both hosts fill, which is why it is the portable choice; and because it
carries the *entire* argument string identically on both hosts, deriving positional tokens from it
in-shell (`${A%% *}`, `${A#* }`) is host-agnostic — no per-host branching, consistent with the single
behavior layer (D22). Live-validated: `/aind:implement 1` confirmed working on **both** Claude Code
and Copilot CLI before the fix was rolled across the remaining commands.

This is a command-prompt change on the D22 agent-host axis (orthogonal to D36's code host and D46's
tracker). It touches no flow node, status, gate, or PR contract.
