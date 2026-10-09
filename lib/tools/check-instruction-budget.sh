#!/usr/bin/env bash
#
# Enforces size budgets on agent-instruction files.
#
# The budgets are tiered by how often a file is loaded into an agent's context,
# because that is what the file actually costs:
#
#   every session      CLAUDE.md                     tightest budget
#   every pipeline step .claude/workflow.md
#   every agent run    .claude/agents/*.md
#   on skill use       .claude/skills/*/SKILL.md
#   on demand          docs/*.md                     loosest budget
#
# A file over budget is not a style nit: it is the mechanism by which these
# files decay. Reactive one-off fixes get appended, nothing is ever removed,
# and eventually the agent is carrying a page of stale advice into every task.
# The budget forces the trade — to add, consolidate or delete something else.
#
# Usage:  bash .claude/tools/check-instruction-budget.sh [--verbose]
# Exit:   0 all within budget, 1 something is over.

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

# path-glob:max_lines.
#
# These are BASELINES: set each one at the file's size when you adopt this
# check, not at a target reasoned up to from first principles. A gate that is
# red the day it lands teaches people to ignore it, so the job here is to stop
# growth first and ratchet down after - the same "measure a baseline, then
# hold it" reasoning as coverage floors.
#
# Ratchet: whenever a file is trimmed, lower its number here in the same commit.
# Never raise one without saying in the commit message why the file genuinely
# needs to be bigger.
BUDGETS=(
  "CLAUDE.md:100"
  # Glob, not the one path: a workflow variant is loaded the same way and decays
  # the same way, so a new one must not land unmeasured.
  ".claude/workflow*.md:145"
  ".claude/agents/*.md:60"
  ".claude/skills/*/SKILL.md:215"
  "docs/*.md:250"
)

status=0
over_budget=()

for entry in "${BUDGETS[@]}"; do
  pattern="${entry%:*}"
  max="${entry##*:}"

  for file in $pattern; do
    [ -f "$file" ] || continue
    lines=$(wc -l < "$file" | tr -d ' ')
    pct=$(( lines * 100 / max ))

    if [ "$lines" -gt "$max" ]; then
      over_budget+=("$file: $lines lines, budget $max (${pct}%)")
      status=1
    elif [ "$VERBOSE" -eq 1 ]; then
      printf '  ok    %-45s %4s / %-4s (%s%%)\n' "$file" "$lines" "$max" "$pct"
    elif [ "$pct" -ge 90 ]; then
      printf '  near  %-45s %4s / %-4s (%s%%) - consolidate before adding\n' \
        "$file" "$lines" "$max" "$pct"
    fi
  done
done

if [ "${#over_budget[@]}" -gt 0 ]; then
  echo
  echo "Instruction files over budget:"
  printf '  OVER  %s\n' "${over_budget[@]}"
  cat <<'EOF'

To fix, in preference order:
  1. Delete a rule that no longer applies (check git blame for when and why it
     was added - if the incident it patched is long gone, the rule can go too).
  2. Move a rule to the file it actually belongs to, leaving a link, not a copy.
     Each rule gets exactly one canonical home.
  3. Replace the rule with a mechanical check (a test, a CI job, a lint rule),
     then delete the prose. A rule a tool enforces does not need to be
     remembered.
  4. Only if none of the above apply, raise the budget here - and say in the
     commit message why the file genuinely needs to be bigger.
EOF
  exit 1
fi

echo "All instruction files within budget."
exit 0
