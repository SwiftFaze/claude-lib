#!/usr/bin/env bash
# Collects everything that happened in a GitHub repo since a given date, into a
# folder of small text/JSON files the reviewer reads. Read-only: only `git fetch`
# and GitHub API reads, never a write.
#
# Usage: collect.sh <repo-path> <since-ISO-8601-UTC> <out-dir>
#   e.g. collect.sh ~/code/my-app 2026-10-08T00:00:00Z /tmp/review
#
# Needs: git, gh (authenticated). Uses gh's built-in --jq (no standalone jq).
set -uo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: don't rewrite "origin/x:path"

REPO_PATH="${1:?repo path}"; SINCE="${2:?since (ISO UTC)}"; OUT="${3:?out dir}"
mkdir -p "$OUT/prs" "$OUT/issues"
cd "$REPO_PATH" || { echo "No such repo: $REPO_PATH" >&2; exit 1; }

git fetch -q --prune --tags origin || echo "WARN: git fetch failed, using local refs" >&2
NWO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || { echo "gh cannot see this repo" >&2; exit 1; }
DEFAULT=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Long-lived branches worth reviewing: the default one plus the usual suspects.
BRANCHES=$(for b in "$DEFAULT" main master develop staging; do
  git rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null && echo "$b"; done | sort -u)

{
  echo "repo=$NWO"; echo "path=$REPO_PATH"; echo "default_branch=$DEFAULT"
  echo "since=$SINCE"; echo "collected_at=$NOW"
  for b in $BRANCHES; do
    base=$(git rev-list -1 --first-parent --before="$SINCE" "origin/$b" 2>/dev/null)
    echo "branch.$b.head=$(git rev-parse "origin/$b")"
    echo "branch.$b.base=${base:-none}"   # last commit before SINCE (diff base)
  done
} > "$OUT/meta.txt"

# ---- Commits and code-level signals, per long-lived branch ----
: > "$OUT/commits.txt"; : > "$OUT/todos.txt"; : > "$OUT/suppressions.txt"; : > "$OUT/diffstat.txt"
for b in $BRANCHES; do
  # --first-parent: the branch's own tip at SINCE, not a merged-in commit with an older date.
  base=$(git rev-list -1 --first-parent --before="$SINCE" "origin/$b" 2>/dev/null)
  range="${base:+$base..}origin/$b"
  echo "=== $b ($range)" >> "$OUT/commits.txt"
  git log --no-merges --since="$SINCE" --format='%h %cI %an | %s' "origin/$b" >> "$OUT/commits.txt"
  [ -n "$base" ] || continue
  echo "=== $b" >> "$OUT/diffstat.txt"
  git diff --stat=200 "$base" "origin/$b" | tail -60 >> "$OUT/diffstat.txt"
  # Added lines only, with file and line number, from the unified diff.
  git diff -U0 "$base" "origin/$b" | awk -v br="$b" '
    /^\+\+\+ b\// { file=substr($0,7); next }
    /^@@/ { split($3,a,","); line=substr(a[1],2)+0; next }
    /^\+/ && !/^\+\+\+/ { print br " " file ":" line ": " substr($0,2); line++ }
  ' > "$OUT/.added.txt"
  grep -E '\b(TODO|FIXME|HACK|XXX)\b' "$OUT/.added.txt" >> "$OUT/todos.txt"
  grep -E 'eslint-disable|@ts-(ignore|expect-error|nocheck)|\.(skip|only)\(|\bxit\(|\bxdescribe\(|continue-on-error|--no-verify|\|\| *true\b|@Disabled|@Ignore|pytest\.mark\.skip|# *noqa|nolint|if: *false' "$OUT/.added.txt" >> "$OUT/suppressions.txt"
  rm -f "$OUT/.added.txt"
done

# ---- Pull requests touched since SINCE ----
gh pr list -R "$NWO" --state all --limit 200 --search "updated:>=$SINCE" \
  --json number,title,state,author,baseRefName,headRefName,createdAt,mergedAt,closedAt,additions,deletions,changedFiles,labels,isDraft \
  --jq '.[] | "#\(.number) [\(.state)\(if .isDraft then ",draft" else "" end)] \(.headRefName)->\(.baseRefName) by \(.author.login) created=\(.createdAt[:16]) merged=\((.mergedAt // "-")[:16]) +\(.additions)/-\(.deletions) files=\(.changedFiles) labels=\([.labels[].name]|join(",")) | \(.title)"' \
  > "$OUT/prs.txt"
for n in $(grep -oE '^#[0-9]+' "$OUT/prs.txt" | tr -d '#'); do
  gh pr view "$n" -R "$NWO" \
    --json number,title,state,body,comments,reviews,files,statusCheckRollup,closingIssuesReferences,mergeCommit \
    --jq '"# PR #\(.number) [\(.state)] \(.title)\nmerge_commit=\(.mergeCommit.oid // "-")\ncloses=\([.closingIssuesReferences[]?.number]|join(","))\nchecks=\([.statusCheckRollup[]? | "\(.name // .context)=\(.conclusion // .state)"]|join(" "))\nfiles=\([.files[].path]|join(", "))\n\n## Body\n\(.body)\n\n## Comments\n\([.comments[] | "@\(.author.login) \(.createdAt[:16]):\n\(.body)"]|join("\n\n"))\n\n## Reviews\n\([.reviews[] | "@\(.author.login) \(.state): \(.body)"]|join("\n"))"' \
    > "$OUT/prs/$n.md" 2>/dev/null
done

# ---- Issues touched since SINCE (excluding PRs) ----
gh issue list -R "$NWO" --state all --limit 200 --search "updated:>=$SINCE" \
  --json number,title,state,author,createdAt,closedAt,labels,milestone \
  --jq '.[] | "#\(.number) [\(.state)] by \(.author.login) created=\(.createdAt[:16]) closed=\((.closedAt // "-")[:16]) milestone=\(.milestone.title // "-") labels=\([.labels[].name]|join(",")) | \(.title)"' \
  > "$OUT/issues.txt"
for n in $(grep -oE '^#[0-9]+' "$OUT/issues.txt" | tr -d '#'); do
  gh issue view "$n" -R "$NWO" --json number,title,state,body,comments,closedByPullRequestsReferences \
    --jq '"# Issue #\(.number) [\(.state)] \(.title)\nclosed_by_prs=\([.closedByPullRequestsReferences[]?.number]|join(","))\n\n## Body\n\(.body)\n\n## Comments\n\([.comments[] | "@\(.author.login) \(.createdAt[:16]):\n\(.body)"]|join("\n\n"))"' \
    > "$OUT/issues/$n.md" 2>/dev/null
done

# ---- CI: runs since SINCE, with job durations (billing rounds each job up to a minute) ----
gh api --paginate "repos/$NWO/actions/runs?created=>=$SINCE&per_page=100" \
  --jq '.workflow_runs[] | "\(.id) \(.name|gsub(" ";"_")) \(.event) \(.head_branch // "-") \(.conclusion // .status) \(.created_at[:16])"' \
  > "$OUT/ci-runs.txt" 2>/dev/null
RUNS=$(wc -l < "$OUT/ci-runs.txt")
if [ "$RUNS" -le 300 ]; then
  : > "$OUT/ci-jobs.txt"
  while read -r id name ev br concl t; do
    gh api "repos/$NWO/actions/runs/$id/jobs?per_page=100" \
      --jq '.jobs[] | select(.started_at and .completed_at) | "\(.name|gsub(" ";"_")) \(.conclusion) \(((.completed_at|fromdate)-(.started_at|fromdate)))"' 2>/dev/null \
      | sed "s|^|$t $name $ev $br |" >> "$OUT/ci-jobs.txt"
  done < "$OUT/ci-runs.txt"
  # Columns: date workflow event branch job conclusion seconds -> billed minutes (0 s jobs are free)
  awk '$7>0 { m=int(($7+59)/60); k=$2" "$3" "$5; c[k]++; s[k]+=m; d[substr($1,1,10)]+=m; tot+=m }
       END { for (k in c) printf "%-60s runs=%4d billed_min=%5d\n", k, c[k], s[k];
             for (x in d) printf "DAY %s billed_min=%d\n", x, d[x];
             print "TOTAL billed_min=" tot }' "$OUT/ci-jobs.txt" | sort > "$OUT/ci-minutes.txt"
else
  echo "Too many runs ($RUNS) to fetch jobs; minutes not computed." > "$OUT/ci-minutes.txt"
fi
grep -E ' (failure|cancelled|action_required|timed_out|startup_failure) ' "$OUT/ci-runs.txt" > "$OUT/ci-failures.txt"

# ---- Releases / tags since SINCE ----
git for-each-ref --sort=-creatordate --format='%(creatordate:iso-strict) %(refname:short)' refs/tags \
  | awk -v s="$SINCE" '$1 >= s' > "$OUT/tags.txt"

echo "Collected into $OUT"
wc -l "$OUT"/*.txt | sed 's|'"$OUT"'/||'
echo "prs: $(ls "$OUT/prs" | wc -l) files, issues: $(ls "$OUT/issues" | wc -l) files"
