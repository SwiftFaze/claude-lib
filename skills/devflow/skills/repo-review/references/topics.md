# Topics: what a deep dive checks

Each topic lists **where to look**, **questions to answer** and **evidence to gather**. These are starting points, not a fence. Follow anything that smells wrong, even if the list doesn't mention it.

In **since** mode, apply the topic to what changed in the period, plus whatever the changes touch. In **full** mode, apply it to the repo as it stands, starting with the hot spots (`hotspots.txt`) and the riskiest areas: auth and access control, money, data, deployment.

Each topic has an ID prefix for its findings, so IDs stay stable from one review to the next: `A` activity, `T` tests, `C` CI/CD, `S` security, `R` architecture, `D` data, `B` billing, `P` dependencies, `F` performance, `X` to check.

---

## all: activity review (the default for `since`)

Everything that happened in the period. This was the skill's original purpose.

- **Spec axis: delivered vs. asked.** For each closed issue or merged PR, does the merged code do what the issue's scope said? Quote the scope line for each gap.
  - **Missing or partial:** the issue asked for it, and the code doesn't fully do it.
  - **Scope creep:** the code does something nobody asked for.
  - **Implemented wrong:** it looks done, but the logic is wrong.

  A deviation announced and justified in the PR is fine; note it. A silent one is a finding.
- **Standards axis: the repo's own rules.** Check the work against the repo's rules (`rules.txt`: AGENTS.md, CONTRIBUTING, ADRs).
  - Required steps skipped: a fix with no regression test, a missing acceptance checklist, a PR merged on red checks, a direct push.
  - Smells in the diff, always labelled as judgement calls: duplicated logic, a mysterious name, shotgun surgery (one change scattered over many files), speculative generality, a primitive standing in for a domain type.

  Keep the two axes in separate groups, and don't rank one against the other. A change can follow every rule and still build the wrong thing.
- **Bugs** in the merged code. Confirm each one in the current code.
- **Signals from the collector:**
  - TODOs added without an open issue;
  - suppressions added (`suppressions.txt`), and why;
  - tests removed or loosened (`git diff <base> -- '*test*'`; look for deleted `expect`s and changed thresholds).
- **Process:** superseded PRs left open, duplicate work, stale Dependabot or security PRs, red CI left alone, releases not deployed, branches that should be gone.
- **CI minutes** against any budget the repo mentions.
- **Deadlines:** anything dated that will bite, such as expiring exceptions, certificates or scheduled jobs.
- **Follow-up** of the previous report's findings, by ID.

## tests: test coverage and test quality

**Where:** `tests.txt`, `test-map.txt`, `test-map-summary.txt`, `hotspots.txt`, the test configs (vitest/jest/pytest/playwright…), the CI jobs that run them, and the repo's testing rules.

**Map the layers.** For each layer (unit, integration, end-to-end, contract, mutation, scripts), record:
- how many test files and tests it has;
- what it runs against (mocks, a real DB, a browser);
- when it runs (every PR, nightly, by hand);
- how long it takes.

Run the fast suite if it can run without installing anything or touching tracked files, and report pass, fail and skip counts.

**Find gaps by risk, not by percentage:**
- **Entry points:** server actions, API routes, webhooks, cron handlers, CLI commands. Count them, then count how many any test calls.
- **Guards:** auth, tenant isolation, roles, plan limits. Is each guard tested on both the allowed and the refused path? Is there anything that stops a new entry point from shipping without a guard (a structural test, a lint rule)?
- **Money and data:** billing, credits, deletions, bulk rewrites, migrations, idempotency of webhooks and jobs.
- **Hot spots with no test:** join `hotspots.txt` with the `NONE` rows.
- **Pure functions with no test:** these are the cheap wins.
- **User journeys** the product promises but no end-to-end test walks through.

**Judge quality, not just presence.** Sample 5–10 test files from the riskiest areas and check:
- Do they assert outcomes, or only that "it didn't throw"?
- Do they cover the refused path and the error path?
- Do the mocks hide the real risk? A mocked DB in a test about a query is a warning sign.
- Do they check database state after an action?

Also look for flaky patterns (sleeps, real clocks, order dependence), skipped or `.only` tests (`suppressions.txt`), and thresholds lowered in recent history.

**Measurement:** is there a coverage report? Mutation testing? When did it last run, and what did it score?

`test-map.txt` is a proxy that matches files by name. `IMP` only means some test imports a file with that name, so verify any gap you report before stating it.

## ci: CI/CD and delivery

**Where:** `.github/workflows/*`, deploy scripts, `workflows.txt`, `ci-runs.txt`, `ci-failures.txt`, `ci-minutes.txt`, the branch and release rules.

- **The path to prod, end to end.** What gates each step (tests, lint, typecheck, build, security scan, manual approval)? Can a step be skipped: `if:` conditions, `continue-on-error`, `paths-ignore`, `workflow_dispatch` shortcuts? Draw it as a `.flow` diagram (the template's chart kit).
- **Is what runs in CI what the rules say runs?** Compare the workflows with AGENTS.md or CONTRIBUTING step by step.
- **Reliability:** failure rate per workflow, recurring failures, cancelled runs that hid a red result, flaky jobs.
- **Secrets and permissions:** the `permissions:` block per workflow, `pull_request_target`, secrets reaching fork PRs, third-party actions pinned by SHA or by tag.
- **Cost:** minutes per workflow and per day against the budget; jobs that could be cached, skipped or merged.
- **Rollback:** is there a tested way back? Are destructive migrations guarded?
- **Deploy scripts:** error handling (`set -e`), idempotency, what happens on a half-done deploy.

## security

**Where:** auth and session code, middleware/proxy, every entry point, `.env.example`, secret handling, the dependency audit, CI permissions.

- **Access control on every entry point:** authentication, then authorization, then tenant scoping in the query itself (child IDs scoped by parent or organisation). Sample widely; in full mode, enumerate them.
- **Injection:** raw SQL, shell, HTML (`dangerouslySetInnerHTML`), SSRF on fetched URLs, path traversal on uploads.
- **Tokens and secrets:** where they are stored, logged or put in URLs, how long they live, comparisons that should be timing-safe.
- **Webhooks:** signature verification, replay and idempotency.
- **Public endpoints:** rate limits, enumeration, information in error messages.
- **Dependencies:** known vulnerabilities (`npm audit --omit=dev --json` or the equivalent, read-only), abandoned packages.

## architecture

**Where:** the largest files (`largest.txt`), hot spots, the import graph of the busiest areas, ADRs and the glossary.

- **Shallow modules:** an interface nearly as complex as its implementation. **Deep modules** are the goal: a small interface over a lot of behaviour.
- **The deletion test:** would deleting the module concentrate complexity (it earns its place), or just move it elsewhere (it's shallow)?
- **Locality:** understanding one concept requires bouncing between many files. Pure functions extracted for testing while the bugs live in how they're called.
- **Leaks across seams:** coupling between modules that should be independent; the same switch on the same type in many places.
- **God files:** files over ~1,000 lines that change often. Show their churn.
- **Testability:** which areas are hard to test through their current interface?

Don't re-argue a decision an ADR records unless the friction is real; say so explicitly. For each candidate, give the files, the problem (one sentence), the solution (one sentence), the gains, and a before/after diagram (`.compare` with `.box`, `.box.deep`, `.box.leak`). Rate each one *Strong*, *Worth exploring* or *Speculative*.

## data: database and migrations

**Where:** the schema, migrations, migration scripts and guards, backup docs, and code doing bulk writes or deletes.

- Migrations: destructive changes (drop, rename, type change, NOT NULL on existing data, data rewrites); whether they are reversible; whether they are compatible with the version still running (zero-downtime).
- Constraints that the code assumes but the schema doesn't enforce (uniqueness, foreign keys, cascades).
- Transactions: multi-step writes outside a transaction; check-then-insert under the default isolation level.
- Deletion paths: what a cascade deletes; soft vs. hard deletes; personal-data (GDPR) deletion.
- Backups: do they exist, has a restore ever been tested, what is the retention?

## billing

**Where:** payment SDK calls, webhooks, subscription sync, plan limits, credits, invoices, e-mails.

- Every state change from the payment provider maps to the right access change, and back. Downgrade, cancellation, failed payment, trial end, refund.
- Idempotency under retries and concurrent deliveries.
- Paths that delete or orphan a paying customer (account or organisation deletion).
- Is the API version pinned? Are there tests against signed events or a mock server?

## deps: dependencies

**Where:** the manifests, lockfile, Dependabot or Renovate config, open dependency PRs.

- Majors behind, and what blocks them; open security alerts; unused dependencies; duplicate libraries for the same job; licences when it matters.

## perf: performance

**Where:** hot request paths, N+1 queries, big payloads, bundle size, slow CI or tests.

- Queries in loops; missing indexes for frequent filters; unbounded `findMany`; work that could be cached; client bundles that pull in server-sized libraries.

## Custom topic

The user may name anything (`i18n`, `accessibility`, `the canvas`, `onboarding`, `issue #123`). Build a checklist like the ones above in the same shape:
- where to look;
- the 5–10 questions that matter for that topic;
- the evidence each answer needs.

Write it into the report's Method line so the next run can repeat it.
