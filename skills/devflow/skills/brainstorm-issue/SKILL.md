---
name: brainstorm-issue
model: opus
description: Brainstorm a feature idea with the user and capture it directly as a GitHub issue (or two, if scope splits), skipping specs/intent/ entirely. Use when the user wants to think out loud about an idea for later — not spec it through the full intent -> .feature -> approval pipeline.
---

This is the *pre-intent* version of Step 1 in the spec-first workflow
(`.claude/workflow.md`): same shape of thinking, but the destination is a
GitHub issue, not `specs/intent/<slug>.md`. Never write to `specs/intent/`
or `specs/features/` in this skill — if the user wants that, they'll ask for
`/devflow:spec-feature` instead (or say so mid-brainstorm; if they do, stop and
hand off rather than writing the file yourself).

"The project board" below is the setting in `.claude/workflow.md`'s project
configuration; skip the board steps if the project has none.

## Step 1 — Ground the brainstorm in what actually exists

Before asking the user anything, check what the idea depends on: search
the codebase for the systems/classes it would touch or extend. Note
explicitly what already exists (reuse/extend) versus what doesn't exist
yet (net-new — often means the idea is bigger, or partly blocked, or
needs its own separate issue). Don't skip this — a brainstorm grounded in
"here's what's already there" produces a much tighter scope discussion
than one that starts from the idea in the abstract.

## Step 2 — Scope the brainstorm with the user

Use the `grilling` skill (not free-form prose, and not a flat
`AskUserQuestion` round) to settle, at minimum:

- **What's in scope for a first version** versus what should be split
  into a separate follow-up issue. Recommend the smallest coherent slice
  that doesn't depend on anything unbuilt.
- **Priority** for each issue being filed — P0/P1/P2 (the project board's
  `Priority` field). Recommend **P2** by default: this skill exists for
  ideas the user wants to think out loud about "for later," not urgent
  work, so P2 is the sane default unless the brainstorm itself signals
  otherwise (e.g. the user frames it as blocking something, or it's a fix
  for currently-broken behavior). If the brainstorm splits into a primary
  + follow-up issue, ask about the follow-up's priority separately, in a
  later round — it's almost always P2 even when the primary isn't, but
  it's downstream of the split decision.
- Any other genuinely open fork in the idea (entry point, UI shape,
  who/what triggers it) that materially changes what the issue should
  say. Don't ask about things you can just decide reasonably — grilling's
  fact-finding rule applies here too: look it up in the codebase rather
  than asking if it's answerable that way.

If a question is a single, self-contained multiple-choice pick with no
other open question hanging off it (e.g. confirming a milestone match in
Step 4), a plain `AskUserQuestion` is still the right tool — reserve
`grilling` for genuine ambiguity in the idea itself, which is what this
step is about.

If the answers reveal a natural split (some of the idea is buildable now,
some depends on systems that don't exist yet or is clearly later work),
plan on two issues, not one bloated issue — see Step 3.

## Step 3 — File the issue(s)

If the brainstorm split into "do now" + "later", create the **follow-up /
backlog issue first**, so its number is known and the primary issue can
link to it. If it didn't split, there's just one issue — skip straight to
writing it.

Write each issue body in intent-doc shape, adapted for an issue (no
`Source:`/`Slug:` fields, no `## Status` checklist — those only make sense
once there's a file to check items off in):

```
## Problem
<what's broken/missing/manual today, why it matters now>

## Scope
**In scope:** ...
**Out of scope (tracked in #<n>, if split):** ...

## Actors
<who triggers/uses this>

## Desired behavior
<plain-language happy path + the edge cases that already matter>

## Constraints / non-functional notes
<anything beyond the project's standard limits, or "none beyond the usual">

## Open questions
<anything genuinely undecided — don't silently pick for the user here>
```

A backlog/follow-up issue can be shorter — Problem + Scope + a short
"why this is separate/blocked" note is enough; it doesn't need the full
shape if most sections would just say "n/a, blocked."

Create with (label per the issue-labels setting; `enhancement` for a
feature idea):

```
gh issue create --title "<title>" --label enhancement --body "$(cat <<'EOF'
...
EOF
)"
```

Cross-link: the primary issue's Scope references the follow-up issue
number in "Out of scope"; if useful, the follow-up issue can note which
primary issue it was split from.

## Step 4 — Assign a milestone

Milestones here group issues by feature arc, not by release date or due
date. Before adding the issue(s) to the project board:

1. List open milestones:
   ```
   gh api repos/{owner}/{repo}/milestones --jq '.[] | "\(.number)\t\(.title)\t\(.description)"'
   ```
2. Judge whether the issue's theme genuinely fits one of them — the
   milestone's real subject, not a keyword overlap. A new widget idea fits
   a "UI component framework" milestone; a new content idea does **not**
   fit a "loader restructure" milestone just because it mentions the thing
   being loaded — that milestone is about the *pipeline*, not content built
   on it. Don't force a fit — a one-off idea with no real match should stay
   unmilestoned rather than get wedged into the closest-sounding one.
3. Confirm with `AskUserQuestion`: offer the best-matching existing
   milestone(s) as options, plus "Create a new milestone" and "Leave
   unmilestoned", recommending whichever you judged correct in step 2.
4. If creating new: milestones are titled `"<n>. <Title>"`, numbered
   sequentially — take the highest existing leading ordinal and add 1.
   Write a short **thematic** description (the goal/arc, not a list of
   tasks — task lists go stale as scope shifts). If the idea looks big
   enough to need several issues rather than just this one, stop and
   suggest `/devflow:brainstorm-milestone` instead of creating a single-issue
   milestone here. Otherwise:
   ```
   gh api repos/{owner}/{repo}/milestones -f title="<n>. <Title>" -f state="open" -f description="<theme>"
   ```
5. Assign the issue(s):
   ```
   gh issue edit <number> --milestone "<milestone title>"
   ```
   If the brainstorm split into primary + follow-up, both usually share
   the same milestone unless the follow-up is genuinely a different arc.

## Step 5 — Add to the project board and set priority

Every issue created this way goes on the project board. Add it and set its
`Priority` (whatever was settled in Step 2):

```
bash .claude/tools/set-project-field.sh <issue-url> Priority <P0|P1|P2>
```

The script reads the value back; report it set only if the read-back shows
it. Do this for each issue created in Step 3 — the primary and any
follow-up, using each one's own agreed priority.

## Step 6 — Report back

Tell the user the issue URL(s), the milestone (if any), the priority set
on each, and — in one line each — what's in scope for the primary issue
and what got split into the follow-up (if any). Don't propose next steps
beyond what was asked — if this brainstorm is likely to turn into a real
intent later, that's the user's call to make, not something to push in
this skill's output.
