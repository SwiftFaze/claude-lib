#!/usr/bin/env bash
# Snapshot of a repo AS IT IS NOW, for a full scan (not "what changed since").
# Read-only: git reads and GitHub API reads only, never a write to the repo.
#
# Usage: inventory.sh <repo-path> <out-dir>
#
# Writes into <out-dir>:
#   meta.txt         repo, branch, HEAD, whether HEAD matches origin, dirty files
#   rules.txt        files that document how to work (AGENTS.md, CONTRIBUTING, ADRs…)
#   tree.txt         tracked files and lines per top-level dir and per extension
#   largest.txt      40 largest source files by line count
#   tests.txt        test files found, grouped by kind (unit / integration / e2e / other)
#   test-map.txt     every source file: SIB (sibling test) / IMP (imported by a test) / NONE, lines, path
#   test-map-summary.txt  the same, aggregated per directory
#   hotspots.txt     files changed most often in the last 90 days (churn), with test status
#   todos.txt        every TODO/FIXME/HACK/XXX in tracked files
#   suppressions.txt every lint/type/test suppression in tracked files
#   workflows.txt    CI workflows with their triggers; recent runs and failure rate per workflow
#   open-prs.txt, open-issues.txt   what is open on GitHub right now
#
# Needs: git; gh (authenticated) for the GitHub part (skipped with a warning otherwise).
set -uo pipefail
export MSYS_NO_PATHCONV=1

REPO_PATH="${1:?repo path}"; OUT="${2:?out dir}"
mkdir -p "$OUT"
cd "$REPO_PATH" || { echo "No such repo: $REPO_PATH" >&2; exit 1; }

git fetch -q --prune origin 2>/dev/null || echo "WARN: git fetch failed, using local refs" >&2
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
HEAD_SHA=$(git rev-parse HEAD)
UP=$(git rev-parse -q --verify "origin/$BRANCH" 2>/dev/null || echo none)
NWO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")

{
  echo "repo=${NWO:-unknown}"; echo "path=$REPO_PATH"; echo "collected_at=$NOW"
  echo "branch=$BRANCH"; echo "head=$HEAD_SHA"; echo "origin_head=$UP"
  [ "$UP" != "none" ] && echo "behind_origin=$(git rev-list --count HEAD..origin/$BRANCH) ahead_of_origin=$(git rev-list --count origin/$BRANCH..HEAD)"
  echo "dirty_files=$(git status --porcelain | wc -l)"
} > "$OUT/meta.txt"

# ---- Rules and standards the repo documents ----
git ls-files | grep -iE '(^|/)(AGENTS|CLAUDE|CONTRIBUTING|CODING_STANDARDS|GLOSSARY|ARCHITECTURE|SECURITY|TESTING)\.md$|(^|/)docs/(adr|decisions)/|(^|/)\.github/(PULL_REQUEST_TEMPLATE|CODEOWNERS)|(^|/)docs/[^/]*(test|method|ci|deploi|deploy|architecture)[^/]*\.md$' \
  | grep -v node_modules > "$OUT/rules.txt"

# ---- Source vs. test classification ----
TEST_RE='(\.(test|spec)\.[cm]?[jt]sx?$)|(_test\.(go|py)$)|(/test_[^/]*\.py$)|(Test[s]?\.(java|kt|cs)$)|(_spec\.rb$)|(\.test\.sh$)|(^|/)(e2e|tests?|__tests__|spec)/'
SRC_RE='\.([cm]?[jt]sx?|py|go|rb|java|kt|cs|rs|php|sh|mjs|cjs)$'
EXCL_RE='(^|/)(node_modules|dist|build|out|vendor|generated|\.next|coverage|__fixtures__|fixtures|migrations)/|\.d\.ts$|\.stories\.|\.config\.|^\.'

git ls-files | grep -E "$SRC_RE" | grep -vE "$EXCL_RE" > "$OUT/.files"
grep -E "$TEST_RE" "$OUT/.files" > "$OUT/.tests"
grep -vE "$TEST_RE" "$OUT/.files" > "$OUT/.src"

{
  echo "== integration"; grep -iE 'integration' "$OUT/.tests"
  echo "== e2e / browser"; grep -iE '(^|/)(e2e|playwright|cypress)/|\.e2e\.' "$OUT/.tests"
  echo "== shell / scripts"; grep -E '\.test\.sh$' "$OUT/.tests"
  echo "== unit (rest)"; grep -viE 'integration|(^|/)(e2e|playwright|cypress)/|\.e2e\.|\.test\.sh$' "$OUT/.tests"
} > "$OUT/tests.txt"

# Module paths that tests import (import/from/require/mock), reduced to their last one
# and last two segments without extension: "@/server/services/team" -> "team", "services/team".
while read -r f; do cat "$f" 2>/dev/null; done < "$OUT/.tests" \
  | grep -oE "(from|import|require|mock|doMock)[ (]*[\"'\`][^\"'\`]+[\"'\`]" \
  | sed -E "s/.*[\"'\`]([^\"'\`]+)[\"'\`]$/\1/; s/\.[cm]?[jt]sx?$//; s/\.py$//" \
  | awk -F/ '{ print $NF; if (NF>1) print $(NF-1)"/"$NF }' | sort -u > "$OUT/.imported"

# Line counts in one pass, then classify: SIB = a test file next to it with the same stem,
# IMP = some test imports it by name (generic names like route/index need the folder too),
# NONE = no test touches it as far as names can tell.
tr '\n' '\0' < "$OUT/.src" | xargs -0 wc -l 2>/dev/null | grep -v ' total$' | awk '{n=$1; sub(/^ *[0-9]+ /,""); print n" "$0}' > "$OUT/.lines"
awk -v tests="$OUT/.tests" -v imported="$OUT/.imported" '
  BEGIN {
    while ((getline t < tests) > 0) {
      n = split(t, p, "/"); b = p[n]; d = substr(t, 1, length(t) - length(b))
      s = b; sub(/\.(test|spec|e2e|integration)(\.[a-z]+)*$/, "", s); sub(/^test_/, "", s); sub(/_test\.[a-z]+$/, "", s); sub(/Tests?\.[a-z]+$/, "", s)
      sib[d s] = 1
      # Also "foo.integration.test.ts" -> stem "foo".
      s2 = s; sub(/\.[a-z-]+$/, "", s2); sib[d s2] = 1
    }
    while ((getline i < imported) > 0) imp[i] = 1
    generic["index"]; generic["route"]; generic["page"]; generic["layout"]; generic["main"]; generic["mod"]; generic["__init__"]; generic["handler"]
  }
  {
    lines = $1; f = substr($0, length($1) + 2)
    n = split(f, p, "/"); b = p[n]; d = substr(f, 1, length(f) - length(b))
    stem = b; sub(/\.[^.]+$/, "", stem); parent = (n > 1 ? p[n-1] : "")
    if ((d stem) in sib) st = "SIB"
    else if ((stem in generic) ? ((parent "/" stem) in imp) : (stem in imp)) st = "IMP"
    else st = "NONE"
    print st, lines, f
  }' "$OUT/.lines" > "$OUT/test-map.txt"

# Per directory (two levels deep): files and lines with no test at all.
awk '{ n=split($3,p,"/"); dir=(n>2? p[1]"/"p[2] : (n>1? p[1] : ".")); c[dir" "$1]++; l[dir" "$1]+=$2; dirs[dir]=1 }
     END { printf "%-40s %8s %8s %8s %12s\n", "dir", "SIB", "IMP", "NONE", "NONE_lines";
           for (d in dirs) printf "%-40s %8d %8d %8d %12d\n", d, c[d" SIB"], c[d" IMP"], c[d" NONE"], l[d" NONE"] }' \
  "$OUT/test-map.txt" | sort -k5 -nr > "$OUT/test-map-summary.txt"

# ---- Size ----
{
  echo "== tracked files per top-level dir"; git ls-files | awk -F/ '{print (NF>1?$1:".")}' | sort | uniq -c | sort -nr | head -30
  echo "== source files per extension";     sed 's/.*\.//' "$OUT/.files" | sort | uniq -c | sort -nr
  echo "== totals"; echo "source=$(wc -l < "$OUT/.src") tests=$(wc -l < "$OUT/.tests")"
} > "$OUT/tree.txt"
sort -k2 -nr "$OUT/test-map.txt" | head -40 > "$OUT/largest.txt"

# ---- Hot spots: churn over 90 days, joined with test status ----
git log --since=90.days --no-merges --name-only --format= 2>/dev/null | grep -E "$SRC_RE" | grep -vE "$EXCL_RE" \
  | sort | uniq -c | sort -nr | head -60 \
  | while read -r n f; do printf '%5d %s %s\n' "$n" "$(grep -m1 " $f\$" "$OUT/test-map.txt" | cut -d' ' -f1 || echo '?')" "$f"; done \
  > "$OUT/hotspots.txt"

# ---- Code signals across the whole tree ----
git grep -nIE '\b(TODO|FIXME|HACK|XXX)\b' -- ':!*.lock' ':!*lock.json' ':!**/generated/**' > "$OUT/todos.txt" 2>/dev/null
git grep -nIE 'eslint-disable|@ts-(ignore|expect-error|nocheck)|\.(skip|only)\(|\bxit\(|\bxdescribe\(|continue-on-error|--no-verify|\|\| *true\b|@Disabled|@Ignore|pytest\.mark\.skip|# *noqa|nolint|if: *false' \
  -- ':!*.lock' ':!*lock.json' ':!**/generated/**' ':!*.md' > "$OUT/suppressions.txt" 2>/dev/null

# ---- CI ----
{
  for w in $(git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml'); do
    echo "== $w"; awk '/^on:/{p=1;print;next} p&&/^[a-z]/{exit} p' "$w" | head -25
  done
  if [ -n "$NWO" ]; then
    echo; echo "== last 100 runs: conclusion per workflow"
    gh api "repos/$NWO/actions/runs?per_page=100" \
      --jq '.workflow_runs[] | "\(.name|gsub(" ";"_")) \(.conclusion // .status)"' 2>/dev/null | sort | uniq -c | sort -k2
  fi
} > "$OUT/workflows.txt"

# ---- What is open right now ----
if [ -n "$NWO" ]; then
  gh pr list -R "$NWO" --state open --limit 100 \
    --json number,title,author,headRefName,baseRefName,createdAt,isDraft,labels \
    --jq '.[] | "#\(.number) \(.headRefName)->\(.baseRefName) by \(.author.login) created=\(.createdAt[:10])\(if .isDraft then " draft" else "" end) labels=\([.labels[].name]|join(",")) | \(.title)"' \
    > "$OUT/open-prs.txt" 2>/dev/null
  gh issue list -R "$NWO" --state open --limit 300 \
    --json number,title,createdAt,labels,milestone \
    --jq '.[] | "#\(.number) created=\(.createdAt[:10]) milestone=\(.milestone.title // "-") labels=\([.labels[].name]|join(",")) | \(.title)"' \
    > "$OUT/open-issues.txt" 2>/dev/null
else
  echo "WARN: gh cannot see this repo; GitHub part skipped" >&2
fi

rm -f "$OUT/.files" "$OUT/.tests" "$OUT/.src" "$OUT/.imported" "$OUT/.lines"
echo "Inventory written to $OUT"
wc -l "$OUT"/*.txt | sed 's|'"$OUT"'/||'
awk '{c[$1]++} END{for(k in c) print k, c[k]}' "$OUT/test-map.txt"
