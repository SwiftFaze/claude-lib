---
name: close-milestone
description: Close a finished milestone and promote it to release — verifies every issue in the milestone is closed and no PR is still awaiting merge into the base branch, closes the milestone, then opens/merges the base-into-release-branch promotion PR that triggers the release pipeline. Use when the user says a milestone is done and should ship, not for filing or auditing milestones (that's brainstorm-milestone/audit-planning).
---

Closing counterpart to `brainstorm-milestone` (which files milestones) and
`audit-planning` (which health-checks them). This skill ships one: it is the
last step in a milestone's life, not a health check, so it changes state
(closes the milestone, merges into the release branch) rather than just
reporting. "The base branch" and "the release branch" are the settings in
`.claude/workflow.md`'s project configuration.

Takes one input: a milestone number or title (matching the `"<n>. <Title>"`
convention documented in `audit-planning`). If not given, list open
milestones and ask which one — this is a standalone, self-contained pick
with nothing else riding on it, so use `AskUserQuestion`, not `grilling`:

```
gh api repos/{owner}/{repo}/milestones --jq '.[] | select(.state=="open") | {number, title, open_issues, closed_issues}'
```

## Step 1 — Resolve the target milestone

Match the input against the open-milestones list from above: by number
directly, or by title (exact match first, then substring). If nothing
matches, or more than one title substring-matches, stop and ask rather than
guessing which milestone was meant.

## Step 2 — Verify every issue in the milestone is closed

```
gh api repos/{owner}/{repo}/milestones/<n> --jq '{open_issues, closed_issues}'
```

If `open_issues` is 0, continue. Otherwise list the offending issues and
stop — do not close a milestone with open work still tracked under it:

```
gh issue list --milestone "<n>. <title>" --state open --json number,title,url
```

Report each one's number/title/url and tell the user to close or re-milestone
them first (per `.claude/workflow.md` Step 7.5, a PR merging into the base
branch may not auto-close its issue when the base branch isn't the repo's
default branch — it may just be waiting on that manual close).

## Step 3 — Verify no PR is awaiting merge into the base branch

Any open PR targeting the base branch is unfinished work that hasn't reached
the release branch yet, independent of which milestone it's filed under —
promoting now would ship without it and make it awkward to land after the
fact.

```
gh pr list --base <base branch> --state open --json number,title,headRefName,url,isDraft
```

If any come back (draft or ready-for-review, doesn't matter), list them and
stop. Tell the user to merge, close, or explicitly defer each one before
re-running this skill — don't decide that for them.

## Step 4 — Confirm before touching the release branch

Everything past this point is hard to reverse and visible to others: closing
the milestone, and — if there's anything to promote — merging into the
release branch, which may trigger a real release (tag, GitHub Release,
build artifacts, deploy). Confirm once with `AskUserQuestion` before
proceeding, stating plainly what will happen: "Close milestone `<n>. <title>`
(all `<closed_issues>` issues done) and merge `<base branch>` into
`<release branch>`, triggering <whatever the release pipeline does>.
Proceed?" Recommend "Proceed" as the default option since Steps 2-3 already
passed.

## Step 5 — Close the milestone

```
gh api repos/{owner}/{repo}/milestones/<n> -X PATCH -f state=closed
```

## Step 6 — Promote the base branch into the release branch

First check there's actually something to promote:

```
git fetch origin
git log origin/<release branch>..origin/<base branch> --oneline
```

If that's empty, the release branch is already even with the base branch —
tell the user there's no release to trigger, milestone closure alone is the
complete outcome this run, and stop here (don't open an empty PR).

Otherwise check there isn't already a stale promotion attempt open:

```
gh pr list --base <release branch> --state open --json number,title,headRefName,url
```

If one exists, stop and point the user at it instead of opening a duplicate.

Open the promotion PR — its title/body is where the milestone gets
referenced in what triggers the release:

```
gh pr create --base <release branch> --head <base branch> \
  --title "chore: promote milestone <n>. <title> to release" \
  --body "Promotes <base branch> into <release branch>, closing out milestone #<n> — \"<title>\" (<closed_issues> issues).

Closed issues: <#a, #b, #c, ...>"
```

Then merge it, waiting for required checks rather than forcing through
them:

```
gh pr merge <number> --merge --auto
```

**If a required check fails:** report it plainly (quote the check's failure
message). If it's a check that doesn't expect the base branch as a PR head
(a branch-name rule, for instance), suggest fixing the workflow to exempt it
in a small separate PR. Never route around a required check (no `--admin`
merge, no disabling the check) to force this one through.

## Step 7 — Best-effort: record the release on the milestone

Optional, and skip it without ceremony if the project has no tagged
releases or nothing shows up. The milestone itself can't carry a changelog
entry, but its description can note which version it shipped in, which is
a real, durable reference.

Poll for the resulting release, a handful of times a couple minutes apart:

```
gh release list --limit 1 --json tagName,publishedAt,url
```

If a new stable tag (`vX.Y.Z`, no pre-release suffix) appears whose
`publishedAt` is after this run started, append a line to the milestone's
existing description (don't overwrite it):

```
gh api repos/{owner}/{repo}/milestones/<n> -X PATCH -f description="<existing description>

Shipped in <tagName> — <release url>"
```

If nothing shows up within a handful of checks, stop polling and just tell
the user the milestone closed and the promotion merged, but the release
hadn't published yet as of this run — they can check `gh release list` and
patch the milestone description themselves later if they want that record.

## Step 8 — Report back

One short summary: milestone closed (number/title), whether anything was
promoted (PR number + merge result, or "nothing to promote"), and whether
Step 7's release note landed or was left for later. If Step 2, 3, or 6 (a
failing required check) stopped the run early, that's the report instead —
state exactly what's blocking and what the user needs to do before
re-running.
