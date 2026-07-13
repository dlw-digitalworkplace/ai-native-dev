# AI-native dev flow — Design Document

**Scope.** This document describes the **plan phase**, the **build phase**, and the **dreaming phase** of the flow — intake, planning, plan review, implementation, code review, how those steps are triggered and executed, and how the flow learns from its own exhaust to improve its agents. All three phases are **functionally designed**; phases that follow (deployment onward) are documented as they are decided. The rationale behind every choice recorded here is kept in the companion `design-log.md` (decisions D1–D36).

---

## 1. Overview

A **user story** is the unit of work. The flow has two linear, functionally designed phases — **plan** and **build** — plus a non-linear **dreaming phase** that runs alongside them and feeds improvements back into the agents.

The **plan phase** moves a story through three stages:

1. An **intake agent** checks the story is well-formed and ready to plan against.
2. A **planner agent** turns an approved story into an implementation plan, delivered as a GitHub pull request.
3. A **human** reviews and approves that plan.

It ends with an approved, merged plan — the item is `Ready for implementation`.

The **build phase** turns that plan into merged code:

1. A **coding agent** implements the spec — and, where the plan's test strategy calls for tests, authors them as it goes; a **polish agent** does in-context cleanup.
2. The coder gets the project's build **and** the tests it authored green, then opens a code PR. (Getting build + tests green before the PR is the flow's objective gate; any CI a project runs on the PR is the project's own concern, orthogonal to AIND.)
3. A **reviewer agent**, independent of the coder, reviews for spec alignment, missed edge cases, the cross-cutting concerns tests can't capture, **and the quality of the tests themselves** (do they cover the plan's must-cover cases, and do they assert the spec'd behavior rather than whatever the code happens to do); the two iterate in the PR, with a human breaking any deadlock.

It ends with a merged PR — the item is `Implementation complete`. Throughout both phases, a single `AIND status` tag on the Azure DevOps work item records where the item is, while the GitHub PRs own the fine-grained iteration.

Running alongside both phases is the **dreaming phase** — a non-linear, cross-story improvement loop. Each agent emits a structured *lessons-learned* record at the end of its session; on a regular basis a separate, independent **dreamer agent** reviews the accumulated lessons and proposes improvements to the agent-config layer (skills, agent prompts, the readiness rubric, project rules) as a pull request against `.claude`. A human accepts or rejects each proposal. This is the flow's feedback path: the rest of the flow turns stories into code, while the dreaming phase turns the experience of doing so into better agents — without ever changing the flow itself.

### Two independent axes: agent host and code host

The flow runs on two orthogonal, per-project choices — don't conflate them:

- **Agent host** — *where the agents run:* **Claude Code** or **GitHub Copilot CLI**. One behaviour layer, a per-host manifest + hook (see `design-log.md` D22).
- **Code host** — *where the code and its pull requests live:* **GitHub** or **Azure DevOps Repos**, selected per-project by `AIND_CODE_HOST` (default `github`; `AIND_GH_REPO` for GitHub, `AIND_ADO_REPO` for ADO). A thin **forge-adapter** in the scripts layer absorbs the difference; commands, agents, and skills are identical on both (see `design-log.md` D36).

Work items always live in **Azure DevOps** regardless of either choice. **This document says "GitHub PR" for brevity; read it as "the configured code host's pull request"** — the review surface, the assumption/review threads, the `AIND-LINKS` block, and the merge gate all work the same on GitHub and ADO Repos. The one host-appropriate detail is the machine-marker carrier (an HTML comment on GitHub; a hidden span on ADO) and the native work-item↔PR link (the Azure Boards ↔ GitHub integration for GitHub; ADO's built-in `--work-items` linking for ADO Repos).

---

## 2. Actors

| Actor | Type | Responsibility |
|---|---|---|
| Intake agent | Automated | Scores a story for readiness; records its reasoning as comments; suggests fixes but never edits the story itself. |
| Planner agent | Automated | Produces the implementation plan and opens it as a GitHub PR. |
| Coding agent | Automated | Implements the merged spec; authors the tests the plan's test strategy calls for, in-context; opens the code PR; applies fixes during review, including a human's verdict. |
| Polish agent | Automated | In-context (warm) cleanup before the PR — code style, formatting, self-consistency. Not an independent check, by design. |
| Reviewer agent | Automated | Cold, independent review of the code PR for spec alignment, missed edge cases, cross-cutting concerns (coding style, auth, logging), and **test quality** — that the tests cover the plan's must-cover cases and assert the spec'd behavior, not whatever the code does; re-grounded from artifacts only, never the coder's context. |
| Dreamer agent | Automated | Cold, independent. Runs in the dreaming phase on a regular cadence; reviews the *lessons-learned* records emitted by every other agent and proposes improvements to the agent-config layer as a PR against `.claude`. Re-grounded from the emitted lessons and artifacts only, never any agent's running context. Proposes only — a human accepts or rejects; bounded to config, never the flow itself (see §5 Dreaming phase). |
| Onboarding agent | Automated | One-time, pre-flow. Reads an existing codebase, discovers its domains, and **drafts** the initial `.claude/` config (per-domain project rules, a wired `CLAUDE.md`, project skills from discovered build/test/run commands, a seed-rubric copy), then reports the remaining setup prerequisites. Suggests only — a human reviews and edits the drafts; bounded to the config layer, never the flow (see §5 Onboarding and `design-log.md` D18). |
| Human reviewer | Person (developer / tech lead) | Authors and fixes the story; reviews and approves the plan; breaks a coder↔reviewer deadlock via PR comments; merges the code PR; reviews and accepts/rejects the dreamer's improvement PRs; reviews and edits the onboarding agent's drafted config. |

> **Emission (dreaming phase).** Every *automated* agent above carries one extra duty for the dreaming phase: at the end of its session it emits a structured *lessons-learned* record (what it tried, where it iterated, what it would do differently). This emission is *warm* — the agent reflecting on its own run — by design; the independence that matters lives in the **cold dreamer** that synthesises those records, not in the emission itself (see §5 Dreaming phase and `design-log.md` D16).

---

## 3. End-to-end flow

```mermaid
flowchart TD
    A([Story created]) --> B[Intake agent scores story]
    B -- not ready --> R1[Human edits story]
    R1 --> B
    B -- ready --> C[Planner drafts plan]
    C --> D[Plan opened as GitHub PR]
    D --> E{Human reviews plan}
    E -- plan gap --> F[Planner revises in PR]
    F --> E
    E -- story problem --> G[Close PR, reroute to intake]
    G --> B
    E -- approve --> H([Ready for implementation])
    H --> I[Coding agent implements spec + tests]
    I --> J[Polish agent cleans up in-context]
    J --> K[Coder opens code PR]
    K --> M{Reviewer agent reviews diff + tests}
    M -- comments --> N[Coder fixes or rebuts in thread]
    N --> M
    M -- unresolved after 3 passes --> O[Human posts verdict in PR]
    O --> P[Coder executes verdict]
    P --> Q[Final reviewer pass]
    Q --> Z([PR merged])
    M -- approve --> Z
```

The flow has three gates. **Intake** (an automated agent) sits at the front of the plan phase and scores the *story*. **Plan review** (a human) sits at the back of the plan phase and reviews the *plan*. **Code review** (an automated agent, with a human as tiebreaker) sits at the back of the build phase and reviews the *code*. Rejections route by root cause:

- A story that isn't ready returns to the author, who edits it and resubmits for scoring.
- A plan with gaps is revised by the planner inside the same PR.
- A story problem only surfaced once the plan exists sends the item all the way back to intake, and the plan PR is closed.
- Once the plan is approved and merged, the coding agent implements it — authoring the tests the plan's test strategy called for as it goes — the polish agent cleans up, and the coder opens a code PR only after getting the project's build **and** those tests green (that pre-PR check is the flow's objective gate; any CI a project runs on the PR is orthogonal to AIND). The cold reviewer agent then reviews the diff *and the tests*, and the coder and reviewer iterate in the PR until the reviewer is satisfied or a human breaks the deadlock — after which the PR merges.

---

## 4. AIND status model

A single `AIND status - <state>` tag on the work item is the source of truth for where an item sits in the flow.

**Invariant:** an item carries **exactly one** `AIND status` tag at any moment. Every transition removes the old tag and adds the new one as a single atomic change.

| Status | Set by | Meaning |
|---|---|---|
| `Ready for intake` | Human | Story is submitted (or resubmitted) for scoring. |
| `Intake declined` | Intake agent | Story isn't ready; the reasoning is in the work-item comments. |
| `Intake approved` | Intake agent | Story passed; planning may begin. |
| `Generating plan` | Planner agent | Planner is producing the plan (transient). |
| `Plan ready for review` | Planner agent | Plan PR is open and awaiting human review. |
| `Ready for implementation` | Human | Plan approved and merged; the plan phase is complete and the build phase may begin. |
| `In implementation` | Coding agent | Build is underway — implementation (including any tests the plan called for), polish, the code PR, and the review loop all happen here (transient/coarse). |
| `Needs attention` | Any stuck agent | An agent has **stopped because it cannot make progress** — planner can't produce a viable plan, coder can't get the tests passing, or an unresolvable merge conflict — after exhausting its retry cap. The trail (what was tried, why it's stuck) is in the work-item or PR comments. A human resolves the blocker and re-triggers the phase the item came from (see `design-log.md` D12). Distinct from a coder↔reviewer *disagreement*, which does **not** move the tag (D7). |
| `Implementation complete` | On merge (human-gated) | Code PR merged; the build phase is complete. In current (manual) scope a human merges after reviewer approval and a CLI command writes this tag as part of the same step — merge first, then tag (see `design-log.md` D13). |

```mermaid
stateDiagram-v2
    [*] --> Ready_for_intake
    Ready_for_intake --> Intake_approved: intake passes
    Ready_for_intake --> Intake_declined: intake fails
    Intake_declined --> Ready_for_intake: story edited
    Intake_approved --> Generating_plan: planner starts
    Generating_plan --> Plan_ready_for_review: PR opened
    Plan_ready_for_review --> Ready_for_implementation: human approves
    Plan_ready_for_review --> Ready_for_intake: story problem, PR closed
    Ready_for_implementation --> In_implementation: coder starts
    In_implementation --> Implementation_complete: PR merged
    Generating_plan --> Needs_attention: planner stuck (cap hit)
    In_implementation --> Needs_attention: coder stuck / merge conflict (cap hit)
    Needs_attention --> Generating_plan: human resolves, re-run plan
    Needs_attention --> In_implementation: human resolves, resume build
    Implementation_complete --> [*]
```

*(State names use underscores for the diagram; they map to the `AIND status - <state>` tags above.)*

Note the coarse/fine split: the work-item tag tracks the **coarse phase**, while the **GitHub PR** owns the fine-grained back-and-forth. In the plan phase, plan revisions requested during review happen inside the plan PR and **do not** change the status — the item stays `Plan ready for review`. The same split holds in the build phase: the code PR owns the entire coder↔reviewer iteration (and any human tiebreak), and none of it moves the tag — the item stays `In implementation` until the PR merges. This is why neither `Generating plan` nor `In implementation` has a return arrow *for ordinary iteration*: there are no PR-review sub-states mirrored into tags.

`Needs attention` is the one exception, and it is a different kind of transition — not iteration but **recovery**. An agent enters it only when it has *stopped and cannot proceed* (a stuck-state, per `design-log.md` D12), and it returns to whichever phase the item was stuck in once a human clears the blocker. This is deliberately separate from the coder↔reviewer disagreement case (D7): a disagreement keeps the agents *working* and never moves the tag, whereas `Needs attention` records that work has *halted*. So the two return arrows out of `Needs attention` represent human-driven recovery, not the automatic loop-backs the coarse/fine rule suppresses.

---

## 5. Phase detail

### Phase 0 — Intake

While a story is `Ready for intake`, the intake agent evaluates it against the readiness rubric and scores it. It records its reasoning as comments on the work item. It **suggests** improvements but does not edit the story — the human owns the story text.

The rubric lives in-repo at **`.claude/intake-rubric.md`** (checked out with the rest of the `.claude` config) and is **two-layer and hybrid** (see `design-log.md` D11):

- **Two layers.** The flow ships a seeded file containing a baked-in **core**; each project edits that file in place to add its own criteria — both objective and judgment — for project-specific needs (e.g. "touches payments → must cite the PCI checklist"). The core is a strong default but **not an enforced floor**: because it is a single editable file, a team can remove core items, and nothing structurally prevents that.
- **Hybrid scoring.** *Objective* criteria are pass/fail — any miss yields `Intake declined`. *Judgment* criteria are surfaced by the agent as advisory comments, not hard fails (consistent with the agent suggesting rather than authoring).

The baked-in core is:

| Type | Criterion |
|---|---|
| Objective (pass/fail) | Title present and non-trivial |
| Objective (pass/fail) | At least one acceptance criterion exists |
| Objective (pass/fail) | Intent is stated — user-story form *or* a clear problem/goal statement (the "As a…" form is not forced rigidly) |
| Objective (pass/fail) | No unresolved placeholders (`TODO`, `???`, `TBD`) in the body or ACs |
| Objective (pass/fail) | Dependencies/blockers are named, or explicitly declared "none" |
| Judgment (advisory) | ACs are testable/observable, not subjective ("works well", "fast enough") |
| Judgment (advisory) | Story is single-sized, not an epic in disguise |
| Judgment (advisory) | Story is internally coherent — title, intent, and ACs agree |
| Judgment (advisory) | Enough context for a planner to act on the *what* without guessing (the *how* is the planner's job) |

Beyond the rubric, intake runs a **dependency gate**: it resolves the story's linked ADO *Predecessor* work items (the stories it depends on) and declines the story if any of them is not implemented yet — a story is "implemented" when it carries the terminal `Implementation complete` AIND status, or (for a dependency not tracked by AIND) a done-like ADO state. This is a *command-level* gate, **not** a rubric criterion: it is orthogonal to the readiness score, so a perfectly-defined story can score 100 and still be declined solely because a story it depends on is unbuilt. It complements the rubric's objective criterion that dependencies be *named* — that catches a story which never declares its dependencies (a text gap the author fixes); the gate catches declared-and-linked dependencies that aren't *done* yet (a sequencing state that needs no story edit — the story becomes ready when the dependency lands and intake is re-run). See `design-log.md` D32.

The outcome is either `Intake approved` or `Intake declined`. A declined story is edited by the human and resubmitted as `Ready for intake`, which re-runs intake. The gate is unskippable: a fixed story always passes back through intake before planning.

### Phase 1 — Planning

When a story is `Intake approved`, the planner produces an implementation plan; status becomes `Generating plan` while it works. The plan is written as a markdown document at **`/plans/<work-item-id>/plan.md`** and delivered as **its own GitHub pull request, on its own branch, which merges to the project's integration branch before any code branch exists** — the PR is the review surface (inline comments, request-changes, revision diffs). The integration branch is whatever the project treats as its working trunk (`main`, `develop`, a `release/x.y` branch, etc.); the design fixes only that the plan merges there *first*, not the branch name. The plan is **not** co-developed on the same branch as the code; it is approved and merged first, then the build phase opens a separate code PR (see `design-log.md` D10). This keeps "the merged spec" a frozen, immutable artifact for the build phase's cold agents to re-ground from (§5, Phases 3–4). The merged plan stays in the repo as **permanent living documentation** next to the code it produced, not a throwaway. Once the plan PR is open, status becomes `Plan ready for review`.

The plan follows a fixed template designed to carry enough detail for a coding agent to execute without re-deriving the planner's decisions, while staying **domain-agnostic** — the planner never hardcodes a project's domains. Beyond **Context** and the recommended **Implementation approach**, the plan includes: a **Keep it simple** section stating explicit non-goals and the simpler option chosen over a heavier one (a guard against over-engineering — dropped when there is nothing to fence off); a conditional **Data contracts** section that, *only when the change crosses a boundary* (API↔client, service↔service, module↔module), pins the exact shape both sides must agree on — field names, types, nullability, and any mapping — in the project's own language(s); a **Task breakdown** as a dependency-ordered task list where **each task cites the project rule file(s) (`.claude/rules/*.md`) it must obey** rather than being filed under a fixed domain bucket, so the coder applies the right conventions and "done" bar per task (a task may cite more than one rule, e.g. a UI change that also touches a cross-cutting concern); a **Considerations** section of non-blocking reviewer context (security, performance, edge cases); and a **Definition of done** — a checklist whose every item traces to a real source (an acceptance criterion, a cited rule's "what done looks like" bar, an invariant, or a ratified testing recommendation) for the coder and reviewer to validate against. To ground all of this, the planner reads not just the project rules and code but also the project's **skills** and **`docs/`**, and respects a multi-project/deployment topology where the rules define one. Because the criteria and domains live in the project's rule files rather than the command, the same planner produces a single-domain plan for a small UI change and a multi-domain, contract-bearing plan for a full-stack story — reading whatever rules the project actually has (the same "data, not procedure" split as the intake rubric, `design-log.md` D11 and D23).

The planner also records a **test strategy** for the build phase, under the plan's **Testing recommendations** heading and reflected in the Definition of done (see Phase 3 and `design-log.md` D33). It has three parts. First, **whether** the story warrants automated tests at all — a decision gated on the project actually *having* a test practice, which the planner reads from the project's skills and rules (a config fact, not a per-story invention): a repo with no test framework gets "no automated tests" and the coder does not bootstrap one per story (the planner may add a non-blocking Consideration suggesting the project adopt one). Second, **at what altitude** — unit, integration, or behavioral, expressed in the project's own vocabulary. Third, a conditional, **additive must-cover list**: the specific edge cases and failure modes the acceptance criteria don't already state (empty input, boundaries, error paths, …), **each with its expected outcome**, so the coder has a concrete target and the reviewer a spec-anchored checklist. The list is dropped entirely when the ACs already pin down testable behavior — the same "drop rather than fabricate filler" discipline as the plan's other conditional sections. The planner sets *strategy*, never a designed suite; the human ratifies it at plan review along with the rest of the plan. Test altitudes are orthogonal — a backend story might warrant unit + integration tests, a small UI change none.

When the planner opens the plan PR it also establishes the **artifact links** that let every later agent navigate between the work item, the plan, and the PRs (see `design-log.md` D17). The link layer is twofold. First, the plan PR is **linked to the ADO work item through ADO's native work-item↔PR linking** (the Azure Boards ↔ GitHub integration). Second, the plan PR's body carries a fixed, machine-parseable `AIND-LINKS` block — written as an HTML comment, so it is invisible in the rendered PR but trivially parsed — listing the work-item URL and the plan path. The same contract repeats in the build phase: when the coder opens the code PR (Phase 3) it is likewise native-linked to the work item, and its `AIND-LINKS` block additionally carries the plan-PR URL. The framework fixes the plan's location (`/plans/<work-item-id>/plan.md`, per D10) and uses the **work-item ID as the join value**, but it **does not name or assume any branch** — branch naming is a project responsibility, so an agent reaches the branch *through* the code PR, never by constructing a branch name. The links are created **after** each PR is successfully opened, so a failed link leaves a real, discoverable PR rather than a dangling pointer (the same merge-then-tag discipline as D13). This whole contract depends on the Azure Boards ↔ GitHub integration being connected — a one-time setup prerequisite, like the branch-protection rule below; if it is absent, the degraded fallback is a fixed-prefix work-item comment (`AIND-LINK: <kind> <url>`).

The planner never blocks waiting for an answer — a triggered run has no one to prompt. Where it hits a genuine choice (a design alternative or an ambiguous detail), it proceeds on a reasonable assumption and records it, with any open questions, under an **Assumptions & open questions** heading in the plan; reviewers then respond to a concrete draft rather than an abstract question. Each assumption and open question is recorded in **two places**: once under that heading in the plan markdown (so the plan is self-contained and the record survives in the merged living doc), and once as an **individual PR review thread** on the plan PR. The review threads are the active mechanism: because they are resolvable threads (not a single lumped top-level comment), and because the plan PR's target branch requires conversation resolution before merge (see below), **every assumption and open question must be explicitly resolved by the human before the plan can be approved and merged**. This turns the assumptions from passive documentation into a checklist the reviewer has to clear item by item — a reviewer who silently merges has, by construction, ticked through each one. If a story proves too underspecified to plan against at all, the planner does not open a plan PR full of questions — that is a story that was not ready, handled as an intake-stage exception rather than as plan-review feedback. And if the planner simply cannot produce a viable plan after its retry cap, it stops and raises `Needs attention` rather than looping or emitting a bad plan — the stuck-state protocol (see `design-log.md` D12 and §4).

> **Required repo setting.** The "every assumption must be resolved before merge" gate depends on the plan PR's target branch having GitHub's **"require conversation resolution before merging"** branch-protection rule enabled. This is a one-time repo setup prerequisite — the agent posts resolvable threads, but it is the branch protection (not the agent) that actually blocks the merge until they are resolved. Note the mechanism is specifically *review threads*: plain top-level PR (issue) comments do not carry resolve state and would not gate merge.

### Phase 2 — Plan review

A human reviews the plan in the PR.

- **Plan-level gaps and open questions:** the human requests changes — or answers a question the planner raised — and the planner revises within the same PR. The planner's assumptions and open questions appear as resolvable PR review threads (Phase 1), and the human works through them one by one: accepting an assumption resolves its thread, while disagreeing prompts a revision. Status stays `Plan ready for review` throughout; the iteration lives in the PR, not in the status.
- **Story-level problems** surfaced by the plan: the human closes the plan PR and reroutes the item to `Ready for intake` so the story can be fixed and re-scored.
- **Approval:** when the plan is approved, the human sets `Ready for implementation`, completing the plan phase. Because the target branch requires conversation resolution (Phase 1), **the plan cannot be merged until every assumption/open-question thread is resolved** — so approval and merge structurally guarantee that each one was addressed, not skipped. Approving the plan also ratifies the planner's test strategy — whether tests are written, at what altitude, and the must-cover cases — for the build phase (see Phase 3).

### Phase 3 — Implementation

When a story is `Ready for implementation` (its plan PR merged), the build phase begins; status becomes `In implementation`.

**Implementation.** The coding agent implements the spec and, where the plan's test strategy calls for tests, **authors them in-context** — against the must-cover list and the seams it is building (warm and cheap: the coder is testing structure it is actively creating, so it knows the seams; authoring the tests cold would only re-derive that design intent for no independence gain — the independence lives at the reviewer, Phase 4). A **polish agent** then does in-context cleanup — code style, formatting, self-consistency — working from the coder's own context (warm). Note the asymmetry: polish is warm *by design* (it is the coder tidying work it already understands), so it is **not** an independent check. The coder gets the project's build **and** the tests it authored green, then opens a GitHub PR for the code. Getting build + tests green before the PR is the flow's objective gate; any CI a project runs on the PR (build, lint, coverage, security, the test suite) is the project's own and orthogonal to AIND (see `design-log.md` D34).

**In current scope, the coding agent is a warm in-session command (`/aind:implement <work-item-id>`) that builds the plan into a code PR and then drives the code review (Phase 4) to a verdict** (see `design-log.md` D24 and D26). It grounds from the merged plan and the `rules/*.md` files each task cites (the artifact-link contract of §5 Phase 1 / D17) plus the project's build/run skills, implements the task breakdown against the plan's Definition of done, authors the tests the plan's strategy called for, runs the polish step in its own context, opens the code PR — generating a readable code branch (`[type]/<work-item-id>-<short-name>`) that every later agent reaches *through the PR*, never by reconstructing the name (D17) — and then spawns the cold reviewer for the review loop below. **Scope ends at reviewer approval or a human tiebreak**; the human merge gate and the terminal `Implementation complete` write (D13) are the close-out step (`/aind:complete`).

Two build-phase failure modes are handled by the stuck-state protocol (see `design-log.md` D12 and §4) rather than by silent looping. If the coder cannot get the tests passing after its retry cap, it stops and raises `Needs attention` with the trail of what it tried. If a merge conflict arises from work that landed concurrently, the coder attempts **one automated rebase/conflict-resolve**; only if that single attempt fails does it escalate to `Needs attention`. In both cases a human resolves the blocker and the build resumes (§4).

**Live verification, when the plan calls for it.** There is no live/end-to-end *agent* and no E2E CI gate in the flow: how to stand up and drive a running application is irreducibly per-project (it belongs in a project **skill**, never in plugin machinery), so AIND does not own it (see `design-log.md` D33). Where a story genuinely needs the running app exercised before merge, the planner records it as a **Definition-of-done line** ("needs manual live verification before merge"), and a **developer runs the app and signals the pass in the PR** like any other human input — the same human-in-PR pattern used elsewhere, with zero new machinery. An automated E2E path (a job that stands up the app in CI) remains possible for a project to add on its own, but it depends on the deployment/preview story that is out of scope here.

### Phase 4 — Code review and merge

A **reviewer agent** reviews the code PR for spec alignment and missed edge cases — the things a diff cannot self-verify. The reviewer is **cold**: a separate invocation, re-grounded only from artifacts (the PR diff, the merged spec, project rules) and never handed the coder's transcript or reasoning. This independence is the entire point of the gate, so it is enforced structurally (separate run, no shared context) rather than by instruction. A cold agent given only the PR resolves the rest of its inputs through the artifact links (D17): it reads the `AIND-LINKS` block in the PR body to reach the work item and the plan at `/plans/<id>/plan.md` without an ADO round-trip — which is precisely why that block is kept in the PR body and not only as a native link. If a convention-derived guess and a stored link ever disagree (for example after a branch or file was renamed), the **stored link wins and the agent flags the mismatch** rather than guessing.

Because the coder authors its own tests (Phase 3), the reviewer is also **the independence gate on the tests themselves** (see `design-log.md` D33) — the check the coder cannot be for its own work. Re-grounded from the spec (never the code), it judges three things. **Coverage:** every must-cover case in the plan's test strategy has a test — a missing case is a **blocking** finding. **Fidelity:** each test asserts the behavior the *spec* calls for, not whatever the code happens to do — so the reviewer must **not** treat a green suite as evidence of correctness (a test can pass against buggy code because its assertion was written to match the bug); a test that encodes wrong-per-spec behavior is **blocking**. **Meaningfulness:** tautological, framework-testing, or redundant-bulk tests are flagged, but as non-blocking **suggestions** — the plan's must-cover list is the objective/taste boundary that keeps the review loop from deadlocking on test nits. This is a genuine reduction of the "coder games its own tests" and "coder pads the suite" risks, not an elimination: a diff-reading reviewer cannot catch every subtly tautological assertion, and the robust mechanical upgrade — mutation testing — is a project-side CI gate a team can add, not plugin machinery. Beyond tests, the reviewer owns what a suite can never express — the **cross-cutting concerns**: coding style and conventions, authentication and authorization, logging and observability, and project-rule alignment. When a story warranted no tests, the reviewer remains the sole spec-correctness check, exactly as before.

The reviewer and coder iterate in the PR for **up to three reviewer passes**. A pass is: the reviewer comments, and the coder either fixes the issue or pushes back in the thread. The loop **exits as soon as the reviewer has no open comments** (approval) — so the cap only bites on a genuine deadlock, not on normal iteration. If comments remain open after the third pass (the coder rebuts, the reviewer is unsatisfied), the item **escalates to a human**, who reads the PR threads — the disagreement is visible there, not synthesized — and posts a verdict. The coder executes that verdict, one more reviewer pass follows, and then the PR merges.

Throughout this loop, status stays `In implementation` — the iteration lives in the PR, not in the tag (§4). Once the reviewer approves (or the human verdict has been executed and the final pass is clean), **a human merges the code PR**, and a CLI command writes the terminal `Implementation complete` tag as part of the same step — **merge first, then tag**, so a failed tag-write leaves the item recoverable rather than falsely complete (see `design-log.md` D13). Auto-merge and an Action-driven tag-write are deferred to the automation phase along with the rest of the unattended machinery (§6).

### Dreaming phase (non-linear, cross-story)

The plan and build phases above are linear and per-story: one story enters intake and leaves as merged code. The **dreaming phase** is different in kind — it is **non-linear, cross-story, and asynchronous**. It does not move any single item through the status model; instead it watches the *exhaust* of many completed items and uses it to improve the agents themselves. It is the flow's only feedback path: everything else converts stories into code, while dreaming converts the experience of doing so into better agent configuration (see `design-log.md` D16).

It has four parts.

**1. Emission (warm).** Every automated agent — intake, planner, coder, polish, reviewer — ends its session by emitting a structured *lessons-learned* record: what it tried, where it iterated and why, and what it would do differently. The record draws on whatever that agent's run exposed — the plan-PR comment threads it worked through, the polish fixes it repeatedly applied, the reviewer passes it took to converge, and so on. This emission is deliberately **warm**: the agent is reflecting on its own run, and it is the only party that knows *why* it did what it did (the artifacts show *that* the planner iterated three times, not *what the planner would say it learned*). Warm self-report is appropriate here precisely because emission does not *decide* anything — it only contributes raw signal. This is the same reasoning that forbids warm self-grading for *gating* (polish D7; the coder judging its own tests, D33) yet permits it for *emission*: the gate must be independent, the raw report need not be.

**2. Synthesis (cold dreamer).** On a regular cadence, a **dreamer agent** reviews the accumulated lessons-learned records and proposes improvements. The dreamer is **cold** — a separate invocation, re-grounded only from the emitted lessons plus artifacts, never handed any agent's running context — the same re-grounding contract as the reviewer (Phase 4). The phase's overall shape is therefore **reflect-warm / synthesise-cold**: warmth where it is cheap and informative (an agent reporting its own session), independence where it counts (deciding whether a lesson is a real, recurring pattern worth acting on or a one-off worth ignoring). The dreamer's coldness is exactly what keeps the synthesis of those warm reports honest — it judges the pile of self-reports without having lived any of them.

**3. Cadence.** The dreaming phase runs **on a regular basis**; the framework deliberately leaves the exact trigger open — for example **every X `Implementation complete` items** (a volume-based cadence that fires when enough new exhaust has accumulated to be worth synthesising). The precise number is a tuning detail, left empirical in the same spirit as the retry-cap N in D12; nothing in the design depends on a specific value. A volume trigger is given only as the illustrative default — a project could equally choose a time-based or manual trigger.

**4. Output and authority.** Every improvement the dreamer proposes lands as a **GitHub pull request against `.claude`** — **one dream cycle is one PR** — and a **human accepts or rejects it**. The dreamer *proposes*; the human *disposes*. This human gate is **permanent**: it is not a manual-scope limitation to be lifted once automation arrives, but the same *agent-suggests / human-decides* pattern as intake (D2) and merge (D13), applied here to the **highest-blast-radius write in the whole system** — because the dreamer modifies the very files (`.claude`: skills, agent prompts, the rubric, project rules) that *every other agent reads on every run*, a bad lesson merged unreviewed would silently degrade all future work rather than break one story. The PR shape gives every proposed change the same properties D5 gives plan assumptions: each one is individually reviewable, rejectable, auditable, and revertible.

The dreamer's **authority is hard-bounded to the agent-config / "learned behavior" layer** — skills, agent prompts, the intake rubric (§5 Phase 0), project rules. It may **never** propose changes to the **flow itself**: the status model (§4), the gates, and the structural decisions D1–D15 are out of bounds. Improving *how* an agent does its job is in scope; redesigning *the job* is not. If the dreamer detects what looks like a structural problem — a recurring failure that no amount of prompt-tuning seems to fix — it may **raise it as a parking-lot note for a human to consider**, but it must not encode such a change as a mergeable diff. A self-improving agent that could rewrite its own gates is exactly the failure this boundary exists to design out.

**One signal is deliberately not yet captured.** The emission step covers *agents*, but the two most consequential human interventions — the **human tiebreaker** who resolves a coder↔reviewer deadlock (Phase 4, D7) and the **human who merges** the code PR (D13) — are not agents and do not auto-emit. *Why a human overrode the machine* is arguably the single highest-value lesson, and today it is lost unless the human writes it into the PR by hand. Capturing it systematically (a prompt at the human gate, say) is **deferred**: it adds friction to the human gate and is a gate-mechanics detail rather than part of the framework's shape (see `design-log.md` D16). The dreaming phase functions without it — it simply learns from the agents' self-reports and the artifacts in the meantime.

**How it's implemented (D30).** Emission is a single signed script (`aind-emit-lesson.sh`, the exhaust twin of `aind-comment.sh`): each agent calls it at session end and it appends one record — front-matter (work item, agent, phase, a **severity** enum keyed to how far a human had to step in: `observation`/`suggestion`/`correction`/`blocker`, plus a `source` and an optional implicated-config `area`) and an **Observation** body that states *what happened and why* but never a proposed fix (the remedy is the dreamer's alone). Records are written with throwaway-index git plumbing (no checkout), so an agent emits mid-run without leaving its branch, onto a dedicated **orphan branch** (`aind/lessons`, default) that never merges into integration — an append-only exhaust store, git-native like the dreamer's output. This also realises the deferred human-override capture *without* a gate prompt: the planner/coder revise runs already read the PR threads, so a human's correction or tiebreak verdict is emitted as a `correction`/`suggestion` lesson sourced to that thread. Synthesis is the manual command `/aind:dream` (the scheduler's handle later) — a warm orchestrator that spawns the cold `aind-dreamer` **twice**: an *analyze* pass clusters the unprocessed lessons and judges each on **severity × recurrence × factualness** (a lone high-severity or verifiable-defect cluster is actionable at once; a taste cluster needs recurrence — no fixed count), surfacing borderline clusters with a confidence label rather than dropping them; the **human then curates the clusters** (Gate 1 — with the recurrence view in hand); an *author* pass turns only the approved clusters into `.claude` edits, which land as the one config PR (Gate 2). Scope is the project's own `.claude` (rules, skills, rubric, project agent prompts) and never the flow; a suspected structural problem, or generic reusable knowledge that belongs in the companion standards plugin (D25), is recorded as a parking-lot note (`.aind/parking-lot.md`), never a diff.

### Onboarding (one-time, pre-flow)

Before any story runs through the flow, an existing project needs an initial agent-config layer — the project rules, the readiness rubric, and the project-specific skills that every agent reads. The **onboarding agent** bootstraps that layer from the codebase itself, so a team adopting AIND does not start from empty template stubs (see `design-log.md` D18).

It is **human-invoked and one-time**. Run at the project root, it:

1. **Surveys the codebase** — layout, package/build manifests, CI/CD config, infra, docs, existing conventions.
2. **Discovers the rule areas this codebase actually needs**, through three lenses: **technical layers** present (front-end, back-end, web-jobs/workers, infrastructure, …), **cross-cutting concerns** with a notable or non-standard approach (a custom pin-code auth scheme, a specific logging or error-handling discipline, …), and the **functional / domain architecture** — the product's core structural concepts and invariants (e.g. "the app is composed of mini-apps", "every entity is scoped to a couple of IDs"), which a planner must respect but no technical-layer file captures. The layer names are *examples, never a fixed list*, and discovery is **strictly evidence-only**: a rule file is drafted only for an area that genuinely exists, so a repo with no test framework gets no testing rule and one with no docs system gets no docs rule. It drafts one `rules/<area>.md` per discovered area and a `CLAUDE.md` that imports exactly those files.
3. **Stubs project-specific skills** from the deterministic dev workflows it finds (manifests, CI steps, scripts) — build/test/run-app/lint as the common core, but not limited to them (deploy, DB migrations, data seeding, codegen, formatting, starting local dependencies, e2e, …, where the repo has them) — so the mechanics are scripted from day one and ready for the planner and the build phase.
4. **Copies the seed intake rubric** (§5 Phase 0) into the project for the team to extend.
5. **Reports the remaining prerequisites** via a preflight probe — required tools, ADO/GitHub auth, the Azure Boards↔GitHub integration, and the plan-PR branch-protection rule — so the team leaves the step knowing exactly what is left to set up.

**Greenfield variant — the kickstart agent (D31).** Onboarding as described above reads an
*existing* codebase; a **new project has no code to scan**. For that case a sibling **kickstart
agent** (`/aind:kickstart`) bootstraps the same `.claude/` config from a **guided conversation**
instead of from code — it elicits the project across the same three lenses (functional/domain,
technical layers, cross-cutting concerns) plus the operational config, reading any design docs the
user points it at, then drafts the rule files, a wired `CLAUDE.md`, placeholder skills (the
*intended* dev workflows — build/test/run and beyond, e.g. deploy/migrate/seed/codegen where the
project plans them — marked unverified since the toolchain may not exist yet), and a seed-rubric copy. It obeys the same two rules as the onboarder — suggest-don't-assert, config-layer
only — with one greenfield-specific discipline that distinguishes it: because a new project's answers
are often *decisions not yet made* rather than observed facts, it **never fabricates a convention to
fill a gap** — an undecided point becomes an explicit `TODO`/open question in the draft, not a rule.
The two are complementary: kickstart bootstraps config *before* code exists, and `/aind:onboard`,
re-run once real code lands, reconciles those intended-design drafts against the actual codebase.

The onboarding agent is the **day-one mirror of the dreamer**: the onboarder *bootstraps* the agent-config layer from the codebase, the dreamer (above) *evolves* it from the flow's exhaust. Both obey the same two rules. First, **suggest, don't assert** — every file the onboarder writes is a clearly-marked **DRAFT** that a human reviews and edits before it is trusted, the same *agent-suggests / human-decides* pattern as intake (Phase 0) and the dreamer. Second, the onboarder is **bounded to the config layer and may never touch the flow** — the status model, the gates, the structural decisions — exactly the boundary the dreamer respects. The one deliberate difference is delivery: the onboarder writes **draft files directly into `.claude/`** rather than opening a PR-against-`.claude` (the dreamer's surface), because at onboarding there is no running flow or configured repo to review such a PR — the draft files are reversible via git and reviewed before commit, which preserves the human gate without the bootstrap chicken-and-egg.

---

## 6. Triggering and execution

> **Current scope: manual execution only.** Of the two modes below, **only the local CLI mode (Claude Code or GitHub Copilot CLI) is in current scope** — the team runs the agents by hand for now. The GitHub Actions mode (unattended, service-identity-based automation) is documented as the intended next step but is **descoped for now**, and the service-identity question it depends on is parked (see `design-log.md` D6 amendment, 2026-06-24). It is retained here as the design target, not a current deliverable.

The agents are Claude Code — or GitHub Copilot CLI — reading the repository's `.claude` configuration (skills, project rules, the readiness rubric). The same agent definitions are intended to run in two modes — only *where they run* and *whose credentials they use* differ. The Azure DevOps work item (with its `AIND status` tag) is the state record in both modes; what triggers each step is separate from that state.

### Local (Claude Code or GitHub Copilot CLI) — current mode

A developer runs each handoff from the Claude Code CLI (or GitHub Copilot CLI) on their own machine — for example `/aind:intake <work-item-id>`, `/aind:plan <work-item-id>`, or headless `claude -p`. The agent uses the developer's own Azure DevOps and GitHub credentials, and needs no service identity and no CI. Both hosts load the same plugin (Copilot via its own manifest + hook, and requires Git's `bash` on PATH on Windows — see `design-log.md` D22). This is the **current working mode**: it runs the intake, planner, coder, and reviewer agents entirely by hand, with no infrastructure to provision.

Two consequences follow from the agent acting as the developer: tags and comments it writes appear under that person's name rather than a distinct bot — fine for manual use, less precise for audit — and PR revisions (both plan review and code review) are re-run by hand, since the CLI does not listen for PR events. The stuck-state protocol (§4, D12) still applies — a stuck agent sets `Needs attention` and the developer resolves and re-runs the relevant command.

### GitHub Actions — future (descoped for now)

> The following describes the intended automation step and is **not in current scope**. The service-identity decision it references is closed-by-descoping until automation is picked up (`design-log.md`, former Q7).

The agents run as Claude Code in GitHub Actions.

- **Intake, planning, and the build kickoff are human-triggered.** Each is a workflow started via `workflow_dispatch`, with the work-item ID passed in. The agent reads the story from Azure DevOps, performs its task, and writes the resulting `AIND status` tag and its reasoning back to the work item. The build kickoff runs the coder (implement + any tests the plan called for → polish → open code PR).
- **Plan review and code review are event-driven within GitHub.** Once a PR is open, requesting changes (or an `@claude` mention) drives the next iteration in place — the planner revises the plan, or the coder responds to the reviewer. Each loop lives entirely in its PR and does not change the `AIND status`; the item stays `Plan ready for review` or `In implementation` respectively. On merge of the code PR, status becomes `Implementation complete`; in this future mode the merge could be auto-merge-on-approval and the tag written by a PR-merge Action as the service identity — both **deferred to the automation phase** (the manual-scope answer is D13; see `design-log.md` D13).
- **Agents act through a service identity.** Reading stories and writing tags and comments to Azure DevOps is done with a dedicated service identity; its credentials and the model API key are stored as GitHub secrets. (The specifics — single bot vs. per-agent, PAT vs. Entra service principal + OIDC, secret storage — are deferred with the rest of the automation work.) The reviewer runs as a separate invocation from the coder, so the two never share a context (§5, Phase 4).

Both modes run the same `.claude` configuration, so an agent proven locally is intended to run unchanged in GitHub Actions when automation is picked up — only the trigger and the identity move.

---

## 7. Glossary

| Term | Meaning |
|---|---|
| AIND | AI Native Dev — the prefix namespacing the status tags. |
| Stuck-state / `Needs attention` | The protocol for an agent that has stopped because it cannot make progress (planner can't plan, coder can't get the tests passing, unresolvable merge conflict): it caps its retries, stops, sets the shared `Needs attention` status, and posts its trail for a human, who resolves the blocker and re-triggers the origin phase. Distinct from a coder↔reviewer disagreement, which keeps working and does not move the tag (see §4 and `design-log.md` D12). |
| Intake agent | Automated agent that scores a story's readiness (see §2). |
| Planner agent | Automated agent that drafts the plan and opens the plan PR (see §2). |
| Coding agent | Automated agent that implements the merged spec, authors the tests the plan's strategy calls for, and opens the code PR (see §2). |
| Polish agent | Warm-context agent that does in-context style/consistency cleanup before the code PR; not an independent check (see §5). |
| Reviewer agent | Cold, independent agent that reviews the code PR for spec alignment, edge cases, cross-cutting concerns, and test quality (see §5). |
| Dreamer agent | Cold, independent agent in the dreaming phase that synthesises the emitted lessons-learned records and proposes agent-config improvements as a PR against `.claude`; proposes only, human disposes, bounded to config never the flow (see §5 Dreaming phase). |
| Onboarding agent | One-time, human-invoked agent that bootstraps a project's `.claude/` config from its existing codebase — drafts per-domain rules, a wired `CLAUDE.md`, project skills from discovered commands, and a seed-rubric copy, then reports prerequisites. Suggests only (drafts for human review); bounded to the config layer; the day-one mirror of the dreamer (see §5 Onboarding and `design-log.md` D18). |
| Kickstart agent | Greenfield variant of the onboarding agent (`/aind:kickstart`): bootstraps the same `.claude/` config for a **new project with no code to scan**, eliciting its shape through a guided conversation (plus any design docs) instead of from code. Suggests only; config-layer only; and never fabricates a convention — an undecided point becomes a `TODO`, not a rule (see §5 Onboarding and `design-log.md` D31). |
| Dreaming phase | The non-linear, cross-story feedback loop: agents emit lessons → the cold dreamer synthesises them on a cadence → a PR against `.claude` proposes improvements → a human accepts or rejects (see §5 and `design-log.md` D16). |
| Lessons-learned record | The structured self-report an automated agent emits at the end of its session (what it tried, where it iterated, what it would do differently); the warm raw signal the dreamer synthesises (see §5 Dreaming phase). |
| Reflect-warm / synthesise-cold | The shape of the dreaming phase: emission is warm (an agent reporting its own run), synthesis is cold (an independent dreamer deciding what is a real pattern) — the D7 warm-vs-cold split applied to learning (see §5). |
| Agent host | Where the agents run: **Claude Code** or **GitHub Copilot CLI** — one behaviour layer, a per-host manifest + hook (see §1 and `design-log.md` D22). Orthogonal to the code host. |
| Code host / forge | Where the code and its PRs live: **GitHub** or **Azure DevOps Repos**, selected per-project by `AIND_CODE_HOST` (`AIND_GH_REPO` / `AIND_ADO_REPO`). A thin forge-adapter in the scripts absorbs the difference; commands, agents, and skills are identical on both. Work items always live in ADO (see §1 and `design-log.md` D36). |
| Plan PR | The pull request carrying the implementation plan, on the configured code host (GitHub or ADO Repos). |
| Code PR | The pull request carrying the implementation, on the configured code host (GitHub or ADO Repos). |
| Artifact links / `AIND-LINKS` | The contract for navigating between a work item, its plan, and its PRs (see §5 Phase 1 and `design-log.md` D17): each PR is native-linked to the ADO work item (the Azure Boards ↔ GitHub integration on GitHub; ADO's built-in `--work-items` linking on ADO Repos) **and** carries a fixed `AIND-LINKS` block in its body (a hidden marker — an HTML comment on GitHub — listing the work-item URL, the plan path, and — on the code PR — the plan-PR URL). The native link is canonical and human-visible; the in-body block lets a cold agent resolve everything from artifacts alone. The work-item ID is the join value; branch names are never assumed (a branch is reached through its PR). |
| CI | Continuous integration — whatever automated pipeline a project runs on its PRs (build, lint, coverage, security, tests). It is **not part of the AIND flow**: AIND enforces nothing at CI, and a project with no pipeline runs the flow fine. The flow's own objective gate is the coder getting build + tests green *before* opening the PR; any project CI is orthogonal (see `design-log.md` D34). |
| Cold / warm context | Warm = shares the coder's context (the polish agent, and the coder authoring its own tests); cold = a fresh invocation re-grounded from artifacts only, with no shared context (the reviewer and the dreamer). |
| Test strategy | The planner's per-story testing decision recorded in the plan (Testing recommendations + Definition of done): whether to test (gated on the project having a test practice), at what altitude, and a conditional must-cover list of edge cases with their expected outcomes. The coder authors the tests; the cold reviewer checks them (see §5 and `design-log.md` D33). |
| Behavioral / acceptance-level test | A test that asserts input→expected-behavior against the acceptance criteria, agnostic to internal code structure; one altitude the planner's test strategy may call for (see §5). |
| Unit test | A test exercising an internal code seam (function, module, boundary); authored warm by the coder as it builds those seams (see §5). |
| Manual live verification | Where a story needs the running application exercised before merge, the plan records it as a Definition-of-done line and a developer runs the app and signals the pass in the PR — there is no live/E2E agent or E2E CI gate in the flow (running the app is a per-project skill; see `design-log.md` D33). |
| Definition of Ready / readiness rubric | The criteria the intake agent scores a story against, stored at `.claude/intake-rubric.md` — a two-layer (baked-in core + per-project extensions), hybrid (objective pass/fail + judgment advisory) rubric (see §5 Phase 0 and `design-log.md` D11). |
| `workflow_dispatch` | The GitHub Actions trigger used to start an agent run manually (see §6). |

---

*Rationale for the choices in this document is recorded in `design-log.md` (decisions D1–D36).*
