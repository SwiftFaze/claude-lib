# claude-lib

Reusable Claude Code skills, agents and tools for a spec-first, agent-driven
development pipeline: intent doc → Gherkin spec → test-first implementation
(`coder`) → clean-code hardening and mutation testing (`hardener`) → PR, with
GitHub issues, milestones, a project board and repo reviews for planning.

## Layout

This repo is checked out as `~/.claude` itself. Its `.gitignore` ignores
everything (credentials, history, sessions, settings) except the library:

| Path                  | What it is                                                         |
|-----------------------|--------------------------------------------------------------------|
| `skills/devflow/`  | The **`devflow` plugin**: `.claude-plugin/plugin.json`, `skills/`, `agents/` |
| `lib/`                | Per-project templates: `workflow.md`, `tools/`, `specs/`           |

A folder in `~/.claude/skills/` that has a `.claude-plugin/plugin.json` loads
as a plugin in every session, with no install step (it shows up as
`devflow@skills-dir`). Edits apply at the next session or after
`/reload-plugins`.

## Names: everything is prefixed

Plugin skills and agents carry the plugin name, so they never collide with a
project's own skills of the same name:

- Skills: `/devflow:spec-intent`, `/devflow:brainstorm-issue`, …
- Agents: `devflow:coder`, `devflow:hardener`

In a project that has its own `brainstorm-issue` (for example), `/brainstorm-issue`
runs the project's and `/devflow:brainstorm-issue` runs this one.

### Turn the library off in one project

From that project's directory:

```
claude plugin disable devflow@skills-dir --scope local
```

or open `/plugin` → Installed → `devflow` and disable it there. Local scope
writes to the project's `.claude/settings.local.json`, so other projects are
unaffected. `claude plugin enable … --scope local` turns it back on.

## Set up a project for the pipeline

| From `~/.claude/lib` | To the project          |
|----------------------|-------------------------|
| `workflow.md`        | `.claude/workflow.md`   |
| `tools/`             | `.claude/tools/`        |
| `specs/`             | `specs/` (repo root)    |

The pipeline skills and agents stay in the plugin; they read the project's
`.claude/workflow.md`. Then:

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

**Review skills**: `repo-review` (dated HTML report on a repo's activity or
current state, with a cross-repo registry in `~/repo-reviews/`),
`brainstorm-repo-review` (turn a review's actions into decisions and issue
drafts), `uncle-bob-craft` (design review lens), `token-usage-analyzer`
(session transcript cost audit).

**Agents**: `coder` (haiku), `hardener` (sonnet).

**Tools** in `lib/tools/` (`bash`; the gates assume a Maven/Java build):

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

`.gitattributes` keeps every `.sh` file on LF line endings, so the scripts run
under bash from a Windows checkout.
