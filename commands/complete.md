---
description: Close out the build phase — verify the code PR is merged, then set Implementation complete.
argument-hint: <work-item-id> [pr-number]
allowed-tools: Bash
---

# /complete — build phase close-out

Human-run helper for after the code PR for story `$1` has been **reviewer-approved and merged** in
GitHub. Merging is a human act — the human is the final authority on what lands; this command only
**confirms** the merge and records the resulting terminal status. It does **not** merge anything.

Work item: **$1**

## Procedure

1. **Verify the code PR is merged.** Resolve the story's code PR and confirm it is `MERGED`:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-complete.sh" verify "$1" $2
   ```
   (The optional `$2` is a PR number — pass it when the story has more than one matching PR, or when
   the search can't find it.) On success this prints one line: `<pr-number> <pr-url> <head-ref>
   <merge-commit-sha>` — keep these for steps 2–4.

   **If it refuses — STOP.** The command only writes the terminal tag *after* a confirmed merge, so a
   completed tag can never sit on an unmerged PR. Do **not** run the remaining steps. Relay its
   message to the user (typically: merge the PR first, then re-run; or pass an explicit PR number).

2. **Write the terminal status.** Reached only because step 1 confirmed the merge (merge first, then
   tag):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-status.sh" "$1" "Implementation complete"
   ```
   If this fails, stop and report it: the item stays `In implementation` and is safely re-runnable —
   never leave it falsely complete.

3. **Post the completion note.** A short signed note on the work item (feed the body as a direct
   heredoc — one command, no `cat |` pipe — and substitute the real PR URL and merge commit from
   step 1):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-comment.sh" "$1" coder <<'EOF'
   ## Implementation complete
   Code PR <pr-url> has been merged; this story is now **Implementation complete**.
   Merge commit: <merge-commit-sha>.
   EOF
   ```

4. **Clean up the merged code branch.** Branch hygiene last, so a cleanup hiccup never affects the
   committed status. The script re-confirms the PR is `MERGED` first, deletes the remote branch only
   if it still exists (a no-op when the merge auto-deleted it), prunes the stale remote-tracking ref,
   and removes the lingering local branch (switching you to the integration branch first if it's
   checked out and your working tree is clean). Finally, if you end up on the integration branch with
   a clean tree, it **fast-forwards that branch to include the merge** so your local checkout is
   current (fast-forward only — a diverged branch is left for a manual pull). Pass the PR number from
   step 1:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/aind-complete.sh" cleanup "$1" <pr-number>
   ```

## Report
Tell the user the story is **Implementation complete**, with the merged PR URL and merge commit, and
note the branch-cleanup outcome (deleted / already gone / left for you to remove manually if your
working tree was dirty) and whether the integration branch was fast-forwarded to include the merge.

## Notes
- This is the terminal state of the flow. There is no un-complete step; if the tag was written in
  error, correct it by re-running the appropriate earlier phase.
- The merge is the human's act of acceptance — this command trusts that the reviewer approved (or a
  human resolved a tiebreak) before the PR was merged, exactly as plan approval trusts the human
  merged the plan PR only after resolving its threads.
- One story = one code branch = one code PR. The PR is the handle for the branch — this command finds
  it by the work-item id, never by reconstructing the branch name.
