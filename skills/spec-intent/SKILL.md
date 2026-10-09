---
name: spec-intent
description: Given a GitHub issue number, bootstrap Step 1 of the spec-first workflow — create a linked branch off the base branch, move the tracker item to In progress, and derive specs/intent/<slug>.md from the issue's own description. Use when the user hands you an issue number to start work from, instead of asking them to write the intent doc by hand.
---

Entry point into the spec-first pipeline (`.claude/workflow.md`) when the
intent already lives in a GitHub issue rather than being dictated fresh.
Produces the same `specs/intent/<slug>.md` Step 1 normally requires —
`/spec-feature` picks up from there exactly as it would for a hand-written
intent doc. Do not write a `.feature` file or any implementation code in
this skill.

Takes one input: a GitHub issue number (or URL). If not given, ask for it
— don't guess which issue.

Optional suffix **`parallel`** (`/spec-intent 140 parallel`): start the work
in its own git worktree instead of switching this checkout's branch. Use it
when other sessions or agents are already working in the current checkout —
a plain run would `--checkout` the new branch out from under them. Only
Steps 3, 5 and 6 differ; each marks its parallel variant.

"The base branch", "the project board" and "the issue labels" below are the
settings in `.claude/workflow.md`'s project configuration.

## Step 1 — Read the issue

```
gh issue view <n> --json number,title,body,url,labels,state
```

If `state` is `CLOSED`, tell the user and confirm before continuing —
don't silently start work on a closed issue.

## Step 2 — Derive the slug and branch name

- **Slug:** kebab-case the issue title (strip punctuation, lowercase,
  hyphens for spaces). This must match the eventual
  `specs/features/<slug>.feature` name, so keep it short and concept-level
  — same rule as the intent-doc template ("one slug per distinct
  concept"). If the title clearly bundles more than one unrelated concept,
  say so and ask whether to split before continuing, rather than picking
  one slug and burying the rest.
- **Branch prefix**, from the issue's labels, per the issue-labels mapping
  (by default `bug` → `fix/`, `documentation` → `docs/`, anything else →
  `feat/`, matching the Conventional Commits type). State which prefix you
  picked and why in the final report — it's a one-word rename if the user
  disagrees, not worth a blocking question.
- **Branch name:** `<prefix><slug>`.
- Check `git branch -a` for a collision on that name first. If it already
  exists (local or remote), stop and ask rather than reusing or
  overwriting it — it likely represents existing work.

## Step 3 — Create and link the branch

First, run `git status`. If the working tree isn't clean, stop and tell
the user to commit or stash before continuing — don't carry uncommitted
changes onto a new branch silently.

Then, in one step, create the branch off the base branch and link it to
the issue via GitHub's Development panel:

```
gh issue develop <n> --name <branch> --base <base branch> --checkout
```

This both creates and checks out the branch, and associates it with the
issue (visible in the issue's "Development" section on GitHub) — no
separate linking step needed.

**Parallel variant.** Skip the `git status` check on the current checkout —
it belongs to other work and may legitimately be dirty. Never check anything
out, stash, or commit in it. Instead:

```
gh issue develop <n> --name <branch> --base <base branch>
git fetch origin <branch>
git worktree add .claude/worktrees/<slug> <branch>
```

If `.claude/worktrees/<slug>` already exists, stop and ask — same reasoning
as a branch collision. Confirm `git -C .claude/worktrees/<slug> log
--oneline -1` matches `origin/<base branch>`'s tip before going on
(harness-made worktrees have been seen starting at a stale branch).

## Step 4 — Move the tracker item to In progress

If the project uses a project board, set the issue's `Status` to
`In progress`:

```
bash .claude/tools/set-project-field.sh <issue-url> Status "In progress"
```

It adds the issue to the board first if it isn't already there, and reads
the value back: report it set only if the read-back shows it.

## Step 5 — Derive specs/intent/<slug>.md from the issue

Write `specs/intent/<slug>.md` using `specs/intent/TEMPLATE.md`'s
structure:

- **Slug(s):** `<slug>`
- **Author:** current git user (`git config user.name`)
- **Date:** today
- **Source:** `[GitHub issue #<n>](<url>)`
- **Status:** only "Intent drafted" checked; everything else unchecked.
- **Problem / Scope / Actors / Desired behavior / Constraints / Open
  questions:** derived from the issue's title and body.
  - If the issue was written in intent-doc shape already (e.g. via the
    `brainstorm-issue` skill — Problem/Scope/Actors/Desired
    behavior/Constraints/Open questions headings), this is close to a
    direct carry-over into the template, not a rewrite.
  - If the issue is terse (a one-line bug report, a short ask with no
    structure), derive what you can from it and the codebase, and use the
    `grilling` skill to ask whatever's genuinely missing or ambiguous —
    per `.claude/workflow.md`'s "Notes for the agent": never invent scope to
    fill a section. Most terse issues only produce one open question, so
    this is usually a single-question round, but let grilling ask more if
    the terseness turns out to hide several open forks.

Do not commit this file — leave it for the user to review, same as any
other intent doc.

**Parallel variant:** write it inside the worktree —
`.claude/worktrees/<slug>/specs/intent/<slug>.md`. `specs/intent/` is
gitignored, so each checkout has its own and the doc must live where the
rest of the pipeline will run.

## Step 6 — Report back

One short summary: branch name (created + checked out), issue linked and
moved to In progress, and the intent doc's path. Tell the user the next
step is `/spec-feature <slug>` once they're happy with the intent doc —
don't start that step yourself.

**Parallel variant:** report the worktree path instead of "checked out", and
tell the user to run the rest of the pipeline from a session started in that
directory (`cd .claude/worktrees/<slug>` then `claude`), so every later step
and every dispatched agent operates on the worktree, not the shared
checkout. Once the PR merges, clean up with
`git worktree remove .claude/worktrees/<slug>`.
