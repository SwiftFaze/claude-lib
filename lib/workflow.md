# Development workflow (spec-first agentic pipeline)

## Project configuration

Fill this in once per project. Every skill, agent and tool in this library
refers to these settings by name ("the verify command", "the project board")
instead of hard-coding a stack, a repo or a board. Replace the examples.

| Setting             | Value (examples: replace)                                                        |
|---------------------|----------------------------------------------------------------------------------|
| Base branch         | `develop`: feature branches fork from it and PR back into it                      |
| Release branch      | `main`: receives the base branch when a milestone ships                           |
| Verify command      | `mvn verify`: build, every test suite, coverage and structural gates              |
| Scenario command    | `mvn test -Dcucumber.filter.name="<scenario>"`: runs one acceptance scenario      |
| Run command         | `mvn compile exec:java`: launches the app for the human playtest                  |
| Mutation command    | `mvn pitest:mutationCoverage`, report in `target/pit-reports/`                    |
| QA command          | none, or a scripted replay per `.feature` (see `tools/check-qa-coverage.sh`)      |
| Clean Code gate     | `bash .claude/tools/check-clean.sh`                                               |
| Project board       | GitHub project `<number>`, owner `<owner>`; fields `Status`, `Priority` (`P0`/`P1`/`P2`) |
| Issue labels        | `bug` → `fix/`, `documentation` → `docs/`, anything else → `feat/`                |
| High-risk triggers  | auth, payments, data integrity / persistence formats, public APIs or contracts third parties depend on |
| Architecture doc    | `docs/architecture.md`                                                            |
| UI verification doc | `docs/ui-verification.md` (only if the project has a UI)                          |
| User-facing docs    | where user-visible behavior is documented (e.g. the GitHub wiki)                  |

Board fields are set with `bash .claude/tools/set-project-field.sh`, which adds
the issue to the board if needed and reads the value back.

## Two paths, chosen by risk

- **Standard path (the default)**: Steps 1, 4, 4.5, 5, 6, 7, 7.5. Write a
  short intent doc, then implement in an agile loop: build a slice, look at
  it, reconcile the intent doc with what was actually built, continue. The
  `.feature` file gets written during Steps 4-5 as behavior stabilizes; it
  must exist, be wired, and pass before done.
- **High-risk path**: adds blocking Steps 2-3 (approved Gherkin spec before
  any code). Triggers: the **high-risk triggers** above. One trigger is
  enough. If genuinely unsure, take the high-risk path: an unnecessary
  approval gate is cheaper than a skipped one. A contract CI already
  validates (e.g. with a schema check) is still high-risk to change on
  purpose: CI catching drift doesn't move the gate.

The split exists because a fully pre-approved spec doesn't survive contact with
implementation; plans made before an agent starts reliably diverge from what
gets built. Pay the approval latency only where being wrong is expensive.

## Steps

1. **Intent**: `specs/intent/<slug>.md` exists before code. If it doesn't,
   ask rather than guess. From a GitHub issue, use the `spec-intent` skill.
   Intent is not frozen: clarifying answers gathered later get appended here,
   and `.feature` is always derived from this file, never the reverse. Use
   extended thinking for the judgment-heavy parts (scope boundaries, what's
   in/out), not for reading files or running `gh`.
2. **Spec, high-risk path only**: generate `specs/features/<slug>.feature`
   from the intent doc via the `spec-feature` skill. No implementation code.
   Loops with Step 1: update the intent doc first, regenerate `.feature`, then
   ask what's still open.
3. **Human approval, high-risk path only**: stop and wait. Do not proceed on
   your own.
4. **Implementation** (`coder`, `.claude/agents/coder.md`): **run Steps 4-7
   through the `implement-issue` skill**. It owns the coder → commit →
   playtest → hardener handoff, prompt contents, verifying what comes back,
   and where the PR fits. The Clean Code gate belongs to the hardener
   (`.claude/agents/hardener.md`), not this step.
    - **Test-first.** Write the failing test before the code that passes it.
      Uncle Bob's three laws of TDD are the default loop, not an aspiration.
    - **Respect the module dependency direction** the project's architecture
      tests enforce. Fix a violation by inverting the dependency or extracting
      an interface, never by weakening the rule.
    - **Rendering/layout/sizing/text changes must be visually verified** when
      no test asserts on pixels or rendered text (technique: the UI
      verification doc). It doesn't replace the human playtest (Step 4.5);
      say which screens changed so the playtest covers them.

   **4.5. Human playtest**: the human runs the app (the run command) and tries
   what changed. Agents stop here and wait; they never tick this off.
5. **Acceptance tests** (`coder`, same agent as Step 4): wire the `.feature`
   file to the runner so it's executable, not documentation.
    - **If you touched a shared step-definitions file** (one that backs
      several features), run the verify command **twice** from clean and
      require identical results. One green run isn't evidence when shared
      test infrastructure changed.
6. **Mutation testing** (`hardener`, after the gate is clean): the mutation
   command against new/changed code (the check on the unit tests; confirm the
   new classes are in the mutation tool's target list).
7. **Documentation** (`hardener`, same agent as Step 6): part of done, not
   cleanup:
    - New domain concept, non-obvious design decision, or a deviation from an
      existing pattern → add/update an entry in `docs/`.
    - User-visible behavior or data → the user-facing docs too.
    - Added/renamed a `.feature` file, or changed what one covers → update that
      file's own `Feature:` description block (what it covers, what it
      supersedes, what's out of scope). There is no separate index to sync.
    - If nothing user-facing or architecturally significant changed, say so
      explicitly rather than skipping silently.
    - Narrative documentation goes in `docs/`, never into `CLAUDE.md`.

   **7.5. Close the linked issue** once its PR merges. PRs land on the base
   branch, which is usually not the repo's default branch, so `Closes #N` may
   not close it automatically: close it by hand (`gh issue close <n>`).

## Constraints (CI-enforced, not optional)

The project's static-analysis and coverage configuration defines the hard
limits. They fail the build, so don't re-derive them by eye. Record the
project's actual values here:

- Max function length `<n>` lines; max cyclomatic complexity `<n>`; max
  parameters `<n>`.
- Minimum line coverage `<n>%` repo-wide.
- Module dependency direction: `<the test that enforces it>`.

If a change can't meet a limit, stop and propose a decomposition rather than
disabling the check. **One narrow exception:** a method overriding a
library/framework interface whose signature mandates more parameters than the
limit may carry a parameter-count suppression. It applies to parameter count
only, never to complexity, length, coverage, or the module rule.

**SLAP (Single Level of Abstraction) is not enforced**: no tool backs it.
It's design guidance from the `uncle-bob-craft` checklist the hardener
applies (`.claude/agents/hardener.md`); don't describe it as a build gate.

These thresholds are a deliberate dial for agent-authored code, not a constant.
If you change one, record the new value and the reasoning here; don't loosen a
gate because one change didn't fit under it.

## Session management

Checkpoint at clean boundaries (tests green, nothing mid-edit) rather than
waiting for auto-compact to fire mid-thought. The agent can't run `/compact` or
`/clear` itself, so **surface the checkpoint to the user**: at the end of each
step, and in Steps 4-5 after each file or scenario is verified working, state
what's done and suggest clearing.

Between steps, prefer a fresh session once the step's artifact is on disk: the
next step's real memory is that artifact, not the conversation. Before clearing,
write a short status note in the PR description or commit message: which step
finished, which files were touched, what the next step does first. On resume,
read that note plus the git diff and the `.feature` file before opening anything
else (the `resume-issue` skill does this).

## What gets reviewed vs. not

| Artifact                    | Written by   | Reviewed by human?                          |
|-----------------------------|--------------|---------------------------------------------|
| Intent doc                  | Human/agent  | N/A: it's the source                        |
| Gherkin acceptance spec     | Agent        | High-risk: before implementation. Standard: after the fact |
| Implementation code         | Agent        | No, by design: leverage comes from not reading it |
| Unit tests                  | Agent        | No, by design                               |
| Mutation test results       | Tooling      | Human skims summary                         |
| Codebase docs, user docs    | Agent        | Spot check                                  |

## Notes for the agent

- If the intent doc is missing or ambiguous, use the `grilling` skill rather
  than inventing scope: it batches open questions into dependency-ordered
  rounds, which fits the intent/spec loop better than a flat prompt. Reserve
  `AskUserQuestion` for a genuinely standalone multiple-choice pick.
- Never mark a feature done without: the Clean Code gate at exit 0 with the
  judgment checklist answered, acceptance tests passing, the Step 7
  documentation decision stated explicitly, the human playtest (Step 4.5), and
  the linked issue closed (Step 7.5). A gate you cannot pass is a blocker to
  report, never a rule to suppress.
