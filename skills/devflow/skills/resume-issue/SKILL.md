---
name: resume-issue
description: Resume in-flight work on a GitHub issue from a clean session — resolves the issue to its branch and specs/intent/<slug>.md, reconciles that doc's Status checkboxes against what the repo actually contains, and picks the pipeline back up at the first genuinely unfinished step. Use when returning to an issue started earlier with /devflow:spec-intent, not to start new work.
---

Counterpart to `/devflow:spec-intent`: that skill starts an issue, this one picks it
back up after a session ended mid-flight (usually out of context). Ends with
work resumed at the correct `.claude/workflow.md` step, not with a plan to
resume it.

Takes one input: a GitHub issue number or URL. If not given, ask — don't guess
which issue. Optional `--report-only`: orient and stop, skipping Step 5.

Throughout, "the base branch", "the verify command" etc. are the settings in
`.claude/workflow.md`'s project configuration.

## Step 1 — Resolve the issue to its artifacts

Run these together; they're independent:

```
gh issue view <n> --json number,title,body,url,state,labels
gh issue develop --list <n>
grep -rl "issues/<n>)" specs/intent/
gh pr list --state all --search "<n>" --json number,state,headRefName,body
```

- **Intent doc:** the `grep` hit. Intent docs carry
  `**Source:** [GitHub issue #N](...)`, so this is the reliable link — the slug
  need not match the issue title. Zero hits means Step 1 never finished: say so
  and offer `/devflow:spec-intent <n>` instead; this skill has nothing to resume.
  More than one hit means the issue produced several slugs — report all of
  them and ask which to resume rather than picking one.
- **Branch:** from `gh issue develop --list`. If that's empty, fall back to
  `git branch -a --list "*<slug>*"`.
- **Issue `state: CLOSED`** with unfinished work is a real signal — the issue
  may have been closed by a merged PR. Report it and confirm before resuming.

## Step 2 — Get onto the branch safely

Run `git status --short` and `git branch --show-current`.

First check `git worktree list`: if the branch is already checked out in a
worktree (a `/devflow:spec-intent … parallel` start), `git checkout` will refuse it.
Work from that worktree's path instead — tell the user to restart the session
there if this one isn't — and apply the rules below to it.

- **Uncommitted changes on the right branch** are the normal shape of a session
  that died mid-implementation — that's work in progress, not garbage. Keep it,
  and treat it as evidence in Step 3. Never stash, reset, or clean it.
- **Wrong branch + a dirty tree:** stop and hand it back to the user. Don't
  switch branches over uncommitted work.
- **Wrong branch + clean tree:** `git checkout <branch>`, then
  `git pull --ff-only` (a squash-merge upstream may have moved things).
- **No branch exists** but an intent doc does: the previous session died
  between the doc and the branch. Create it per `/devflow:spec-intent` Step 3
  (`gh issue develop <n> --name <branch> --base <base branch> --checkout`).

## Step 3 — Reconcile the Status block against the repo

The doc's `## Status` checkboxes are the record of progress, but a session that
runs out of context dies *before* ticking the box for work it just finished, so
an unchecked box is weak evidence and a checked one is only as current as the
last save. Verify each against what's actually on disk. Gather the evidence in
one pass:

```
git diff --stat <base branch>...HEAD
git status --short
ls specs/features/<slug>.feature
git log --oneline <base branch>..HEAD
```

| Status line              | Ground truth to check                                                   |
|--------------------------|-------------------------------------------------------------------------|
| Intent drafted           | the doc exists and its sections aren't still TEMPLATE placeholders       |
| Spec drafted             | `specs/features/<slug>.feature` exists with real scenarios, not a stub   |
| Approved by human        | trust the box — high-risk path only; unverifiable from disk             |
| Implemented              | diff/working tree touches production source, not just tests or docs      |
| Manually playtested      | trust the box, plus any playtest note in the PR body; **never infer it** |
| Acceptance tests passing | see below — the one probe worth spending on                             |
| Mutation testing passed  | trust the box; mutation reports are usually gitignored and may be stale |
| Documentation updated    | diff touches `docs/` (or the doc states explicitly that nothing changed) |

For **acceptance tests**, run the feature's own scenarios with the scenario
command rather than the whole suite — cheap enough to be worth real evidence,
scoped enough not to burn the session you just started.

Skip even that if the tree is clean, the box is checked, and `git log` shows a
commit after the `.feature` was last touched — nothing can have broken since.

Then **write the corrected checkboxes back into the intent doc** and say which
ones you changed and why. This is the point of the skill: the next resume reads
a Status block that matches reality. Never tick a box you couldn't verify —
leave it unchecked and name it as unverified in the report.

## Step 4 — Report where the work actually stands

Before resuming, state in a few lines:

- Issue, branch, intent doc path, and PR number if one is open.
- The reconciled Status block, flagging any box you corrected.
- **The resume point:** the first `.claude/workflow.md` step that isn't done.
- Uncommitted work carried over from the dead session, if any.
- Any `## Open questions` in the intent doc still unanswered — those block a
  resume just as hard as an unfinished step, and are easy to walk past when the
  session that raised them is gone.

## Step 5 — Resume at that step

Unless `--report-only` was passed, continue the pipeline from the resume point,
following `.claude/workflow.md` for that step exactly as a fresh run would —
including the `implement-issue` skill for Steps 4-7 (`--from-hardener <sha>` if
the coder's commit already exists), and the blocking Clean Code gate.

Two things to get right on a resume specifically:

- **Don't redo finished steps.** A verified-complete step is done; re-running
  implementation over existing work is how a resumed session loses it.
- **Stop at human-only gates.** The Step 4.5 playtest (the run command) and the
  high-risk Step 3 approval are the user's, not yours. Reaching one is a
  successful resume: report it and stop.

Stop and hand back, rather than resuming, when: open questions are unanswered,
the intent doc contradicts what's on the branch (implementation diverged from
scope — reconcile the doc first, per Step 1 of the workflow), or the branch is
mid-conflict.

Checkpoint at each step boundary and suggest clearing, per
`.claude/workflow.md`'s session-management notes — a resumed session is already
carrying the reconciliation you just did.

**Resume point is Step 2 → hand back instead of running `/devflow:spec-feature`.** Its
`model: opus` pin covers only the invoking turn; every grilling round after the
user's first answer would run on this session's model. Tell the user to switch
with `/model opus` and run `/devflow:spec-feature <slug>` themselves.
