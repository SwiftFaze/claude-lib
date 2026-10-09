#!/usr/bin/env bash
#
# Blocks the implement-issue handoff when a changed .feature has neither a QA
# procedure (any specs/qa/<slug>.* file, run by the QA command in
# .claude/workflow.md) nor a `QA: none - <reason>` line in its Feature: block.
# Only useful in a project that configures a QA command.
#
#   bash .claude/tools/check-qa-coverage.sh [--base <ref>]
#
# Same base logic as check-clean.sh: merge-base with the base branch
# (CLEAN_BASE_REF, default develop), committed plus
# uncommitted plus untracked work.
# Exit: 0 all covered, 1 at least one offender, 2 could not run.

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

BASE_REF="${CLEAN_BASE_REF:-develop}"
while [ $# -gt 0 ]; do
  case "$1" in
    --base) shift; BASE_REF="${1:-}" ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if ! merge_base=$(git merge-base "$BASE_REF" HEAD 2>/dev/null); then
  echo "ERROR: cannot find a merge base with '$BASE_REF'. Pass --base <ref>." >&2
  exit 2
fi

changed=$( { git diff --name-only --diff-filter=d "$merge_base" -- 'specs/features/*.feature'
             git ls-files --others --exclude-standard -- 'specs/features/*.feature'; } \
           | tr '\\' '/' | sort -u)

offenders=0
for f in $changed; do
  [ -f "$f" ] || continue
  slug=$(basename "$f" .feature)
  # The Feature: block runs from the Feature: line to the first Scenario/Background/Rule.
  block=$(awk '/^[[:space:]]*(Scenario|Scenario Outline|Background|Rule)[: ]/{exit} {print}' "$f")
  procedure=$(ls "specs/qa/$slug".* 2>/dev/null | head -1)
  if [ -n "$procedure" ]; then
    echo "OK   $slug: procedure $procedure"
  elif reason=$(printf '%s\n' "$block" | sed -n 's/^[[:space:]]*QA: none - \(.*[^[:space:]]\).*$/\1/p' | head -1) && [ -n "$reason" ]; then
    echo "OK   $slug: QA: none - $reason"
  else
    echo "FAIL $slug: add a specs/qa/$slug.* procedure, or a 'QA: none - <reason>' line in its Feature: block" >&2
    offenders=$((offenders + 1))
  fi
done

[ -z "$changed" ] && echo "No changed .feature files vs $BASE_REF."
[ "$offenders" -eq 0 ] || exit 1
exit 0
