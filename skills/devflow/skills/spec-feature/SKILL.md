---
name: spec-feature
model: opus
description: Turn an approved intent doc into a reviewable Gherkin acceptance spec, looping between specs/intent/<slug>.md and specs/features/<slug>.feature until nothing's left ambiguous. Use for Step 2 of the spec-first workflow — after an intent doc exists (hand-written, or via spec-intent), before any implementation code is written.
---

You are turning a feature intent into a reviewable Gherkin acceptance
spec, through an iterative clarification loop. Do not write any
implementation code at any point in this skill.

Takes one input: a feature slug (from `args`). If not given, ask for it —
don't guess which intent doc this is for.

## Step 1 — Read intent, including prior clarifications

Read `specs/intent/<slug>.md`. If it does not exist, stop and tell the
user — do not create it yourself. Either they write it by hand (copy
`specs/intent/TEMPLATE.md`), or, if the intent already lives in a GitHub
issue, run the `spec-intent` skill to derive it from the issue instead.

If the file already has a `## Clarifications` section (format below),
read it fully before doing anything else. Do not ask a question that's
already been answered there.

## Step 2 — Generate or regenerate the .feature file from the intent doc only

Write `specs/features/<slug>.feature`, derived entirely from the current
state of the intent doc (including its Clarifications section) — never from
anything you were told that isn't reflected in the intent doc yet. If you're
about to write something into the .feature file that came from an answer
not yet recorded in the intent doc, stop and do Step 3/4 first.

Include:

- **Feature**: name, plus the description block that says what this file
  covers, what it supersedes, and what's explicitly out of scope — that
  block is the single source of truth for the file's coverage
  (`specs/features/README.md`), so keep it current on every regeneration
- **Background** (if multiple scenarios share setup)
- **Scenarios** in Given/When/Then form — happy path, at least one edge
  case, at least one failure/error case
- **Scenario Outline + Examples table** where behavior varies by input
- A trailing comment block listing **Non-goals**, **Risks**, and **Open
  questions** — anything still ambiguous, for the human reviewer

## Step 3 — Ask remaining questions, doubts, or problems

After generating/updating the spec, list anything still unclear: open
questions, ambiguous edge cases, conflicts you noticed between the intent
and the existing codebase. Use the `grilling` skill to ask them, not a
flat `AskUserQuestion` round or free-form prose — this loop routinely
surfaces several interdependent questions per pass (an edge case's answer
can gate what the next scenario even needs to ask), which is exactly the
frontier/rounds structure grilling is for. Anything answerable by reading
the codebase or the intent doc itself is your job to find, not the
user's — don't put it in the round.

## Step 4 — On receiving an answer, close the loop before continuing

When the user answers:

1. **Update the intent doc first.** Append the Q&A to the
   `## Clarifications` section (format below). This step is not optional
   and not deferrable — do it before touching the `.feature` file.
2. **Then regenerate `.feature` from the updated intent doc** (repeat
   Step 2), so the spec reflects the answer.
3. **Then re-run Step 3** — ask whatever's still open, which may now be a
   shorter list, or may include new questions the answer just raised.

Repeat Steps 3-4 until there are no remaining open questions.

## Clarifications section format (in the intent doc)

Append under a `## Clarifications` heading, creating it if it doesn't exist:

```
## Clarifications

- Q: [question as asked]
  A: [answer as given]
  Affects: [scenario name(s) or "general", if it changes a Gherkin scenario]
```

Keep entries in chronological order. Never delete or rewrite a past entry
— if a later answer contradicts an earlier one, add a new entry noting
the change rather than silently editing history.

## Stopping condition

Once there are no remaining open questions, stop. Do not start writing
implementation code, even partially, in this same turn — that's Step 4,
a separate handoff, and out of scope for this skill regardless of path.

Whether you then block on human approval depends on which path this
feature is on (`.claude/workflow.md`'s high-risk vs standard split — if
you haven't already classified it, do so now against the high-risk
triggers in its project configuration; one match is enough, default to
high-risk if genuinely unsure):

- **High-risk path**: tell the user the spec is ready for review at
  `specs/features/<slug>.feature`, and that you will not begin
  implementation until they approve it. This is `.claude/workflow.md`'s
  Step 3 — a real blocking gate, not a formality.
- **Standard path** (everything else, the default): tell the user the
  spec is ready at `specs/features/<slug>.feature`, and say explicitly
  that no approval gate blocks moving on — `.claude/workflow.md`'s Step 3
  is high-risk-path-only, so they're free to review it or not before
  Step 4 starts. Don't ask them to check it and don't wait for a
  response before considering this skill done.
