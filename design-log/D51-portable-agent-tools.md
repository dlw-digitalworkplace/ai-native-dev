# D51 — Portable subagent tool names across agent hosts

- **Area:** Cold-subagent tool declarations / dual-host packaging (the D22 *agent-host* axis; agent-frontmatter only, does not touch the flow, status model, gates, or PR contract of D1–D15). Sibling of D49/D50.
- **Date:** 2026-08-05
- **Status:** Active

## Decision
The two cold subagents (`agents/reviewer.md`, `agents/dreamer.md`) declare their `tools:` as a
**cross-host union** of Claude tool names and Copilot tool aliases, so each host grants the subagent
a working command-execution (shell) tool:

- `agents/reviewer.md`: `tools: execute, read, search, Bash, Read, Glob, Grep`
- `agents/dreamer.md`: `tools: execute, read, search, edit, Bash, Read, Glob, Grep, Edit, Write`

Copilot recognises `execute` (its primary shell alias), `read`, `search`, `edit`; Claude recognises
`Bash`, `Read`, `Glob`, `Grep`, `Edit`, `Write`. **Unrecognised tool names are ignored on both
hosts**, so the single union list resolves to the right set on each. The reviewer is granted **no**
edit tool on either host (no `edit`/`Edit`/`Write`), and keeps `disallowedTools: Edit, Write` —
coldness (it never authors fixes) is preserved.

## Rationale
On Copilot CLI, `/aind:implement` ran to the review phase and the cold reviewer subagent returned
`CANNOT-REVIEW`: *"no Bash/command-execution tool is available in this session"* — so it could not
run `aind-review-pr.sh` to fetch/ground the PR, post threads, or leave a summary. The coder then
correctly fell to the stuck-path (`Needs attention` + a signed trail — the flow degraded safely).

Root cause: the subagent's `tools:` named the shell as `Bash`, a **Claude** tool name. On Copilot
the shell tool's primary alias is **`execute`** (GitHub's custom-agents reference lists `shell` /
`Bash` / `powershell` as compatible alternatives, but the CLI build under test did not honour `Bash`
as an execute alias). Copilot **strictly enforces a subagent's `tools:` allowlist** — so the
unrecognised `Bash` granted nothing and the reviewer was spawned with only the read tools
(`Read`/`Glob`/`Grep` → `view`/`rg`/`glob`, which it did use for 30 read-only calls) and no shell.

Why only subagents broke: Copilot does **not** strictly restrict a **top-level command** to its
`allowed-tools`, so the coder (`/aind:implement`) got a shell despite the same `Bash` name; it
enforces the restriction only for spawned subagents. So the coder worked and only the cold reviewer
(and, by the same defect, the dreamer) lacked a shell.

Options weighed:
- **Replace `Bash` with `execute` only** — rejected: would strand Claude, whose shell tool is
  `Bash`, not `execute`.
- **Drop the `tools:` restriction entirely** (inherit all tools) — rejected for the reviewer:
  the restriction is what keeps the cold reviewer from gaining `Edit`/`Write` (its coldness is the
  point of the gate). A union list keeps the explicit no-author guarantee on both hosts.
- **Per-host agent files** — rejected: violates the single behavior layer (D22) and doubles the
  maintenance surface, exactly as for D49/D50.

Distinct from D49 (plugin-root resolution) and D50 (command arguments): those fixed the
command→shell path; this fixes the **subagent tool grant**. Same D22 agent-host axis; touches no
flow node, status, gate, or PR contract. Validate empirically on Copilot after any CLI upgrade —
tool-alias handling has shifted between versions.
