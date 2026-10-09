---
name: repo-review
description: Deep-dive review of a GitHub repo, written as a dated, titled HTML report inside the repo itself (docs/reviews/). Two scopes. "since" reviews what happened since the last review or a date/ref: commits, PRs, issues, CI runs and minutes, releases, delivered vs. asked, bugs in merged code, skipped steps, TODOs. "full" scans the repo as it stands now. Either scope can focus on a topic: tests/coverage, CI/CD, security, architecture, data/migrations, billing, dependencies, performance, or any custom subject. Bugs are verified in code, findings carry stable IDs and are followed up from one review to the next, and a registry remembers where each repo stopped. Use whenever the user asks to review, audit, scan, catch up on or report on a repo ("what happened since last time", "review today's work", "full scan of test coverage", "audit the CI", "where are the gaps", "fais-moi un rapport"), even without the word "review", and when they ask which repos have been reviewed or when.
argument-hint: "[full | since <date|ref|last>] [topic…] [repo path]"
---

# Repo review

An honest, evidence-based, deep review of a repo. It is written as a self-contained HTML report in the reviewed repo, and the registry remembers where the review stopped.

The user is usually a **consultant or reviewer, not the person doing the work**. On the repo, the skill is read-only apart from the report file:
- no commits, `git add`, pushes or merges;
- no edits, comments or labels on PRs and issues;
- no installs, and no commands that modify tracked files.

The report goes into the working tree as an **untracked file**. Committing it is the user's call. If something needs fixing, the report says so.

## 1. Parse the request

Arguments are free text. Read these out of them:

| Parameter | Values | Default |
|---|---|---|
| **scope** | `full`: the repo as it stands now (HEAD of the current checkout). `since <X>`: what changed after X, where X is a date ("2026-10-01", "Monday", "yesterday"), a git ref (tag, SHA, branch, read as its commit date), or `last` | a topic given without a scope → `full`; nothing given → `since last` |
| **topic** | `all` (activity review), `tests`, `ci`, `security`, `architecture`, `data`, `billing`, `deps`, `perf`, or any custom subject; several may be combined | `all` for `since`; for `full` with no topic, ask which topic, suggesting `all` as a broad health check |
| **repo** | a path or `owner/repo` | the current working directory's git repo |

Examples:
- `/repo-review` → since the last review, everything.
- `/repo-review full tests` → whole repo, test coverage and quality.
- `/repo-review since 2026-10-01 ci` → CI/CD changes since 1 October.
- `/repo-review security` → full security scan.

`since last` uses the registry: the latest `history` entry for the same topic, otherwise `last_run`. First review of a repo with no date given: ask how far back to go, suggesting 7 days.

If the user asks "which repos have been reviewed / when", answer from the registry and stop.

## 2. Files

- **Registry:** `~/repo-reviews/registry.json` (in the user's home directory). Create it if it's missing.
- **Report:** `<repo>/<report_dir>/<YYYY-MM-DD>-<topic-slug>-<scope>.html`, for example `docs/reviews/2026-10-09-tests-full.html` or `docs/reviews/2026-10-09-all-since.html`.
  - `report_dir` comes from the registry entry, otherwise `docs/reviews`. Create the folder if needed.
  - Add `-2`, `-3`… if the name is taken.
  - Several topics give a slug like `tests-ci`.
  - Never overwrite a previous report.
- **Scripts** next to this file:
  - `scripts/collect.sh <repo> <since ISO UTC> <out>`: activity since a date (commits, PRs, issues, CI runs and minutes, tags, added TODOs and suppressions).
  - `scripts/inventory.sh <repo> <out>`: snapshot of the repo now (rules files, size, test map, hot spots, all TODOs and suppressions, workflows, open PRs and issues).
- **Topic checklists:** `references/topics.md`. Read the section for each requested topic before investigating.
- **Report template:** `assets/report-template.html`.

Write collector output to the session scratchpad (or another temp dir), never into the repo.

Registry entry, keyed by `owner/repo`:

```json
{
  "path": "/home/me/code/my-app",
  "report_dir": "docs/reviews",
  "language": "en",
  "last_run": "2026-10-09T19:11:29Z",
  "last_report": "/home/me/code/my-app/docs/reviews/2026-10-09-all-since.html",
  "heads": { "develop": "d6e1ea63…", "main": "a8fe1721…" },
  "history": [
    { "date": "2026-10-09", "scope": "full", "since": null, "topic": "tests",
      "report": "/home/me/code/my-app/docs/reviews/2026-10-09-tests-full.html", "heads": { "develop": "d6e1ea63…" } }
  ],
  "notes": "Durable context: who works on it, conventions, standing decisions."
}
```

`last_run` and `last_report` track the activity reviews (`since` with topic `all`), which is what "since last time" means by default. `history` records every report. Keep `notes` short, and update it when you learn something that will still matter next time.

## 3. Collect

- **`since`:** run `collect.sh` with the start date. Also run `inventory.sh` when a topic other than `all` is requested, since topics need the current state as well as the changes.
- **`full`:** run `inventory.sh`. Add `collect.sh` for the last 30 days when CI cost or recent activity matters to the topic.
- If a script fails (gh not authenticated, no remote, Windows path issues), say so and fall back to what git alone can show.
- In `full` mode, check `meta.txt`: if the checkout is behind origin or dirty, say which state you reviewed. Never switch branches or pull in the user's checkout.

Then read the context before judging anything:
- the repo's rules (`rules.txt`: AGENTS.md, CLAUDE.md, CONTRIBUTING, ADRs, test and CI docs);
- its glossary, if it has one;
- the previous report for this repo and topic. Parse its `<script id="review-data">` JSON to get the open findings and their IDs. Older Markdown reports: read their findings section.

## 4. Investigate: the deep dive

Depth is the point of this skill. A review that only lists file counts is not done.

**4a. Plan.** From the topic checklists and the collected data, list the investigation areas, ranked by risk:
- access control and security;
- money;
- data loss;
- deployment;
- user-facing features;
- everything else.

In `full` mode, start with hot spots × untested × risky. Write the plan down (internally) before reading code.

**4b. Fan out when the scope is large.** For a `full` scan, or a `since` period with more than ~10 merged PRs, run **parallel read-only sub-agents**. Use the `Explore` agent for locating code and `general-purpose` for judging it. Launch them in one message, in the foreground. Running this skill is the user's request for them.
- Use 2–5 agents, each with one area or one axis.
- In an activity review, Spec and Standards are separate agents, as in a two-axis code review. Never merge or rerank the two axes against each other.
- Each prompt contains:
  - the repo path;
  - the exact files or diff range;
  - the relevant topic checklist, pasted in full;
  - the repo rules that apply;
  - this brief: *"Read-only. Report each finding as: claim, file:line, quoted evidence, concrete failure scenario, suggested fix, and whether you confirmed it in code or only suspect it. Also report what you checked and found fine, and what you could not check. Under 600 words."*

For a small scope, investigate inline.

**4c. Go to the code yourself.** Diffs are `git diff <base> origin/<branch> -- <path>` or `git show <sha>`. Also do the following when they apply:
- run the test suite or other cheap read-only commands, if the topic calls for it;
- compare similar code paths: one guarded and one not is the strongest evidence of a bug;
- search the whole repo before claiming something is missing ("no X anywhere in `src/`").

**4d. Verify every finding.** Before anything goes into the report as **confirmed**, open the cited file at the current HEAD and check the claim yourself, including the findings that sub-agents report. Anything you can't confirm becomes **plausible** and goes under "To check", together with what would confirm it. Drop anything that turns out wrong.

For each finding, record:
- **ID:** topic prefix plus number, such as `T-04`. Reuse the previous report's ID when it is the same finding;
- **severity:** critical, high, medium or low;
- **verdict:** confirmed or plausible;
- **status:** new, still open, worse, or fixed (against the previous report);
- **where:** file:line, PR or issue;
- **what, why it matters, fix:** "why it matters" is a concrete failure scenario, not a generic risk.

**Judge as well as list.** Credit good work specifically: a strong test, a careful guard, a well-scoped PR. Be calibrated, and say "not verified" where that is the truth. Say what you covered in depth, what you only skimmed, and what you didn't cover.

## 5. Write the HTML report

Start from `assets/report-template.html`. Keep its CSS tokens, the filter script, the pinned Mermaid import and the `review-data` JSON block. Fill in the placeholders and delete sections that would be empty. Write in the registry's `language` for that repo (default English).

- **Title:** names the review, for example "Test coverage review", "CI/CD review", "Activity review: 1–9 Oct", or "Full health check". Put it in `<title>`, `<h1>` and the JSON block, together with the date, the repo and the scope chips.
- **Structure:**
  1. Header: title, repo, date, scope, topic, and the method / covered / not covered list.
  2. Summary: 3–6 sentences, a few stat tiles and the verdict table.
  3. Picture: optional; see "Diagrams" below.
  4. Findings: grouped by area or axis, and within each group ranked by severity. For an activity review: Spec axis, Standards axis, bugs, skipped steps, TODOs, process, CI usage.
  5. Good.
  6. To check.
  7. Previous review follow-up.
  8. Recommended actions: numbered, most important first. For each one: which finding IDs it covers, whether it needs a new issue, a comment on an existing issue or a decision, and who would do it.
- **Finding cards:** one `<article class="finding <severity>" id="<ID>" data-sev="<severity>">` each, with ID, title, badges, location, What, Why it matters, Fix, and the evidence collapsed in `<details>`.
- **Diagrams:** use Mermaid when a picture explains faster than prose:
  - a timeline or gitGraph for a period;
  - a flowchart of a pipeline or of the call path behind a bug;
  - a pie of coverage or CI minutes;
  - before/after flowcharts for architecture candidates.

  Inside Mermaid nodes, avoid `|`, `;` and `#`. Escape `<`, `>` and `&` in all HTML text, and in code inside `<pre>`.
- **JSON:** the `review-data` block lists every finding (`id`, `title`, `severity`, `verdict`, `status`, `where`, `area`). It must be valid JSON. Check it with `node -e` or `python -c` before finishing.

## 6. Update the registry

Do this only after the report is written.
- Append a `history` entry.
- For a `since` review with topic `all`, also set `last_run` to `collected_at` from `meta.txt`. Use that value rather than "now", so anything that happened during the review is picked up next time. Also set `last_report` and `heads`.
- `full` scans and topic-only reviews never move `last_run`.
- Update `path`, `report_dir` and `notes` if they changed.

## 7. Tell the user

- Open the report in the browser: on Windows `start "" "<path>"`; on macOS `open`; on Linux `xdg-open`.
- Give its path, and remind the user that it is untracked in the repo.
- List the 3–5 most important findings with their IDs, and anything that needs the user's decision.
- Don't paste the report into the chat.
- If there are actionable findings, offer to draft the issues, but don't file them unless asked.
