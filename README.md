# claude-lib

Reusable Claude Code skills, agents and tools for a spec-first, agent-driven
development pipeline: intent doc → Gherkin spec → test-first implementation
(`coder`) → clean-code hardening and mutation testing (`hardener`) → PR, with
GitHub issues, milestones and a project board for planning.

## Install into a project

| From this repo  | To the project          |
|-----------------|-------------------------|
| `workflow.md`   | `.claude/workflow.md`   |
| `agents/`       | `.claude/agents/`       |
| `skills/`       | `.claude/skills/`       |
| `tools/`        | `.claude/tools/`        |
| `specs/`        | `specs/` (repo root)    |

Then:

1. Fill in the **Project configuration** table and the **Constraints** values
   at the top of `.claude/workflow.md`. Every skill and agent refers to those
   settings by name (base branch, verify command, project board, high-risk
   triggers…).
2. Set `PROJECT_NUMBER` / `PROJECT_OWNER` in `tools/set-project-field.sh` (or
   the environment) if you use a GitHub project board.
3. Add the `specs/intent/` ignore rules from `specs/intent/README.md` to
   `.gitignore`.
4. Point the project's `CLAUDE.md` at `.claude/workflow.md`.

## Contents

**Pipeline skills**: `spec-intent` (issue → branch + intent doc),
`spec-feature` (intent → `.feature`), `implement-issue` (coder → playtest →
hardener → PR), `spec-intent-auto` (the whole standard path unattended),
`resume-issue` (pick up a dead session).

**Planning skills**: `brainstorm-issue`, `brainstorm-milestone`,
`audit-planning`, `close-milestone`, `grilling`.

**Standalone skills**: `uncle-bob-craft` (design review lens),
`token-usage-analyzer` (session transcript cost audit).

**Agents**: `coder` (haiku), `hardener` (sonnet).

**Tools** (`bash`; the gates assume a Maven/Java build):

- `check-clean.sh`: the diff-scoped Clean Code gate (PMD, CPD, SpotBugs,
  text smells, optional CRAP) plus the judgment checklist.
- `check-quality-gates.sh`: fails a PR that weakens JaCoCo/PIT/PMD gates in
  `pom.xml`.
- `check-instruction-budget.sh`: line budgets for `CLAUDE.md`, workflow,
  agent and skill files.
- `check-qa-coverage.sh`: every changed `.feature` has a QA procedure or a
  `QA: none - <reason>` line.
- `check-jqwik-canary.sh`: pins jqwik's agent-directed console output to an
  audited text (only for projects using jqwik).
- `set-project-field.sh`: sets a project-board field and reads it back.
