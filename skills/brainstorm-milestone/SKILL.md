---
name: brainstorm-milestone
model: opus
description: Plan a big feature out loud, split it into a sequence of GitHub issues, and file them together under one new numbered milestone, skipping specs/intent/ entirely — the multi-issue sibling of brainstorm-issue. Use when the user wants to plan a feature arc big enough to need several issues, not spec it through the full intent -> .feature -> approval pipeline.
---

This is `brainstorm-issue` scaled up to a whole feature arc: same
pre-intent, straight-to-GitHub shape (no `specs/intent/` or
`specs/features/` writes — hand off to `/spec-intent`/`/spec-feature` if
the user wants that pipeline instead), but the destination is a
**milestone plus its issues**, not a single issue. Reach for
`brainstorm-issue` instead when the idea is a single self-contained
task — this skill is for when decomposition itself is part of the work: a
feature arc that naturally breaks into several dependent pieces.

## Step 1 — Ground the brainstorm in what actually exists

Same as `brainstorm-issue` Step 1, but broader: search the codebase for
every system the feature touches or extends, across all the pieces you
expect it to decompose into. Note what already exists (reuse/extend)
versus what's net-new. This matters more here than in the single-issue
skill — the boundary between "buildable now" and "blocked on something
that doesn't exist yet" is usually what determines the task split and
their order.

## Step 2 — Scope the arc and decompose it with the user

This step has more interlocking decisions than a single-issue brainstorm
does — the boundary, the split, and the dependency order between issues
all shape each other — so use the `grilling` skill for it instead of a
flat `AskUserQuestion` round. Invoke the Skill tool with `grilling` and
run its design-tree/frontier interview to settle, at minimum:

- **The outer boundary of the milestone** — what's in this arc at all
  versus clearly a separate, later concern. Recommend the smallest set of
  pieces that together deliver one coherent capability.
- **The decomposition into discrete issues.** Propose a split based on
  Step 1's findings — each issue should be independently completable and
  roughly similar in size to a normal `brainstorm-issue` issue. Don't
  propose a single giant issue "for the whole feature"; that defeats the
  point of this skill.
- **Dependency order between the issues.** Most feature arcs have a
  natural build order (foundation first, consumers after — e.g. a data
  schema before the loader that reads it, a framework before the widget
  built on it). This is usually downstream of the decomposition question
  in the design tree — don't ask it in the same round as a split it
  depends on.
- **Priority** for the milestone's issues — same P0/P1/P2 field as
  `brainstorm-issue` (recommend P2 by default, same reasoning). It's fine
  for issues within one milestone to carry different priorities if the
  arc is long — e.g. the first, unblocking piece can reasonably be higher
  priority than pieces several steps downstream.

Per `grilling`'s own rule, any of this you can determine by reading the
codebase (e.g. whether a piece is genuinely net-new or already has a
partial implementation) is your job to find, not the user's to answer —
dispatch that lookup rather than asking. The session isn't done until the
frontier is empty and the user has confirmed shared understanding; don't
move to Step 3 on a partial round.

If the grilling session reveals the arc is actually just one task, say so
and hand off to `brainstorm-issue` instead of forcing a milestone.

## Step 3 — Create the milestone

Milestones carry no due date and are titled `"<n>. <Title>"`, numbered
sequentially by when they were opened, not by priority.

1. Find the next number:
   ```
   gh api repos/{owner}/{repo}/milestones --jq '.[].title'
   ```
   Take the highest existing leading ordinal and add 1.
2. Write the description in the same intent-doc shape `brainstorm-issue`
   uses for an issue body, but pitched at the whole arc rather than one
   piece of it:

   ```
   ## Problem
   <what's broken/missing/manual across the whole arc today, why it matters now>

   ## Scope
   **In scope:** <the capability this milestone delivers as a whole, once every issue in it lands>
   **Out of scope:** <what's explicitly a separate, later concern>

   ## Actors
   <who triggers/uses the resulting capability>

   ## Desired behavior
   <plain-language end state once the arc is complete>

   ## Constraints / non-functional notes
   <anything beyond the project's standard limits, or "none beyond the usual">

   ## Open questions
   <anything genuinely undecided at the arc level>
   ```

   Stay **thematic, not enumerative**: describe the goal/arc, never a list
   of its issues or their build order — no issue numbers, no per-issue
   checklist. Task lists go stale as scope shifts; ordering and
   dependencies belong on the issues themselves (cross-links in their
   bodies, per Step 4), not the milestone description.
3. Create it (pipe the body in rather than inlining it, since it's
   multi-line):
   ```
   gh api repos/{owner}/{repo}/milestones -f title="<n>. <Title>" -f state="open" -f description="$(cat <<'EOF'
   ...
   EOF
   )"
   ```

## Step 4 — File the issues, in dependency order

File issues in the build order agreed in Step 2 — foundational pieces
first — so later issues can cross-link back to real issue numbers rather
than forward references.

Use the same body shape as `brainstorm-issue`:

```
## Problem
<what's broken/missing/manual today, why it matters now>

## Scope
**In scope:** ...
**Out of scope (tracked in #<n>, if applicable):** ...

## Actors
<who triggers/uses this>

## Desired behavior
<plain-language happy path + the edge cases that already matter>

## Constraints / non-functional notes
<anything beyond the project's standard limits, or "none beyond the usual">

## Open questions
<anything genuinely undecided>
```

Every issue after the first in the chain should name what it depends on
explicitly in its own body — a `## Problem` opening with "Depends on #<n> —
can't be spec'd/built against real code until that lands," or an
`**Out of scope (tracked in #<n>):**` line pointing forward from an earlier
issue to a later one. This is how the build order stays visible on the
issues themselves rather than only in this conversation or the milestone
description.

Create each with:

```
gh issue create --title "<title>" --label enhancement --body "$(cat <<'EOF'
...
EOF
)"
```

Then assign it to the milestone from Step 3:

```
gh issue edit <number> --milestone "<n>. <Title>"
```

## Step 5 — Add each to the project board and set priority

Same as `brainstorm-issue` Step 5, for every issue created in Step 4:

```
bash .claude/tools/set-project-field.sh <issue-url> Priority <P0|P1|P2>
```

Report a priority set only if the script's read-back shows it.

## Step 6 — Report back

Tell the user: the milestone title/number and URL, then each issue in
build order with its number, URL, priority, and a one-line scope. Don't
propose next steps beyond what was asked.
