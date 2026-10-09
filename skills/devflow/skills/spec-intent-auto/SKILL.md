---
name: spec-intent-auto
description: Run the entire standard-path spec-first pipeline (intent -> spec -> implementation -> acceptance tests -> mutation testing -> docs) unattended for a simple feature, from a GitHub issue number straight through to "ready for playtest" — answering trivial ambiguities itself and front-loading any real ones, so the only human checkpoint is one final playtest right before the PR is opened. Use for small, well-scoped issues that don't need the user present for the whole run — not for high-risk work (auth/payments/data-integrity/public APIs), which stays on the high-risk path's blocking gates.
---

Unattended variant of the spec-first pipeline (`.claude/workflow.md`).
Where `spec-intent` + `spec-feature` + the Step 4-7 handoff still stop to
ask the user everything, and the normal Step 4.5 playtest sits
mid-pipeline, this skill collapses all of that into one continuous run with
exactly **one** human checkpoint: a final playtest, positioned right before
the PR is opened instead of between Steps 4 and 5. Everything before that
checkpoint happens without asking the user to confirm intermediate steps.

This is a deliberate, scoped deviation from the normal step order — don't
generalize it back into `.claude/workflow.md` or the other pipeline
skills. It only applies within a run of this skill.

**Only for the standard path.** Takes one input: a GitHub issue number (or
URL), same as `spec-intent`. If not given, ask for it. Accepts the same
optional `parallel` suffix; pass it through to Step 1, and run every later
step from inside the resulting worktree.

## Step 0 — Classify risk before doing anything else

Read the issue (`gh issue view <n> --json number,title,body,url,labels,state`)
and classify it against the high-risk triggers in `.claude/workflow.md`'s
project configuration — one matching trigger is enough, default to
high-risk if genuinely unsure.

If it's high-risk, **stop immediately** and tell the user this skill is
standard-path only — point them at `spec-intent` + `spec-feature` instead,
which preserve the real human approval gate that class of feature needs.
Do not proceed, do not ask "are you sure" — just decline and explain why.

If `state` is `CLOSED`, tell the user and confirm before continuing.

## Step 1 — Intent, branch, and board (same as spec-intent)

Follow `spec-intent`'s Steps 2-5 exactly: derive the slug, pick the
branch prefix from labels, check for a branch-name collision, create and
link the branch off the base branch, move the issue to `In progress` on
the project board, and derive `specs/intent/<slug>.md` from the issue body.

## Step 2 — Resolve open questions: answer trivial ones, front-load real ones

This is the one place in the whole run where the user might hear from you
before the final playtest — and it should happen now, in one pass, not be
discovered mid-implementation later.

For each open question the intent doc (or your own read of the codebase)
surfaces, classify it:

- **Trivial — decide it yourself** when the answer is a mechanical default
  already established elsewhere: an existing pattern in the codebase to
  follow 1:1, a naming/formatting convention, a choice with no real
  downstream consequence, or something fully answerable by reading the
  code/docs. Record your decision and reasoning in the intent doc's
  `## Clarifications` section (same format `spec-feature` uses) but
  labeled `A (auto-decided):` instead of `A:`, so a later human reviewer
  can tell at a glance which answers were never actually asked.
- **Real — ask now, all at once** when the answer changes scope,
  user-facing behavior, data shape, or has more than one reasonable design
  with genuinely different tradeoffs. Use the `grilling` skill for this —
  one full round (or the minimum number of dependency-ordered rounds), not
  a question dribbled out later. **When in doubt, treat it as real and
  ask** — a wrong autonomous guess here is expensive precisely because
  nothing checks it again until the playtest at the very end.

After any real-question round is answered, update the intent doc's
Clarifications section per the normal `A:` format before continuing.

Do not proceed past this step with any open question left silently
unresolved either way.

## Step 3 — Feature spec (same as spec-feature, no approval gate)

Follow `spec-feature`'s Step 2 to generate `specs/features/<slug>.feature`
from the now-settled intent doc, and commit it on the branch
(`implement-issue` refuses an uncommitted spec).

Since Step 0 already confirmed this is standard-path work, there is no
Step 3 approval gate to wait for (`.claude/workflow.md`'s Step 3 is
high-risk path only) — move straight to implementation.

## Step 4 — Coder, then hardener, per implement-issue

Run the `implement-issue` skill's sequence with one change: **no mid-pipeline
playtest.** Dispatch `coder`, verify it, then go straight to `hardener` and
verify that — both exactly as `implement-issue`'s "Dispatching" and
"Verifying what comes back" sections say, including the escalation ladder.
Don't open the PR at the end of that sequence; that is this skill's Step 6.

The playtest is the one step this skill deliberately relocates: it happens
once, at the very end (Step 5), not between the two agents. Include in the
coder's prompt the `A (auto-decided):` entries from Step 2, so it builds what
was decided rather than re-deciding it.

## Step 5 — Stop here: the one human checkpoint

This is the only point in the run where you wait for the user. Report,
in one message:

- Branch name and what issue/slug it covers.
- A short summary of what was implemented (not a full diff dump).
- The coder's and hardener's commit shas, confirmation that the verify
  command and the Clean Code gate are green when you ran them, and the
  mutation counts for the changed classes.
- Any `A (auto-decided):` entries from Step 2, so the human can see what
  was decided without them, not just what was asked.
- Explicit instructions for the playtest: the run command, and what
  specifically to try given what changed.
- That you're waiting for either "looks good" or a bug report before
  going further — nothing is pushed yet.

Do not push or open a PR before this confirmation. If the user reports a
problem instead, resume the coder with it (`implement-issue`'s hand-back),
re-run the hardener and its verification, and ask for the playtest again —
don't silently re-expand scope while you're at it.

## Step 6 — Push, open the PR

Once the user confirms the playtest passed:

1. Update the intent doc's Status checklist (Implemented, Manually
   playtested, Acceptance tests passing, Mutation testing passed,
   Documentation updated — all now true).
2. Push the branch.
3. Open the PR against the base branch (never the release branch), with
   `Closes #<n>` in the body and what the playtest covered, in the user's
   words.
4. Report the PR URL and stop. Merging is a separate, human-driven action
   outside this skill's scope.
