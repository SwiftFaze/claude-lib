# Uncle Bob Craft — Expanded Reference

This document expands the criteria referenced in the main skill
([SKILL.md](./SKILL.md)). Sources: *Clean Code*, *Clean Architecture*, *The
Clean Coder*, *Clean Agile* (Robert C. Martin). This is a self-contained
summary for agent use, not a substitute for the books — there is no
separate `@clean-code` skill or deeper `references/` folder to consult
beyond this file; everything this skill covers lives in `SKILL.md` and
here.

---

## Clean Architecture

### Dependency Rule

Source code dependencies must point only **inward** (toward higher-level policies). Inner layers do not know about outer layers (e.g., use cases do not import from the web framework or the database driver).

- **Violation**: A use case that imports from Express, Django, or a concrete repository implementation.
- **Correct**: Use case depends on an interface (e.g., `OrderRepository`); the adapter in the outer layer implements it and uses Express/DB.

**Without inversion**: Use case imports and calls `SqlOrderRepository` directly → use case depends on the DB.
**With inversion**: Use case depends on `OrderRepository` (interface); `SqlOrderRepository` implements it and is injected at the edge — the use case stays independent of SQL.

### Layers (hexagonal / ports and adapters)

| Layer | Responsibility | Depends on |
|-------|----------------|------------|
| Entities | Core business entities and rules | Nothing (innermost) |
| Use cases | Application-specific business rules, orchestration | Entities |
| Interface adapters | Convert data between use cases and external world | Use cases, entities |
| Frameworks & drivers | DB, UI, HTTP, file I/O | Interface adapters |

### Boundaries

A **boundary** is an interface or abstract type that inner code depends on and outer code implements. Good boundaries make it easy to swap implementations (an in-memory repo for tests, a SQL repo for production). Draw a boundary where there's a genuine reason to vary or replace something (different persistence, different UI, different transport) — not preemptively.

### SOLID in architecture context

- **SRP** — A module should have one reason to change (one actor). E.g., separate "report formatting" from "report calculation" if they change for different reasons.
- **OCP** — Extend behavior via new implementations of interfaces (new adapters), not by editing existing use-case or entity code.
- **LSP** — Any implementation of a repository or gateway interface must be substitutable without breaking the use case.
- **ISP** — Small, focused interfaces (e.g., `ReadOrderRepository` and `WriteOrderRepository` if read and write evolve differently) instead of one fat `OrderRepository`.
- **DIP** — Use cases depend on `OrderRepository` (interface); the composition root wires in `SqlOrderRepository`. High-level policy does not depend on low-level details.

### Component design (cohesion and coupling, for larger systems)

When grouping classes into **components** (modules, packages):

**Cohesion:**
- **REP (Reuse/Release Equivalence)** — The unit of reuse is the unit of release; group classes that are reused and released together.
- **CCP (Common Closure)** — Classes that change for the same reasons belong in the same component; reduces the impact of change.
- **CRP (Common Reuse)** — Classes reused together should be packaged together; avoid forcing dependents to pull in more than they need.

**Coupling:**
- **ADP (Acyclic Dependencies)** — The component dependency graph must have no cycles.
- **SDP (Stable Dependencies)** — Depend in the direction of stability; less stable components depend on more stable ones.
- **SAP (Stable Abstractions)** — Stable components should be abstract; unstable components can be concrete.

Use this when discussing module/package boundaries beyond single layers.

---

## The Clean Coder

### Professionalism

- **Do no harm** — Don't leave the codebase in a worse state than you found it; leave a clear TODO if you must leave a mess, and prefer leaving it better (the "boy scout rule").
- **Work ethic** — Know your craft, practice, stay current. Estimate only what you understand enough to estimate.
- **Saying no** — Say no when a request is unreasonable or would compromise quality; offer alternatives (e.g., "We can do X by date Y if we drop Z").
- **Saying yes** — When you commit, mean it; communicate early if a commitment can't be met, rather than missing it silently.

### Estimation

- **Three-point estimates** — Best case, nominal, worst case; use for planning and risk, not as a single "promise" number.
- **Velocity** — Use historical velocity for iteration planning; don't inflate commitments off one fast iteration.
- **Uncertainty** — Communicate uncertainty; prefer ranges over false precision.
- **Refusal to estimate** — It's professional to decline a date when the request is vague or the work unknown; offer to break it down first, or give a range after discovery.

### Sustainable pace

- Avoid sustained overtime; it reduces quality and long-term output.
- Tests and refactoring are part of the job, not "extra" — the first thing to protect under pressure is the test suite and the ability to refactor safely.

### Tests as requirement

- Code without tests is legacy by definition. Writing and maintaining tests is a professional requirement, not optional.

### Mentoring and collaboration

- Helping others (mentoring, pairing) and leaving the team and codebase better are part of professionalism.

---

## Clean Agile

### Values (from the Agile manifesto, emphasized by Uncle Bob)

- Individuals and interactions over processes and tools.
- Working software over comprehensive documentation.
- Customer collaboration over contract negotiation.
- Responding to change over following a plan.

The right-hand side still has value; the left-hand side is preferred when there's a trade-off.

### Iron Cross (four values that support the above)

| Value | Meaning |
|-------|--------|
| **Communication** | Prefer high-bandwidth communication; reduce information loss. |
| **Courage** | Courage to refactor, to say no, to change design when the code tells you to. |
| **Feedback** | Short feedback loops (tests, demos, iterations) — learn fast what works. |
| **Simplicity** | Do the simplest thing that could work; avoid speculative design. |

### Practices

- **TDD** — Red, green, refactor: write a failing test first, then minimal code to pass, then refactor. Tests act as specification and safety net.
- **Refactoring** — Continuous small improvements; keep tests green; improve structure, names, and design in small steps.
- **Pair programming** — Two people at one machine; improves design/quality and spreads knowledge. Not mandatory every hour, but a recognized practice for hard or critical work.
- **Simple design** — No duplication, express intent, minimal elements, small abstractions; add complexity only when the code actually asks for it (e.g., a third duplication).

---

## Smells and Heuristics (expanded)

### Design smells (from Clean Code / Clean Architecture)

| Code | Name | Brief |
|------|------|--------|
| **Rigidity** | Hard to change; one change triggers many. | Reduce coupling; introduce boundaries. |
| **Fragility** | Breaks in unexpected places. | Isolate changes; improve tests. |
| **Immobility** | Hard to reuse. | Extract reusable parts; reduce coupling. |
| **Viscosity** | Easy to hack, hard to do right. | Make right thing easy (abstractions, tests). |
| **Needless complexity** | Speculative or unused design. | YAGNI; remove until needed. |
| **Needless repetition** | DRY violated. | Extract common logic; name the abstraction. |
| **Opacity** | Hard to understand. | Rename, extract, clarify intent. |

### Heuristics (review checklist style)

- **C1 / Naming** — Names reveal intent; no disinformation (e.g., `accountList` when it isn't a list).
- **C2 / Functions** — Small, one thing, one level of abstraction. On argument count specifically: niladic/monadic/dyadic (0-2 args) are the ideal range; triadic (3) should be used only with good reason; polyadic (4+) needs very special justification and should generally be avoided — treat 4+ as a smell to justify, not a target to design toward, even where the project's CI gate technically permits more than that (see `.claude/workflow.md`'s Constraints section for the actual enforced ceiling — that number is a hard technical limit, not evidence that 4-5 args is fine).
- **C3 / Comments** — Prefer self-explanatory code; good comments explain why, not what.
- **C4 / Formatting** — Newspaper metaphor; vertical density; variables declared near their use.
- **C5 / Error handling** — Exceptions over return codes; don't return or pass null without a clear contract.
- **C6 / Tests** — F.I.R.S.T.; TDD when applicable.
- **C7 / Classes** — Small, single responsibility; stepdown rule.
- **T1 / Boundaries** — Dependencies point inward; no outer details in inner layers.
- **T2 / SOLID** — Check SRP, OCP, LSP, ISP, DIP in context.
- **T3 / Patterns** — A pattern is used to solve a real problem, not for show.

---

## Design patterns (when and when not)

- **Use** when: you have repeated variation (Strategy), lifecycle/creation complexity (Factory/Builder), or a clear cross-cutting concern (logging, validation at a boundary).
- **Avoid** when: the code is simple and a pattern would add indirection without reducing duplication or clarifying intent.
- **Cargo cult** — Applying a pattern by name everywhere (e.g., everything is a Factory) without a design reason. Symptoms: a Factory that only calls `new`, a Strategy with one implementation and no plan for a second. Prefer "the simplest thing that could work" until duplication or a change axis actually appears.
- **Good signals** — the pattern name appears in design docs/comments where it helps; there are at least two concrete variants or a clearly stated reason for future variation; tests and call sites are simpler because of the abstraction (e.g., a test can inject a fake repository).

---

## Scope and attribution

This file is the complete reference for this skill — there's no separate
deep-dive folder or companion skill to consult beyond `SKILL.md` and this
document. It's a summary for agent use, not a substitute for the source
books.

*Attribution: Principles and structure drawn from Robert C. Martin, Clean Code (2008), Clean Architecture (2017), The Clean Coder (2011), Clean Agile (2019).*
