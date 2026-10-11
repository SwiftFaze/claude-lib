#!/usr/bin/env bash
#
# PreToolUse hook (plugin hooks/hooks.json, Bash|PowerShell): blocks a mutation
# run that doesn't go through a lock script, so the one-at-a-time rule of
# run-milestone holds even when an agent forgets it.
#
# Only active while the repo has more than one worktree: that is when parallel
# runs can collide. A single checkout runs mutation tools unguarded.
#
# Reads the hook's JSON payload on stdin and matches it raw (no jq needed).
# A command is a mutation run when it names a runner AND a mutation goal, so a
# plain search for the goal's name isn't blocked. Override either list per repo:
#   DEVFLOW_MUTATION_RUNNER_RE  default: mvn|mvnw|gradle|gradlew|npx|npm|pnpm|yarn|cargo|mutmut|dotnet
#   DEVFLOW_MUTATION_GOAL_RE    default: mutationCoverage|pitest|stryker|mutmut run|cargo[- ]mutants
# Any wrapper whose name ends in "lock.sh" counts as holding the lock, so a
# repo's own lock script still passes.
# Exit: 0 allow; 2 block (stderr is shown to the agent).

payload=$(cat)

runner_re="${DEVFLOW_MUTATION_RUNNER_RE:-mvn|mvnw|gradle|gradlew|npx|npm|pnpm|yarn|cargo|mutmut|dotnet}"
goal_re="${DEVFLOW_MUTATION_GOAL_RE:-mutationCoverage|pitest|stryker|mutmut run|cargo[- ]mutants}"

printf '%s' "$payload" | grep -Eq "(^|[^A-Za-z0-9_-])($runner_re)([^A-Za-z0-9_-]|$)" || exit 0
printf '%s' "$payload" | grep -Eq "$goal_re" || exit 0
printf '%s' "$payload" | grep -Eq 'lock\.sh' && exit 0

worktrees=$(git worktree list 2>/dev/null | wc -l)
[ "${worktrees:-0}" -gt 1 ] || exit 0

lock="$(cd "$(dirname "$0")" && pwd)/mutation-lock.sh"
cat >&2 <<EOF
Blocked: this repo has parallel worktrees, so mutation runs must hold the
shared lock (one at a time across all worktrees). Re-run the same command
prefixed with the lock script:
  bash "$lock" <your command>
If it exits 75, another run holds the lock: report that instead of retrying in
a loop, or set MUTATION_LOCK_WAIT=<seconds> to wait for it.
EOF
exit 2
