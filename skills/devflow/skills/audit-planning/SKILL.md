---
name: audit-planning
description: Audit — and, with confirmation, correct — the repo's GitHub project board and milestones. Checks milestone naming/numbering convention and descriptions, that every open issue is labeled, sits in the milestone that actually fits it (not just any milestone), has a real description, and has a Priority set, and that milestone/issue ordering reflects actual build dependencies (a core restructure before the systems built on it). Also finds issues scattered across different milestones that share one theme and proposes consolidating them so they land in the same pass. Use for a periodic health-check or cleanup of the project board itself — not for filing new issues (that's brainstorm-issue/brainstorm-milestone).
---

This is the maintenance counterpart to `brainstorm-issue`/`brainstorm-milestone`:
those skills file new issues and milestones correctly; this skill checks that
what has already accumulated on the project board (`.claude/workflow.md`
project configuration) and in the repo's milestones still holds together.
Never file new issues or milestones here except as a corrective action the
user explicitly approved (e.g. creating a consolidation milestone in Step 6).

Takes an optional scope argument (a milestone number/title, or nothing for
the whole board). Default to the whole board unless the user names a scope.

## Step 1 — Gather the current state

Run this gathering step in a forked agent (`Agent` with
`subagent_type: "fork"`), not inline in the main session — the raw `gh`
JSON below (up to 500 issues, plus milestones and project items) is only
useful once joined into a summary table, so there's no reason to keep the
raw dump in context after that. Pull everything in one pass, no repeated
`gh` calls per issue (`<number>`/`<owner>` are the project board's):

```
gh api repos/{owner}/{repo}/milestones --jq '.[] | {number, title, description, state}'
gh issue list --state all --json number,title,body,labels,milestone,state,url --limit 500
gh project item-list <number> --owner <owner> --format json --limit 500
gh project field-list <number> --owner <owner> --format json
```

Join the issue list and project item list by issue `number`/`url` — the
project item list carries `status`/`priority`/`size` but not the issue body
or labels, and the issue list doesn't carry project-field values. Build one
table keyed by issue number with: title, state, labels, milestone, body (or
a body summary), status, priority.

Only keep **open** issues and **open** milestones in the table — a closed
issue's missing label/priority from before the repo settled on today's
conventions is historical, not a live problem, and rewriting closed history
isn't the point of this skill. Note closed-issue gaps only if the user asks
for a full historical audit.

Have the fork return the finished table as its result, not the raw `gh`
JSON it pulled — that table, not the raw pulls, is what Step 2 reads from.

## Step 2 — Run the checks

Work through each category below and collect findings. Don't fix anything
yet — Steps 4-6 handle that, after the user sees the full picture.

**a. Milestone naming & numbering.** Every milestone title must match
`"<n>. <Title>"`. Ordinals must be sequential starting at 1 with no gaps or
duplicates, in the order the milestones were actually opened (`gh api
.../milestones` returns creation order) — the number is a build-order label,
not just an ID, per `brainstorm-milestone` Step 3. Flag any milestone that
breaks the pattern, and any gap/duplicate/out-of-creation-order ordinal.

**b. Milestone descriptions.** Every open milestone needs a non-empty
description. Don't flag a short one-line description as wrong by itself —
`brainstorm-issue` Step 4 uses a short thematic line for single-issue
milestones, `brainstorm-milestone` Step 3 uses the full Problem/Scope/
Actors/Desired behavior shape for arc milestones, and both are legitimate
depending on how the milestone was created. Only flag it if it's empty, or
if it's enumerative (a task/issue checklist) rather than thematic — both
skills explicitly warn against that shape because it goes stale.

**c. Issue labels.** Every open issue needs at least one label. The
recognized labels are the ones the issue-labels setting maps to branch
prefixes (by default `bug`, `documentation`, and `enhancement` for
everything else). Flag unlabeled open issues. An issue with a label outside
that set isn't necessarily wrong — note it, don't auto-correct it.

**d. Issue descriptions.** Every open issue needs a real body, ideally in
the Problem/Scope/Actors/Desired-behavior/Constraints/Open-questions shape
`brainstorm-issue`/`brainstorm-milestone` use. Flag an empty body as a hard
finding; flag a one-liner with no structure as a soft finding (worth
improving, not broken).

**e. Milestone assignment and fit.** Two different findings here, don't
conflate them:
   - **Unmilestoned.** An open issue with no milestone. For each, judge
     (read its title/body against every open milestone's theme, same
     judgment call as `brainstorm-issue` Step 4) whether it genuinely
     fits one. Don't force a fit — some issues are legitimately standalone.
   - **Misfiled.** An open issue that *has* a milestone, but its actual
     content reads like it belongs to a different one — e.g. a content
     issue sitting in a "loader restructure" milestone (a pipeline
     milestone, not a content milestone). Judge this the same way: does the
     issue's real subject match the milestone's theme, not just a keyword
     overlap.

   For both, propose the best-fit target milestone (or "leave unmilestoned"
   for a genuinely standalone one) — this feeds Step 5.

**f. Priority.** Every open project-board item needs `Priority` set (`P0`/
`P1`/`P2`). Flag items where it's blank.

**g. Logical order.** Scan every open issue's and milestone's body for
dependency language — "Depends on #N", "blocked by", "prerequisite",
"Out of scope (tracked in #N)", "once #N lands" — and check the direction:
a prerequisite should carry a **lower** milestone/issue number than what
depends on it (built first). Flag any case where the numbering runs
backwards — e.g. milestone 6 says it needs milestone 9's work first, or
issue #80 says it depends on #95. Also flag a milestone whose *theme*
implies a dependency the text doesn't state — e.g. a milestone building
content on top of a data-driven pipeline, numbered before the pipeline
milestone, with no explicit dependency note explaining why that's safe.
This is the check the user is most likely to want explained in plain
language: a core restructure milestone should be numbered (and therefore
built) before the systems that get built on top of it, unless the issue
text explains why that ordering doesn't matter here.

**h. Cross-milestone clusters.** Independent of anything already
milestoned correctly: look across *all* open issues (any milestone, or
none) for a group that shares one real theme — same subsystem, same
follow-up chain, same "would naturally be built in one pass" shape — but is
currently split across different milestones (or partly unmilestoned).
This is about efficiency of execution, not misfiling: an issue can be
correctly filed under its current milestone by theme and still be part of
a cluster that would be cheaper to do together. Propose each cluster you
find as a candidate to consolidate in Step 6, with the specific issues and
why they cluster.

## Step 3 — Report the findings

Present one Markdown table per category from Step 2 that has any findings
(skip empty categories, don't pad the report with "no findings" rows for
everything). Each row: issue/milestone number, title, the problem, and the
proposed fix. Call out which fixes are mechanical (safe to batch-apply) and
which need a per-item human call — see Step 4's split — so the user can see
the shape of the cleanup before answering anything.

## Step 4 — Apply the mechanical fixes

These are narrow, reversible, single-field edits — batch them behind one
confirmation rather than asking per issue:

- Missing label -> `enhancement` (the default per the issue-labels
  setting), unless the issue's own content clearly reads as a bug report or
  docs change, in which case propose `bug`/`documentation` instead.
- Missing Priority -> recommend `P2` by default (same reasoning as
  `brainstorm-issue` Step 2: absent a signal otherwise, treat it as
  non-urgent backlog), unless the issue explicitly reads as blocking/urgent.

Use `AskUserQuestion` once to confirm the batch (apply all / review each /
skip) — this is a self-contained yes/no-shaped choice, not the kind of
multi-branching ambiguity `grilling` is for. If the user wants to review
each one, step through them one at a time with the same tool.

Apply approved fixes:

```
gh issue edit <n> --add-label "<label>"
bash .claude/tools/set-project-field.sh <issue-url> Priority <P0|P1|P2>
```

The script reads the value back — a fix that didn't land must not be
reported as applied.

## Step 5 — Resolve milestone assignment and fit, one call at a time

For every unmilestoned or misfiled issue from Step 2e, confirm the target
with `AskUserQuestion`: offer the best-fit existing milestone(s), plus
"leave unmilestoned"/"leave as-is" — mirroring `brainstorm-issue` Step 4.
Don't batch these the way Step 4's mechanical fixes are batched: a wrong
milestone move is a worse mistake than a missing label, and the best-fit
judgment genuinely varies issue to issue.

Apply approved moves:

```
gh issue edit <n> --milestone "<milestone title>"
```

## Step 6 — Resolve clusters and ordering problems

**Clusters (Step 2h):** for each proposed cluster, confirm with the user
whether to consolidate, and if so, which existing milestone should absorb
it or whether it warrants a new one. A cluster large enough to need its own
milestone should be created the way `brainstorm-milestone` Step 3 does
(sequential ordinal, thematic description) — don't shortcut that shape here
just because the issues already exist. Then move each clustered issue:

```
gh issue edit <n> --milestone "<target milestone title>"
```

**Ordering problems (Step 2g):** never auto-fix a numbering/renumbering
issue. Renaming a milestone's ordinal is mechanically safe for existing
issue associations (GitHub tracks the link by internal ID, not the title
string), but every other place that names the milestone in plain text —
other milestones' descriptions, issue bodies, `CLAUDE.md`/`docs/` — will go
stale and needs updating too. Report the full list of textual references
you find (`gh api .../milestones --jq` + a grep of issue bodies for the old
title) alongside the proposed renumbering, and only rename after the user
explicitly confirms, one milestone at a time:

```
gh api repos/{owner}/{repo}/milestones/<number> -X PATCH -f title="<new-title>"
```

Then fix every textual reference you listed, in the same pass, so nothing
is left pointing at the old name.

## Step 7 — Report back

Summarize: what was checked, what was fixed automatically (Step 4), what
was moved and where (Step 5), what clusters were consolidated (Step 6), and
— separately, clearly flagged — what still needs a human decision because
it wasn't resolved this pass (e.g. the user deferred a milestone move, or a
renumbering proposal wasn't confirmed). Don't propose further work beyond
what the audit surfaced.
