# Implementation plan — pluggable code host (Azure DevOps Repos)

Realises **D36**. Lets a project store its code, PRs, and PR comments in **Azure DevOps Repos**
as an alternative to GitHub, selected by `AIND_CODE_HOST`. This is a **script-only change**: a
forge-adapter layer absorbs the divergence, and `commands/`, `skills/`, and `agents/` stay
byte-for-byte unchanged.

> Dev doc (not shipped). Cites decision IDs freely, like `design-log.md` / `design-doc.md`.
> The shipped-artifact "no D-refs" guard does not apply here.

## Status (branch `feat/ado-code-host`)

- **Phase 1 — adapter + GitHub extraction: DONE.** `scripts/aind-forge.sh` created; all PR scripts
  refactored to source it and call the forge verbs; `aind_gh_signature` → host-aware
  `aind_pr_signature`; `aind_find_code_prs`/`aind_filter_code_prs` moved into the adapter. GitHub
  path is the extracted-verbatim `_gh_*` impls (behaviour unchanged).
- **Phase 2 — ADO implementations: DONE (offline).** `_ado_*` for every verb (REST + `az repos pr
  work-item add`); local-git-diff for `forge_pr_diff`; ADO carrier defaults per the spikes below.
  All `bash -n` clean; the `aind_filter_code_prs` filter and every ADO `jq` program validated
  against sample JSON.
- **Phase 3 — config/preflight: DONE for env + preflight.** `AIND_CODE_HOST`/`AIND_ADO_REPO` in
  `aind-common.sh`, `aind.env.sample`, `project-template/CLAUDE.md`; `aind-preflight.sh` is
  host-conditional. **Remaining:** have `/aind:onboard` + `/aind:kickstart` *ask* which code host
  and write `AIND_CODE_HOST` (prompt-file edits).
- **Phase 0 (spikes) + Phase 4 (docs) + Phase 5 (E2E): pending your live ADO validation.** The ADO
  carrier defaults (signature span, AIND-LINKS HTML comment, thread anchoring offset 1, resolve
  status `fixed`) are marked in-code and adjusted after the spikes.

---

## 1. Goal & non-goals

**Goal.** A project sets `AIND_CODE_HOST=ado` (+ `AIND_ADO_REPO`) and runs the *entire* flow —
plan PR, assumption threads, code PR, cold-review loop, revise loops, complete/merge gate, and the
dreaming config PR — against ADO Repos, with the same commands, prompts, status model, and gates as
the GitHub path.

**Non-goals (this iteration).**
- No change to the flow: status model (D4), gates, plan-PR/assumption-thread contract (D5/D10),
  artifact-linking contract (D17) are untouched.
- No new identity/secret story — ADO reuses the existing `AZURE_DEVOPS_EXT_PAT` (the service-identity
  question stays deferred, D6/Q7).
- No migration of an in-flight story between hosts. `AIND_CODE_HOST` is a per-project setting fixed
  at onboarding.
- Not the *agent* host axis (D22, Claude vs Copilot). See §9 terminology guard.

---

## 2. Guiding constraints

1. **Git is already host-neutral.** ADO Repos is plain git; every `git` operation the flow performs
   works against an ADO `origin` unchanged. Only the **PR/comment API layer** (`gh` + GraphQL) needs
   an ADO twin. Do **not** reimplement branch/checkout/push/fetch/cleanup per host.
2. **One adapter, thin wrappers.** All host divergence lives in a new `scripts/aind-forge.sh`. Every
   existing PR script becomes a thin caller of its verbs. No `case $host` scattered across scripts.
3. **Opaque tokens.** The PR identifier and the review-thread id that cross the script↔command/agent
   boundary (`digest` output, `thread=<id>`, the PR "number") must stay opaque strings. The reviewer
   and coder prompts must not learn which host they run on.
4. **Spikes are validated live, not guessed.** Three questions (§7) are answered by a real ADO run
   during the build, per the plugin's "trust a live run over docs" rule (D22).
5. **Portability preserved.** No org/project/repo values in code — all via env / `.claude/aind.env`.

---

## 3. The forge interface (`scripts/aind-forge.sh`)

Sourced like `aind-common.sh`. Dispatches each verb on `AIND_CODE_HOST` to `_gh_<verb>` or
`_ado_<verb>`. Verbs (proposed signatures — refine as the ADO impls land):

| Verb | Inputs | Output contract (host-agnostic) |
|------|--------|---------------------------------|
| `forge_pr_create` | base, head, title, body-file, work-item-id | prints PR URL; links the work item |
| `forge_pr_list` | filter (head/state/all) | TSV rows: `state \t id \t url \t head \t title \t body` (newlines escaped) |
| `forge_pr_view` | pr-id, field-set | requested fields (title/body/state/headRef/headSha/mergeCommit) as TSV or lines |
| `forge_pr_diff` | pr-id | unified diff on stdout |
| `forge_pr_edit_body` | pr-id, body-file | replaces PR body |
| `forge_comment` | pr-id, agent, body | posts a top-level PR comment (signed) |
| `forge_thread` | pr-id, path, line, agent, body | posts one **resolvable inline** thread anchored to file:line (signed); prints the opaque thread id |
| `forge_thread_list` | pr-id | per-thread: `state(OPEN/RESOLVED) \t thread=<opaque> \t path:line \t comments…` |
| `forge_resolve` | pr-id, thread-id | marks the thread resolved |
| `forge_reply` | pr-id, thread-id, agent, body | replies on a thread (signed); does **not** resolve |

**State normalisation.** The adapter maps host states to a canonical vocabulary the callers already
use: `OPEN` / `MERGED` / `CLOSED` for PRs, `OPEN` / `RESOLVED` for threads. ADO `completed`→`MERGED`,
`active`→`OPEN`, `abandoned`→`CLOSED`; thread `active`→`OPEN`, `fixed`/`closed`→`RESOLVED` (exact
mapping pinned by spike §7.3).

**`forge_pr_diff` on ADO.** `az repos pr` has no clean single-call diff. Preferred implementation:
compute locally — `git fetch` the PR's source+target refs and `git diff <mergeBase>...<headSha>`
(the reviewer already runs in a git checkout). Fallback: the REST iterations/changes API. Decide in
Phase 2; local git diff is the low-dependency default.

---

## 4. Consumer inventory (what becomes a thin wrapper)

Every GitHub-coupled site today, and the verb it moves to:

| Script | `gh` operations today | Moves to |
|--------|-----------------------|----------|
| `aind-common.sh` `aind_find_code_prs` | `gh pr list --json` | `forge_pr_list` (filter logic `aind_filter_code_prs` stays host-agnostic) |
| `aind-common.sh` `aind_gh_signature` | marker only (no call) | rename → `aind_pr_signature`, host-aware carrier |
| `aind-open-plan-pr.sh` | `gh pr list`, `gh pr create` | `forge_pr_list`, `forge_pr_create` |
| `aind-open-code-pr.sh` | `gh pr list`, `gh pr create` | `forge_pr_list`, `forge_pr_create` |
| `aind-review-pr.sh` | `gh pr view/diff/comment`, GraphQL reviewThreads/resolve/reply | `forge_pr_view/diff/comment`, `forge_thread_list/resolve/reply` |
| `aind-thread.sh` | `gh pr view headRefOid`, `gh api pulls/.../comments` | `forge_thread` |
| `aind-revise-plan-pr.sh` | `gh pr list/view/comment`, GraphQL reply | `forge_pr_list/view/comment`, `forge_reply` |
| `aind-revise-code-pr.sh` | `gh pr view/comment/edit` | `forge_pr_view/comment/edit_body` |
| `aind-complete.sh` | `gh pr view` (MERGED), `gh pr list` (via helper) | `forge_pr_view`, `forge_pr_list` |
| `aind-dream.sh` (`start`/`open-pr`) | `gh` config-PR opener | `forge_pr_create` (the `.claude` PR also lives on the chosen host) |
| `aind-preflight.sh` | `gh` presence/auth/repo checks | host-conditional (§6) |
| `aind-links.sh` | none (builds `AIND-LINKS` HTML comment) | carrier depends on spike §7.1 |

---

## 5. ADO API mapping reference

Reuses `AZURE_DEVOPS_EXT_PAT`. Base REST: `{AIND_ADO_ORG}/{AIND_ADO_PROJECT}/_apis/git/repositories/{AIND_ADO_REPO}/…?api-version=7.1`.

| Verb | ADO mechanism |
|------|---------------|
| create PR | `az repos pr create --repository <repo> --source-branch <head> --target-branch <base> --title … --description … --work-items <id>` (native link) |
| list PRs | `az repos pr list --repository <repo> --status all` (map JSON shape → the TSV contract) |
| view PR | `az repos pr show --id <pr>` (`status`, `lastMergeSourceCommit`, `lastMergeCommit`, `sourceRefName`) |
| diff | local `git diff <mergeBase>...<headSha>` (preferred) or REST `…/pullRequests/{id}/iterations/{n}/changes` |
| edit body | `az repos pr update --id <pr> --description …` |
| top-level comment | REST `POST …/pullRequests/{id}/threads` with a comment, no `threadContext` |
| inline thread | REST `POST …/pullRequests/{id}/threads` with `threadContext.filePath` + `rightFileStart/End` (spike §7.2) |
| resolve | REST `PATCH …/threads/{threadId}` `status: fixed`/`closed` (spike §7.3) |
| reply | REST `POST …/threads/{threadId}/comments` |

The ADO thread id is an integer; the opaque token is `threadId` (comment replies target the thread,
not a node id). `forge_thread`/`forge_thread_list` emit it as the same `thread=<opaque>` string the
GitHub path emits, so callers are unchanged.

---

## 6. Config, env, preflight

- **`aind-common.sh`**: add `AIND_CODE_HOST` (default `github`) resolution; `AIND_ADO_REPO`. Keep
  `AIND_GH_REPO` for the github path.
- **`project-template/aind.env.sample`**: document `AIND_CODE_HOST`, `AIND_ADO_REPO`; note
  `AIND_GH_REPO` is github-only.
- **`aind-preflight.sh`**: branch on `AIND_CODE_HOST`.
  - `github`: existing `gh` presence/auth/repo checks.
  - `ado`: `az` + the `azure-devops` extension present; PAT has **Code (r/w)** scope; the repo is
    reachable (`az repos show`); the integration branch exists.
- **`/aind:onboard` (D18) & `/aind:kickstart` (D31)**: ask which code host, write `AIND_CODE_HOST`
  (+ the matching repo var). For ADO, note the native work-item linking needs no extra app; for
  GitHub, keep the Azure Boards↔GitHub integration prerequisite (D17).

---

## 7. Open spikes — validate live during the build

Each is cheap and decisive. Run against a throwaway ADO repo + a test work item.

### 7.1 Does ADO PR markdown preserve HTML comments? *(highest priority — blocks two features)*
- **Test:** open an ADO PR whose description contains `<!-- AIND-LINKS … -->` and post a thread
  containing `<!-- AIND-AGENT: reviewer -->`. Re-fetch both via REST/`az`; check the stored text.
- **Drives:** the ADO carrier for the D29 signature marker **and** the D17 `AIND-LINKS` block.
  - Preserved → reuse the GitHub HTML-comment carrier verbatim.
  - Stripped → switch ADO to the `display:none` span (as D3 uses in ADO work-item fields) or a
    fenced-code marker; `aind-links.sh` and `aind_pr_signature` branch on host.

### 7.2 Inline-thread anchoring semantics
- **Test:** post a resolvable thread on a specific `file:line` of the diff; confirm it lands on the
  right line and survives a new push (head-SHA re-anchor, mirroring `aind-thread.sh`).
- **Drives:** whether line-only anchoring suffices or `rightFileStart.offset` is required.

### 7.3 Thread-status mapping for the "resolve before merge" gate (D5)
- **Test:** create a thread, resolve it via `status: fixed` and via `status: closed`; confirm which
  ADO branch policy ("all comments resolved") accepts as resolved, and that an OPEN thread blocks
  completion.
- **Drives:** the `active/fixed/closed` ↔ `OPEN/RESOLVED` map and the ADO equivalent of GitHub's
  "require conversation resolution before merging" repo setting (a named prerequisite, like D5's).

---

## 8. Phased task breakdown (dependency-ordered)

**Phase 0 — Spikes (de-risk first).** Run §7.1–7.3 against a scratch ADO repo. Record findings in
this file. Gate: carrier + anchoring + status mapping decided before writing `_ado_*`.

**Phase 1 — Adapter skeleton + GitHub extraction (no behaviour change).**
- Create `scripts/aind-forge.sh` with the §3 verbs; move today's `gh` code into `_gh_*` verbatim.
- Rewrite the §4 scripts to call the verbs (github path only). Rename `aind_gh_signature` →
  `aind_pr_signature`.
- Validate: full GitHub flow still passes (`bash -n` all scripts; re-run the offline unit checks for
  `aind_filter_code_prs`; live-run one GitHub story plan→complete). **Zero prompt/command change.**

**Phase 2 — ADO implementations.**
- Implement `_ado_*` for each verb using §5 + the Phase-0 decisions. `forge_pr_diff` via local git
  diff. Host-aware carrier in `aind-links.sh` / `aind_pr_signature`.
- Validate each verb in isolation against the scratch repo (create → list → view → thread → reply →
  resolve → diff → merge-detect).

**Phase 3 — Config, preflight, onboarding.**
- `AIND_CODE_HOST`/`AIND_ADO_REPO` in `aind-common.sh` + env sample; host-conditional preflight;
  onboarding/kickstart prompts (§6).

**Phase 4 — Docs.**
- `design-doc.md`: reframe "GitHub PR" → "code-host PR"; add a short "code host" glossary entry;
  guard the D22 vs D36 terminology (§9). `docs/index.html` diagram labels host-neutral where they
  say GitHub. `README.md` / `GETTING-STARTED.md`: document `AIND_CODE_HOST` and the ADO setup path
  (PAT Code scope, branch policy for comment resolution).

**Phase 5 — End-to-end live validation (ADO).** Run a real story on `AIND_CODE_HOST=ado`:
plan PR + assumption threads → approve-plan (merge gate) → implement → cold-review loop (findings as
resolvable ADO threads, coder rebuts) → revise loop → complete (MERGED verify + terminal tag) →
`/aind:dream` config PR. Confirm signing markers are attributable and `AIND-LINKS` resolves.

---

## 9. Terminology guard

Two orthogonal axes, four combinations:

|                     | Code host: GitHub | Code host: ADO |
|---------------------|-------------------|----------------|
| **Agent host: Claude Code** (D22) | supported today | target of D36 |
| **Agent host: Copilot CLI** (D22) | supported today | should work (scripts are agent-host-agnostic) |

Never write "dual-host" unqualified. Say **agent host** (Claude/Copilot) or **code host / forge**
(GitHub/ADO).

---

## 10. Definition of done

- [ ] Phase-0 spike findings recorded here; carrier/anchoring/status decisions made.
- [ ] `scripts/aind-forge.sh` exists; all §4 sites call verbs; no `gh`/`az repos` calls outside the
      adapter (`grep -rn 'gh pr\|gh api\|az repos' scripts | grep -v aind-forge.sh` → empty).
- [ ] GitHub path unchanged and re-validated (offline unit checks + one live story).
- [ ] ADO path passes the Phase-5 end-to-end story.
- [ ] Opaque-token discipline holds — no command/agent prompt references a host (`grep -rniE 'github|gh pr|\bgh\b' commands agents skills` → only host-neutral/legacy mentions triaged).
- [ ] Preflight, env sample, onboarding/kickstart cover both hosts.
- [ ] Docs reframed; D22/D36 terminology guard applied.
- [ ] Shipped-artifact guard still clean: `grep -rnE 'design-log|\bD[0-9]+\b' commands skills agents scripts hooks rubric project-template` → empty.

---

## 11. Risks & watch-items

- **HTML-comment stripping (§7.1)** is the load-bearing unknown — de-risk in Phase 0.
- **Self-review on ADO:** GitHub refused a self-approval, so the reviewer posts a plain comment and
  the loop is driven by the returned verdict (D26). Confirm the ADO path likewise never depends on a
  formal "approve" the same identity can't give.
- **Signing enforcement parity:** GitHub PR signing is convention-only (no PreToolUse hook, D29);
  ADO inherits the same gap. If a hook is wanted, it must catch raw `az repos pr … thread` calls the
  way `check-claude-comment.sh` catches raw work-item comments (follow-up, not blocking).
- **`az repos` diff ergonomics** — favour local git diff to avoid the iterations/changes API.
- **Windows/MSYS UTF-8** — ADO REST bodies must go via temp file + `--data-binary` +
  `charset=utf-8`, exactly as `aind-comment.sh` already does.
