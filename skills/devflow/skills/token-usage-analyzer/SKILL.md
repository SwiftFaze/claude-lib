---
name: token-usage-analyzer
description: Analyzes Claude Code (or other Claude-based agent) session transcripts to produce a factual token-usage report — what consumed the most tokens, which models were used and whether that was appropriate, and whether the session involved forks/sidechains, subagent handoffs, context compaction, or /clear boundaries. Ends with concrete optimization proposals that preserve output quality. Use this whenever the user asks to analyze token usage, audit a session/transcript for cost or context-window efficiency, explain why a session got expensive or hit context limits, or wants recommendations to reduce tokens without changing behavior or results. Trigger on phrases like "why did this session use so many tokens", "audit my token usage", "where did all my context go", "did this fork/compact/clear", "optimize my Claude Code usage".
---

# Token Usage Analyzer

A skill for turning raw Claude Code / agent session transcripts into a factual, evidence-based token-usage audit, followed by optimization proposals that are guaranteed not to change the substance of the output.

This skill has two phases that must not be blended: **Phase 1 is pure measurement** (facts only, no recommendations, no judgment calls presented as fact). **Phase 2 is optimization** (recommendations only, each explicitly checked against a "does this change results?" test). Keep them in separate sections in the final report.

## When to use this

- The user hands you a transcript file/export/log and asks what happened to their tokens.
- The user says a session got expensive, slow, or hit a context-window/compaction limit and wants to know why.
- The user wants to know if their model choice, subagent usage, or context management was reasonable.
- The user wants a report they can act on to cut spend without degrading quality.

If no transcript file is available yet, ask the user where their session data lives before doing anything else — do not guess or fabricate numbers. Good places to check, in order:
1. A path or file they already gave you / uploaded (check `/mnt/user-data/uploads`).
2. `/mnt/transcripts` (may be pre-populated in this environment).
3. Their local Claude Code project transcripts, typically JSONL files under `~/.claude/projects/<project-hash>/`. If you're not running with filesystem access to their machine, ask them to export/copy the relevant `.jsonl` file(s) in.

## Step 0 — Inspect before assuming a schema

Transcript formats vary by Claude Code version and by whether the source is a JSONL session log, a support-export JSON, or something else entirely. **Never assume field names.** Before parsing:

1. `view` or `head` the first few lines / few KB of the file.
2. Identify, from what's actually there:
   - Where per-call token usage lives (commonly `message.usage` with `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, and a `model` field).
   - Where role/type lives (`type`: `user` / `assistant` / `system` / `summary`, or a `role` field).
   - Any field indicating a sidechain/fork (commonly `isSidechain`, or a `parentUuid` graph that branches).
   - Any field indicating a subagent/Task-tool invocation (a `tool_use` block with `name` like `Task`, or a nested transcript path).
   - Any marker for a compaction event (a `summary`-type entry, or content mentioning "compact"/"context summary").
   - Any marker for a `/clear` or new-session boundary (a new `sessionId`, or the transcript restarting with no prior `parentUuid`).
3. Only after confirming the real field names, write or adapt the parsing script.

`scripts/analyze_usage.py` implements this defensively: point it at a file and it will print what it detected before aggregating anything, so you can sanity-check the schema match instead of trusting it blindly. Run it, read its output, and use that as the factual backbone of Phase 1 — don't hand-total numbers yourself from spot-checking a few lines.

```bash
python3 scripts/analyze_usage.py /path/to/transcript.jsonl
```

Add `--json` for a machine-readable dump if you need to do further aggregation yourself (e.g. combining multiple files for a multi-session audit).

If the user has several transcript files (a whole project, or a session that spans multiple files due to `/clear`), run the script on each and aggregate — a `/clear` boundary is itself a fact worth reporting, not something to silently merge away.

## Step 1 — Compute the ground-truth numbers

At minimum, extract:
- **Total tokens** by category: input, output, cache creation, cache read (cache reads are cheap/fast but still count toward context — report them separately, don't fold them into "input" without a note).
- **Totals per model** used in the session (a session can span models, e.g. a fast/cheap model for a subagent and a larger one for the main thread).
- **Totals per turn / per tool call**, so you can rank "what used the most."
- **The single largest individual contributors**: the biggest tool_result blocks, the biggest pasted/user-supplied content, the biggest file reads, the largest search results.
- **Structural events**, each with a timestamp/position in the transcript:
  - Forks / sidechains (a branch off the main thread — usually a subagent's private context)
  - Subagent handoffs (main thread → Task tool → subagent → result returned to main thread)
  - Compactions (the conversation was summarized to reclaim context)
  - `/clear` or session-boundary resets

Don't estimate any of these — if the transcript doesn't let you determine one of them, say so explicitly in the report rather than inferring.

## Step 2 — Write the factual analysis (Phase 1 of the report)

Structure it like this. Keep it descriptive, not evaluative — no "should" or "could" language belongs here.

```
## Token Usage — Factual Summary

- Session span: <first ts> to <last ts>, N transcript file(s), M turns
- Total tokens: <input> in / <output> out / <cache creation> / <cache read>
- By model: <model A>: X tokens (Y%) — used for <what, if determinable>
            <model B>: X tokens (Y%) — used for <what, if determinable>

### What used the most
1. <biggest contributor> — <N tokens>, <where in the session, what it was>
2. <next> — ...
(top 5–10, ranked)

### Structural events
- Forks/sidechains: <count>, at <turns/positions>, spawned for <purpose if visible>
- Subagent handoffs: <count>, <which tools/tasks>
- Compactions: <count>, at <position>, <tokens before/after if visible>
- /clear or session resets: <count>, at <position>

### Is the usage reasonable? (assessment, clearly labeled as judgment)
Only after the facts above are laid out, give your read — flag things like: a large model used for trivial calls where a smaller one would do the same job, repeated full-file reads of the same file instead of a diff/grep, a single tool result that dominates the whole budget, redundant context reloaded after a compaction, or forks that duplicated rather than parallelized work. Cite the specific numbers/turns each judgment is based on. If usage looks proportionate to the task, say so plainly instead of manufacturing a concern.
```

## Step 3 — Optimization proposals (Phase 2, kept separate, non-degrading only)

For every proposal, apply this test explicitly before including it: **"Would a domain expert, blind to which run used this optimization, judge the two outputs as equivalent in correctness and completeness?"** If the answer is no, or you're not sure, don't include it as a plain recommendation — either drop it or clearly flag it as a trade-off the user must decide on themselves (never present a quality/token trade-off as a free win).

Common levers that are usually safe (include only the ones the facts actually support):
- **Targeted reads over full reads**: grep/search for the relevant section instead of reading whole files repeatedly, especially the same file across turns.
- **Right-sized model per subtask**: route small, mechanical, or high-volume calls (e.g. a subagent doing routine extraction) to a smaller/cheaper model, reserve the larger model for the steps that need its judgment.
- **Prompt caching**: structure repeated large context (system prompts, big reference docs) so it's cached rather than resent — same content, no cost in quality.
- **Deliberate compaction/`/clear` timing**: compact or clear at natural task boundaries rather than letting context grow unbounded through unrelated subtasks — this only helps if the cleared context genuinely isn't needed again.
- **Subagent isolation for large-context side-tasks**: push a large, self-contained lookup (log digging, large file analysis) into a subagent so only its summary re-enters the main thread, instead of pulling the raw material into the main context.
- **Trim tool-output verbosity where the extra content was never used**: e.g. a full directory listing when only one file mattered — only propose this where the transcript shows the extra content was in fact unused, not just "seems long."
- **De-duplicate repeated context**: the same large block (a spec, a schema, a file) pasted or re-fetched multiple times when it hadn't changed.

Format each proposal as:
```
### <short name>
- Evidence: <the specific numbers/turns from Phase 1 that motivate this>
- Change: <what to actually do>
- Why this doesn't degrade results: <one sentence — same info reaches the model, just via a cheaper path>
- Estimated impact: <rough token/% savings if computable from the data, otherwise "not quantifiable from this transcript">
```

If, after honest review, there's nothing worth changing, say that plainly — "usage was proportionate to the task; no changes recommended" is a valid and useful conclusion, not a failure to find something.

## Reference

See `scripts/analyze_usage.py` for the parsing/aggregation logic. Read it before running it if the transcript schema looks unusual — it's short and meant to be adapted, not treated as a black box.
