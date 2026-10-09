---
name: implement-issue
description: Run Steps 4-7 of the spec-first pipeline on the current feature branch — dispatch the coder, verify it, stop for the human playtest, dispatch the hardener, verify it (gate, mutation scope, behavior diff, docs decision), and only then open the PR. Use once a .feature is committed; --from-hardener <sha> starts at hardening. Not for writing the spec (spec-feature) or resuming a dead session (resume-issue).
---

The entry point for Steps 4-7 of `.claude/workflow.md`: implementation,
hardening and the PR. Counterpart to `/devflow:spec-intent` and `/devflow:spec-feature`, which
own Steps 1-2. It owns the **sequence** and the **verification**. The work stays
in the plugin's `agents/coder.md` and `hardener.md`, and the mechanical gates stay in
the verify command and the Clean Code gate (`.claude/workflow.md` project
configuration): name them here, never restate their thresholds or how to pass
them. Each agent's model, tools, ownership and reading scope live in
the plugin's `agents/`; don't restate them.

Takes no required input. It works on the checked-out branch: the slug is the
branch name minus its `feat/`/`fix/`/`docs/` prefix, the issue number comes from
that slug's `specs/intent/<slug>.md` `Source:` line. If either can't be read,
ask — don't guess. Optional `--from-hardener <sha>`: skip to step 4 with `<sha>`
as the baseline (a hand-written commit, or one already built and playtested).

## Sequence

1. **Refuse without a committed spec.** `specs/features/<slug>.feature` must be
   committed on this branch (`git ls-files --error-unmatch`, clean in
   `git status`). If not, stop and point to `/devflow:spec-feature`. Don't write the
   feature yourself.
2. **Dispatch `coder`, verify its commit.** Run the verify command yourself
   (below). **Then QA, if the project configures a QA command:**
   `bash .claude/tools/check-qa-coverage.sh`. A changed `.feature` with neither
   a `specs/qa/<slug>.*` procedure nor a `QA: none - <reason>` line blocks the
   handoff: get a procedure or the line first. Then run each changed feature's
   procedure with the QA command. It narrows step 3, doesn't replace it.
3. **Stop for the Step 4.5 human playtest** (`.claude/workflow.md`). Say which
   screens changed (the coder's note), what the tests don't cover, and the run
   command to launch it. Wait for the human.
4. **Dispatch `hardener`** with the coder's sha, then verify it (below),
   including the docs decision.
5. **Open the PR, only here.** Base: the base branch. The body has
   `Closes #N` and what the human playtest covered, in the human's words:
   ask, don't invent it. Never mention or open a PR before this step, including
   after a spec-only push — a PR opened then would close its issue on an
   unbuilt feature. Merging is the human's.

With `--from-hardener`, do steps 4-5 only; every hardener verification still runs.

## Dispatching

- **Coder → commit → hardener, one after the other, on the feature branch.**
  Dispatch `subagent_type: "devflow:coder"`; verify its commit; stop for the playtest;
  then dispatch `subagent_type: "devflow:hardener"` with the coder's sha. The commit is
  the handoff: the hardener starts from a clean diff, and each role's work can
  be checked on its own.
- **Default to these agents, not `/fork`.** A tight prompt on a pinned cheap
  model beats a fork's inherited context on the pricier parent model. Explore
  once yourself and compress it into the prompt: file paths with line numbers,
  the actual code referenced (not just its name), and the decisions already
  made. UI work: include the project's styling guide itself, not a summary.
  Fork only when the material is too sprawling to excerpt for less than
  forking costs.
- **Parallel tickets:** one coder per ticket in its own git worktree; that
  ticket's hardener runs in the same worktree.

## Verifying what comes back

**Never relay a subagent's "done" report as fact without checking it yourself.**
A summary describes what the agent intended to do, not what it did. Before
treating any step as finished: open the file it claims to have produced, run the
command it claims passed, read the actual diff. Confidence and detail in a
report are not evidence.

It's unconditional because a near-maximal defensive prompt doesn't prevent it:
a handoff with full file contents, literal code, a "don't explore" instruction
and a verification checklist has still produced an agent that explored anyway
and self-reported done when it wasn't.

**After the coder:** the commit exists, the verify command passes when you run
it, and the diff matches the ticket.

**After the hardener, run the Clean Code gate yourself first.** It's the
identical command the hardener had to pass. Then read its report for: exit 0;
a disposition for every **advisory** finding; and a PASS/FAIL *with evidence
naming a file, method or test* on every judgment-checklist line. A checklist
returned without evidence is the same signal as a skipped step. Also confirm
`git diff <coder-sha>..HEAD` changes no behavior: no edited test expectation
or `.feature` scenario. If the work was in a worktree, run it there.

Specific checks:

- **A passing metric isn't evidence unless its scope is confirmed.** A mutation
  score can be genuinely green while measuring the wrong code — e.g. computed
  before the new classes were in the mutation tool's target list. Find each
  changed class in the mutation report yourself.
- **A mandatory step can't be silently skipped, downgraded, or rationalized
  away.** An agent that can't complete one should stop and report the blocker,
  not proceed with a caveat or substitute a weaker check. A report mentioning a
  skipped mandatory step is a first-class finding, not a footnote.
- **A green acceptance suite doesn't prove keyboard/focus behavior.** If the
  feature involves focus crossing a window or component boundary, confirm at
  least one scenario exercises real input, not just a programmatic shortcut.
- **The docs decision is checked against the diff, not the report.** Read
  `git diff <coder-sha>..HEAD --stat` and the diff itself; a miss goes back to
  the hardener naming the specific doc:
  - User-visible behavior or data changed → the user-facing docs.
  - A contract between packages or layers changed → the architecture doc.
  - A `.feature` added or changed → its `Feature:` block still says what it
    covers, supersedes and excludes.
  - "Nothing user-facing or architecturally significant changed" → the diff
    must actually show that. It's the one claim you can't take on trust.

## Escalation when verification finds a real problem

The ladder applies to each role separately.

1. **First failure.** Resume the same agent via `SendMessage` with the specific
   problem, the fix, and evidence (actual error, diff, file content), not "this
   didn't work, try again." Most corrections land here.
2. **Second failure of the same class.** Switch to `/fork`, which inherits the
   diagnosis. Only after a second same-class failure, not the first.
3. **If the fork fails the same check,** the problem is in the diagnosis, not
   the executing agent. Stop and reconsider.

**Hardener → coder hand-back.** When the hardener reports that a gate needs a
behavior change, that's a handoff, not a failure. Resume the *original* coder
via `SendMessage` with the hardener's finding (it still holds the
implementation context, so this is cheaper than briefing a new coder), verify
its new commit, then resume the hardener with the new sha.

Give a fork a tight checklist, cheapest and most failure-prone checks first, so
the highest-value ones are done even if it runs out of budget.
