---
name: uncle-bob-craft
description: Use when performing code review, writing or refactoring code, or discussing architecture — applies Robert C. Martin (Uncle Bob) criteria (Clean Architecture, The Clean Coder, Clean Agile, design-pattern discipline) as a complement to language-specific style, not a replacement for the project linter/formatter or the mechanical complexity/coverage checks in `.claude/workflow.md`.
---
# Uncle Bob Craft

Apply Robert C. Martin (Uncle Bob) criteria for **code review and production**: Clean Code, Clean Architecture, The Clean Coder, Clean Agile, and design-pattern discipline. This skill is complementary to the project's own linter and to the mechanical constraints already enforced in `.claude/workflow.md` (max function length, cyclomatic complexity, parameter count, coverage, module dependency direction) — it does not replace them. Much of it is mechanized in the Clean Code gate (`bash .claude/tools/check-clean.sh`), which the hardener must pass before reporting a task finished. Use this skill for the design lens behind those rules and for the judgment the gate cannot make. SLAP is the clearest case: still no tool checks it, so it appears as a judgment-checklist line the gate prints and you answer, not as a build gate.

## Overview

This skill aggregates principles from Uncle Bob's body of work for **reviewing** and **writing** code: naming and functions, architecture and boundaries (Clean Architecture), professionalism and estimation (The Clean Coder), agile values and practices (Clean Agile), and design-pattern use vs misuse. Use it to evaluate structure, dependencies, SOLID in context, code smells, and professional practices. It provides craft and design criteria only — not syntax or style enforcement, which remain the responsibility of the linter/formatter and the CI-enforced constraints in `.claude/workflow.md`.

## When to Use This Skill

- **Code review**: Apply Dependency Rule, boundaries, SOLID in context, and smell heuristics; suggest concrete refactors. Pairs with the built-in `/code-review` skill — use this one for the architecture/design lens, `/code-review` for correctness and simplification findings.
- **Refactoring**: Decide what to extract, where to draw boundaries, and whether a design pattern is justified.
- **Architecture discussion**: Check layer boundaries, dependency direction, and separation of concerns — see the project's architecture doc (`.claude/workflow.md` project configuration) for its actual layering.
- **Design patterns**: Assess correct use vs cargo-cult or overuse before introducing a pattern.
- **Estimation and professionalism**: Apply Clean Coder ideas (saying no, sustainable pace, three-point estimates).
- **Agile practices**: Reference Clean Agile (Iron Cross, TDD, refactoring, pair programming) when discussing process.
- **Do not use** to replace or override the project's linter, formatter, automated tests, or the mechanical constraints already enforced in `.claude/workflow.md`.

## Aggregators by Source

| Source | Focus | Where to go |
|--------|--------|-------------|
| **Clean Architecture** | Dependency Rule, layers, boundaries, SOLID in architecture, component cohesion/coupling | See [reference.md](./reference.md)'s "Clean Architecture" section. |
| **The Clean Coder** | Professionalism, estimation, saying no, sustainable pace | See [reference.md](./reference.md)'s "The Clean Coder" section. |
| **Clean Agile** | Values, Iron Cross, TDD, refactoring, pair programming | See [reference.md](./reference.md)'s "Clean Agile" section. |
| **Design patterns** | When to use, misuse, cargo cult | See [reference.md](./reference.md)'s "Design patterns" section. |

## Design Patterns: Use vs Misuse

- **Use patterns** when they solve a real design problem (e.g., variation in behavior, lifecycle, or cross-cutting concern), not to look "enterprise."
- **Avoid cargo cult**: Do not add Factory/Strategy/Repository just because the codebase "should" have them; add them when duplication or rigidity justifies the abstraction.
- **Signs of misuse**: Pattern name in every class name, layers that only delegate without logic, patterns that make simple code harder to follow.
- **Rule of thumb**: Introduce a pattern when you feel the third duplication or the second reason to change; name the pattern in code or docs so intent is clear.

## Smells and Heuristics (Summary)

| Smell / Heuristic | Meaning |
|-------------------|--------|
| **Rigidity** | Small change forces many edits. |
| **Fragility** | Changes break unrelated areas. |
| **Immobility** | Hard to reuse in another context. |
| **Viscosity** | Easy to hack, hard to do the right thing. |
| **Needless complexity** | Speculative or unused abstraction. |
| **Needless repetition** | DRY violated; same idea in multiple places. |
| **Opacity** | Code is hard to understand. |

Full lists (including heuristics C1–T9-style) are in [reference.md](./reference.md). Use these in review to name issues and suggest refactors (extract, move dependency, introduce boundary).

## Review vs Production

| Context | Apply |
|---------|--------|
| **Code review** | Dependency Rule and boundaries; SOLID in context; list smells; suggest one or two concrete refactors (e.g., extract function, invert dependency); check tests and professionalism (tests present, no obvious pressure hacks). |
| **Writing new code** | Prefer small functions and single responsibility; depend inward (Clean Architecture); write tests first when doing TDD; avoid patterns until duplication or variation justifies them. |
| **Refactoring** | Identify one smell at a time; refactor in small steps with tests green; improve names and structure before adding behavior. |

## How It Works

### When reviewing code

1. **Boundaries and Dependency Rule**: Check that dependencies point inward (e.g., use cases do not depend on UI or DB details). See [reference.md](./reference.md)'s "Clean Architecture" section.
2. **SOLID in context**: Check Single Responsibility, Open/Closed, Liskov, Interface Segregation, Dependency Inversion where they apply to the changed code.
3. **Smells**: Scan for rigidity, fragility, immobility, viscosity, needless complexity/repetition, opacity; list them with file/area.
4. **Concrete suggestions**: Propose one or two refactors (e.g., "Extract this into a function named X," "Introduce an interface so this layer does not depend on the concrete DB client").
5. **Tests and craft**: Note if tests exist and if the change respects sustainable pace (no obvious "we'll fix it later" comments that violate professionalism).

Suggested output shape for a review: one or two sentences on boundaries/dependency direction; any SOLID violations named with file/function and principle; smells found with location; one or two concrete refactors; a brief note on test coverage. Keep it tight — this isn't a separate report format, just how to organize the five points above when writing them up.

### When writing or refactoring code

1. Prefer **small, single-purpose** functions and classes.
2. Keep **dependencies pointing inward**; put business rules in the center, adapters at the edges.
3. Keep each function at a **single level of abstraction** (SLAP) — a function should call functions one level below it, not mix high-level orchestration with low-level detail in the same body. See Example 2 below.
4. Introduce **design patterns** only when duplication or variation justifies them.
5. Refactor in **small steps** with tests staying green.

## Examples

### Example 1: Code review prompt (copy-pasteable)

Use this to ask for an Uncle Bob–oriented review:

```markdown
Please review this change using Uncle Bob craft criteria (uncle-bob-craft):
1. Dependency Rule and boundaries — do dependencies point inward?
2. SOLID in context — any violations in the touched code?
3. Smells — list rigidity, fragility, immobility, viscosity, needless complexity/repetition, or opacity.
4. Suggest one or two concrete refactors (e.g., extract function, invert dependency).
Do not duplicate lint/format; focus on structure and design.
```

### Example 2: Before/after (extract and name)

**Before (opacity, does more than one thing):**

```python
def process(d):
    if d.get("t") == 1:
        d["x"] = d["a"] * 1.1
    elif d.get("t") == 2:
        d["x"] = d["a"] * 1.2
    return d
```

**After (clear intent, single level of abstraction):**

```python
def apply_discount(amount: float, discount_type: int) -> float:
    if discount_type == 1:
        return amount * 1.1
    if discount_type == 2:
        return amount * 1.2
    return amount

def process(order: dict) -> dict:
    order["x"] = apply_discount(order["a"], order.get("t", 0))
    return order
```

## Best Practices

- Use this skill for architecture, boundaries, SOLID, smells, and process; use `/code-review` for correctness/simplification/efficiency.
- In review, name the smell or principle (e.g., "Dependency Rule violation: use case imports from the web framework").
- Suggest at least one concrete refactor per review (extract, rename, invert dependency).
- Run the project's linter and formatter separately; this skill does not replace them.
- Do not use this skill to enforce syntax or style; that is the linter's job.
- Do not add design patterns without a clear duplication or variation reason.

## Common Pitfalls

- **Problem:** Treating every class as needing a Factory or Strategy.
  **Solution:** Introduce patterns only when you have a real design need (third duplication, second axis of change).

- **Problem:** Review only listing "violates SOLID" without saying where or how.
  **Solution:** Point to the file/function and which principle (e.g., "SRP: this function parses and persists; split into parse and persist").

- **Problem:** Skipping the project linter because "we applied Uncle Bob."
  **Solution:** This skill is about craft and design; always run the project's lint, format, and the mechanical constraints in `.claude/workflow.md`.

## Limitations

- **Does not replace the project's linter, formatter, or CI-enforced constraints** (max function length, cyclomatic complexity, parameter count, coverage — see `.claude/workflow.md`).
- **Does not replace automated tests.** It can remind you to write tests (Clean Coder, Clean Agile) but does not run or generate them.
- **Complementary to tooling.** Use it alongside existing CI, lint, and test suites, and alongside the built-in `/code-review` and `/simplify` skills.
- **No syntax or style enforcement.** It focuses on structure, dependencies, smells, and professional practice, not on brace style or line length.
- **Summaries, not the books.** Full Clean Code heuristics, component principles (REP/CCP/CRP, ADP/SDP/SAP), and detailed stories are in the books; we reference the most used parts. See [reference.md](./reference.md) "Scope and attribution."
