---
name: brainstorm-repo-review
description: Brainstorm the recommended actions of a repo-review HTML report with the user, the same way brainstorm-issue does (grounded in the code, then grilling rounds), and write the outcome into that same report instead of filing anything. The outcome is the decisions taken and issue drafts in the repo's own issue template, with priority, labels, milestone and dependencies. Use when the user wants to reply to, react to, discuss, triage or turn into issues the plan or findings of a repo review ("reply to this plan", "brainstorm the review", "let's go through the actions", "turn the review into issues"), or names /devflow:brainstorm-repo-review.
argument-hint: "[report path | latest] [action numbers or finding IDs, e.g. 1-3 or T-16]"
---

# Brainstorm a repo review

This is the `brainstorm-issue` method applied to a review's plan:
1. ground the plan in the code;
2. settle the scope with the user in `grilling` rounds;
3. draft the issues.

The destination is different. Everything lands in the review's HTML report: a **Brainstorm** section holds the decisions and the issue drafts, ready to copy.

**The only output is the HTML report.** This skill never writes to GitHub or to git:
- no `gh issue create`, `gh issue edit` or `gh issue comment`;
- no milestones or labels created or edited (`gh api` writes);
- no project-board changes;
- no commits.

This holds even if the user asks mid-session. In that case, say that filing is outside this skill and leave it to them. The drafts are written so the user, or the repo's maintainer, can copy them into GitHub themselves.

`gh` is used read-only: listing issues, labels and milestones in Step 1.

## Step 0: Pick the report and the slice

- **Report:** a path the user gives. Otherwise use `latest`, the newest `history[].report` in `~/repo-reviews/registry.json` for the current repo that is an `.html` file. If there is only a Markdown report, say so and suggest running `/devflow:repo-review` first.
- **Slice:** the action numbers or finding IDs the user names. Otherwise use the whole "Recommended actions" list. If that list has more than ~5 actions, the first grilling round asks which ones to take now.
- Read the report: header, findings, To check, Recommended actions, and the `review-data` JSON. If the report already has a `brainstorm-data` block, read it as well. Earlier decisions stand unless the user reopens them, and a draft that already exists is updated, not duplicated.

## Step 1: Ground it in what exists now

Before asking anything:
- **Has the code moved?** Compare the report's `heads` with the current `origin/<branch>`. If HEAD moved, re-open the file:line of every finding in the slice and note any that are fixed, moved or changed. A draft must never ask to fix something that is already fixed.
- **Does something already track it?** Run `gh issue list --state open --search "<keywords>"` for each action, and use the issue numbers the report already cites (e.g. #738). An existing issue gets a *comment draft* or a scope extension, never a duplicate.
- **What does the repo expect an issue to look like?** Find:
  - its issue template (`.github/ISSUE_TEMPLATE/*`) and its issue or cadrage skill (`.claude/skills/issue`, `cadrage`), plus any rules in AGENTS.md or CONTRIBUTING;
  - its labels (`gh label list`) and open milestones (`gh api repos/{owner}/{repo}/milestones --jq '.[] | "\(.number)\t\(.title)\t\(.description)"'`);
  - the language its issues are written in.

  Drafts follow that template, use those labels and milestones, and are written in that language. If there's no template, use the intent shape from `brainstorm-issue`: Problem, Scope (in/out), Actors, Desired behavior, Constraints, Open questions.
- **What do the actions depend on?** Order the actions so that dependencies come first. For example, a structural guard test before back-filling the cross-org tests, or #736 before #738.

## Step 2: Scope it with the user, in grilling rounds

Use the `grilling` skill: rounds over the decision tree. Each question is numbered, comes with a recommendation, and is written so the user can answer it cold: context first, a concrete example, then the pick and why.

Settle at least these:
- **Which actions become issues now**, and how they group. One issue per action is the default. Merge actions only if they ship together; split one if part of it is blocked or clearly later.
- **For each issue:** what is in and out of scope (the smallest coherent slice), its priority (with the repo's labels), whether it touches a risky area (the repo's own definition), its milestone, and its dependencies ("Dépend de #N" / "Depends on #N").
- **Product decisions only the owner can make.** Examples from a review: whether a commenter may delete others' comments; whether to cancel or refuse when deleting a paying account; GDPR suppression rules. These go to the user, and to the maintainer named in the repo rules if the user defers.

Decide the technical details yourself. If the code answers a question, look it up instead of asking. Ask a plain single-choice question with `AskUserQuestion` only when nothing else hangs off the answer.

Each answer goes into the decisions log, with who decided: the user, "recommendation accepted", or "deferred to <maintainer>".

## Step 3: Draft the issues

For each issue, record:
- the **title**, written for a non-developer when the repo asks for that;
- the **body**, in the repo's template, filled in from the findings. Quote the file:line, the failure scenario and the test that proves the fix. A bug fix states the test that reproduces it;
- the **finding IDs it covers**, such as `T-01 T-02 T-03`;
- the proposed **labels, priority, milestone**, dependencies and risk flag;
- the **follow-up issue**, if the scope split. Draft the follow-up first so the primary issue can refer to it ("Out of scope: see I-02");
- for an **existing issue**: a comment draft and the scope it adds, instead of a new body.

Give drafts local IDs (`I-01`, `I-02`…). Keep them stable across sessions on the same report.

## Step 4: Write it into the report

Read `assets/brainstorm-section.html` (next to this file) and follow its comments.
- On the first run, insert its CSS before `</style>` and its script before `</body>`. Insert the section before `<footer>`, and add a `Brainstorm` link to `nav.toc`.
- Each session adds a dated block with its decisions table. Drafts are updated in place by their `I-xx` ID.
- Fill the `brainstorm-data` JSON block and validate it (`node -e` / `python -c`). Escape `<`, `>` and `&` in the HTML. The Markdown body in each draft's `<pre>` must be exactly what would be filed.
- In each covered finding card, add a line `<p class="drafted">Drafted as <a href="#I-01">I-01</a></p>` to the card's body. Don't change any other part of the review.
- Run the repo-review screenshot check (`node ~/.claude/skills/devflow/skills/repo-review/scripts/screenshot.cjs <report> <scratch>`) and look at the Brainstorm section.

## Step 5: Report back

- Open the report (`start "" "<path>"` on Windows) and give the link to `#brainstorm`.
- List each draft in one line: ID, title, priority, milestone, findings covered.
- List the decisions still deferred to someone else.
- Mention anything that turned out fixed or already tracked in Step 1.

Stop there. Don't file, and don't offer to file.

If the user later says that a draft was filed (e.g. "I-02 is #745"), update only the report: set that draft's status badge to `filed #745` with a link, and set `"filed": 745` in `brainstorm-data`. Later repo reviews also detect filed drafts on their own by searching issue titles.
