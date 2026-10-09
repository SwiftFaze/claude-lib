#!/usr/bin/env bash
#
# The Clean Code gate. ONE command, run identically by the subagent before it
# reports a task finished and by the orchestrator to verify that report.
#
#   bash .claude/tools/check-clean.sh
#
# Why one command for both sides: the recurring failure this exists to stop is
# a subagent reporting "done" and the orchestrator bouncing it for failing
# tests, smells, or Clean Code violations. That loop is expensive because the
# two sides were checking different things - the subagent checked whatever it
# remembered from its handoff prompt, the orchestrator checked whatever it
# thought to look for. Same script, same rules, same output closes the gap by
# construction: there is nothing the orchestrator can reject the work for that
# the subagent could not have seen first.
#
# SCOPE: by default this judges only the lines your change ADDED, measured
# against the merge-base with the base branch (default develop, override with
# CLEAN_BASE_REF or --base), including uncommitted AND untracked
# work - a brand-new class is untracked until `git add`, and missing it would
# be the exact silent pass this tool exists to prevent. That is
# deliberate and it is what makes the gate landable. Strict rules in
# .pmd-clean-code.xml typically find hundreds of violations across an existing
# codebase; a gate that is red the day it arrives teaches everyone to ignore it
# (the same reasoning as check-instruction-budget.sh's baselines).
# You are accountable for the lines you wrote, not the file you happened to
# open.
#
# Usage:
#   check-clean.sh                 the gate - added lines only
#   check-clean.sh --fast          skip `mvn verify` (inner loop only, NOT the gate)
#   check-clean.sh --all           whole repo, ignore the diff (baselining)
#   check-clean.sh --base <ref>    compare against <ref> instead of the base branch
#   check-clean.sh --files         whole changed FILES, not just added lines
#
# Exit: 0 = mechanical checks pass (judgment checklist still owed)
#       1 = blocking violations, or a build/test failure
#       2 = the script could not run the checks (bad ref, maven missing)
#
# Assumes a Maven build with a `clean-code` profile running PMD (rules in
# .pmd-clean-code.xml, reports in target/clean-code/), CPD and SpotBugs.
# Thresholds: .claude/workflow.md "Constraints". Optional settings (env):
#   CLEAN_BASE_REF        base branch to diff against (default develop)
#   CLEAN_HOT_PATH_PATTERN  regex of files on a hot path (e.g. a render loop);
#                         HOT_PATH_RULES only apply there. Empty = nowhere.
#   CLEAN_UI_PACKAGE / CLEAN_DOMAIN_PACKAGE  names used in the checklist

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

BASE_REF="${CLEAN_BASE_REF:-develop}"
RUN_MVN=1
SCOPE="lines"

while [ $# -gt 0 ]; do
  case "$1" in
    --fast)  RUN_MVN=0 ;;
    --all)   SCOPE="all" ;;
    --files) SCOPE="files" ;;
    --base)  shift; BASE_REF="${1:-}" ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

blocking=0
advisory=0
sections_failed=""

hr() { printf '%s\n' "------------------------------------------------------------"; }

# ---------------------------------------------------------------------------
# Scope: which files, and which lines within them, this run is accountable for
# ---------------------------------------------------------------------------

: > "$WORK/addedlines"
: > "$WORK/diff"

if [ "$SCOPE" = "all" ]; then
  echo "Scope: ENTIRE REPOSITORY (baselining mode - not the gate)"
  find src -name '*.java' 2>/dev/null | sed 's|\\|/|g' | sort > "$WORK/files"
else
  if ! merge_base=$(git merge-base "$BASE_REF" HEAD 2>/dev/null); then
    echo "ERROR: cannot find a merge base with '$BASE_REF'." >&2
    echo "       Fetch it first, or pass --base <ref>." >&2
    exit 2
  fi

  # One diff covers both committed-on-branch and uncommitted work, which is
  # what an agent mid-task actually has.
  git diff -U0 "$merge_base" -- '*.java' > "$WORK/diff" 2>/dev/null

  # Hunk headers give the added-line ranges: @@ -old,n +new,m @@
  awk '
    /^\+\+\+ b\// { file = substr($0, 7); next }
    /^@@ / {
      if (file == "") next
      split($3, a, ",")
      start = a[1]; sub(/^\+/, "", start)
      count = (length(a) > 1 ? a[2] : 1)
      for (i = 0; i < count; i++) print file ":" (start + i)
    }
  ' "$WORK/diff" > "$WORK/addedlines.tmp"

  # A brand-new class is UNTRACKED until someone runs `git add`, and `git diff`
  # does not see untracked files at all. Without this an agent could write an
  # entire new class and the gate would report "no Java changes to check" -
  # the exact silent pass this tool exists to prevent. Every line of a new
  # file is an added line.
  git ls-files --others --exclude-standard -- '*.java' 2>/dev/null \
    | sed 's|\\|/|g' > "$WORK/untracked"
  while IFS= read -r uf; do
    [ -n "$uf" ] && [ -f "$uf" ] || continue
    awk -v F="$uf" '{ print F ":" FNR }' "$uf" >> "$WORK/addedlines.tmp"
  done < "$WORK/untracked"

  sort -u "$WORK/addedlines.tmp" > "$WORK/addedlines"
  cut -d: -f1 "$WORK/addedlines" | sort -u > "$WORK/files"

  if [ "$SCOPE" = "files" ]; then
    echo "Scope: changed FILES vs $BASE_REF ($(wc -l < "$WORK/files" | tr -d ' ') file(s))"
  else
    echo "Scope: lines ADDED vs $BASE_REF ($(wc -l < "$WORK/files" | tr -d ' ') file(s), $(wc -l < "$WORK/addedlines" | tr -d ' ') line(s))"
  fi
fi

if [ ! -s "$WORK/files" ]; then
  echo
  echo "No Java changes to check."
  echo "PASS - but note the gate checked nothing. If you changed Java, your"
  echo "branch may not be based on $BASE_REF."
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. Build, tests, and the repo-wide gates that already existed
#    (unit + Cucumber + IT, JaCoCo 85%, ArchUnit module direction,
#     .pmd-minimal.xml complexity/length/params, CPD at 100 tokens)
# ---------------------------------------------------------------------------

hr
echo "1. Build, tests, coverage, module direction (mvn verify)"
hr

# Persisted, not in the temp dir: when this fails, the log is the thing you
# need to read, and it must outlive the script.
mkdir -p target/clean-code
MVN_LOG="target/clean-code/mvn-verify.log"

if [ "$RUN_MVN" -eq 0 ]; then
  echo "  SKIPPED (--fast). This is an inner-loop shortcut, not the gate."
  echo "  You may not report a task finished on a --fast run."
else
  # -Dpmd.failOnViolation=false is NOT a weakening of the gate. A repo-wide
  # PMD ruleset with pre-existing violations makes `mvn verify` fail on a
  # clean checkout. Left alone that would make section 1 permanently red and this
  # whole tool useless. Instead the build is allowed to run to completion -
  # tests, JaCoCo and ArchUnit still fail it for real - and the PMD report it
  # writes is diff-scoped in section 2, so you are told about violations YOUR
  # change added, with file:line, rather than inheriting someone else's.
  # One property covers PMD and CPD - both executions share the plugin's
  # <configuration>. It is wired through pom.xml's <properties>, because a -D
  # is ignored when the value is set literally in the plugin configuration.
  if mvn -B verify -Dpmd.failOnViolation=false -Dcrap.mode=--report-only > "$MVN_LOG" 2>&1; then
    echo "  PASS  compile, unit + acceptance + integration tests, 85% line"
    echo "        coverage, ArchUnit module dependency direction + structure"
  else
    echo "  FAIL  mvn verify failed:"
    echo
    # Only real failures: PMD/CPD counts are handled in section 2, and the
    # unfiltered log is thousands of passing [INFO] lines.
    grep -E "Failed to execute goal|Failures: [1-9]|Errors: [1-9]|Rule violated|^\[ERROR\].*Test|COVERAGE" "$MVN_LOG" \
      | head -30 | sed 's/^/    /'
    echo
    echo "    Full log: $MVN_LOG"
    blocking=$((blocking + 1))
    sections_failed="$sections_failed build/tests"
  fi
fi

# ---------------------------------------------------------------------------
# 2. Clean Code rules (.pmd-clean-code.xml), scoped to the diff
# ---------------------------------------------------------------------------

hr
echo "2. Clean Code rules + repo-wide complexity gates (diff-scoped)"
hr

# Rules that only make sense against test sources, and rules that only make
# sense against main sources. Anything unlisted applies to both.
TEST_ONLY="UnitTestShouldIncludeAssert UnitTestShouldUseTestAnnotation \
SimplifiableTestAssertion DetachedTestCase UnnecessaryBooleanAssertion \
UnitTestContainsTooManyAsserts NoLogicInTests"

MAIN_ONLY="GodClass TooManyMethods TooManyFields ExcessivePublicCount \
CouplingBetweenObjects"

# AvoidInstantiatingObjectsInLoops: allocation inside a loop is a defect on a
# hot path (a per-frame render loop, a tight request handler), not repo-wide -
# a JSON-building loop at startup or in a test step definition is cold code
# where the same allocation is harmless. So these rules only apply to files
# matching CLEAN_HOT_PATH_PATTERN; leave it empty to switch them off.
RENDER_SCOPED_RULES="AvoidInstantiatingObjectsInLoops"
RENDER_PATH_PATTERN="${CLEAN_HOT_PATH_PATTERN:-}"

# ADVISORY rules are heuristic proxies, not proofs. They are reported with
# file:line and must be dispositioned in the completion report, but they do
# not fail the gate on their own - geometry code legitimately contains
# numbers, and a coordinate is legitimately called `x`. Everything else is
# high-precision and blocks. Rules without a standard PMD name (NoLogicInTests,
# MagicNumber, AbbreviatedName, ShortVariableName) are custom XPath rules
# expected in .pmd-clean-code.xml; rename here to match yours.
#
# NoLogicInTests is advisory rather than blocking for one reason: it fires
# on structural tests (e.g. one that scans every step definition for
# duplicates), which loop on purpose. Structural tests that scan the codebase legitimately
# contain a loop, and a blocking rule with a known-legitimate exception and no
# suppression route would push agents onto the "stop and report" path as
# routine. The judgment checklist ("each test fails for exactly ONE reason")
# is what actually carries this rule.
ADVISORY_RULES="GodClass TooManyMethods TooManyFields ExcessivePublicCount \
CouplingBetweenObjects MagicNumber AbbreviatedName ShortVariableName \
LongVariable AvoidDuplicateLiterals CommentSize SingularField \
NoLogicInTests"

if ! command -v mvn >/dev/null 2>&1; then
  echo "  ERROR: maven not on PATH" >&2
  exit 2
fi

if ! mvn -B -q -o -P clean-code pmd:pmd pmd:cpd > "$WORK/pmd.log" 2>&1; then
  # Retry online once: -o fails on a cold cache, which is not the user's fault.
  if ! mvn -B -q -P clean-code pmd:pmd pmd:cpd > "$WORK/pmd.log" 2>&1; then
    echo "  ERROR: PMD run failed:" >&2
    tail -25 "$WORK/pmd.log" | sed 's/^/    /' >&2
    exit 2
  fi
fi

REPORT="target/clean-code/pmd.xml"
[ -f "$REPORT" ] || { echo "  ERROR: no PMD report at $REPORT" >&2; exit 2; }

# Both reports feed one pipeline:
#   target/clean-code/pmd.xml  the Clean Code rules (this profile)
#   target/pmd.xml             .pmd-minimal.xml, written by `mvn verify` above
#                              - method length, cyclomatic complexity, params
# The rule sets do not overlap, so nothing is double-reported. Including the
# second one is what turns "the build is red somewhere" into "line 42 of your
# file has 6 parameters".
REPORTS="$REPORT"
if [ "$RUN_MVN" -eq 1 ] && [ -f "target/pmd.xml" ]; then
  REPORTS="$REPORTS target/pmd.xml"
fi

# Parse PMD XML into: relpath|line|rule|message
# PMD emits one <violation ...> open tag per finding with the message as its
# text content, so a small state machine is enough and keeps this dependency
# -free (bash + awk are all CI has to have).
# shellcheck disable=SC2086
awk '
  /<file name=/ {
    f = $0
    sub(/.*name="/, "", f); sub(/".*/, "", f)
    gsub(/\\/, "/", f)
    sub(/^.*\/src\//, "src/", f)
    next
  }
  /<violation / {
    line = $0; sub(/.*beginline="/, "", line); sub(/".*/, "", line)
    rule = $0; sub(/.*rule="/, "", rule);      sub(/".*/, "", rule)
    inviol = 1; msg = ""
    next
  }
  inviol && /<\/violation>/ {
    gsub(/^[ \t]+|[ \t]+$/, "", msg)
    gsub(/\|/, "/", msg)
    print f "|" line "|" rule "|" msg
    inviol = 0; next
  }
  inviol {
    t = $0; gsub(/^[ \t]+|[ \t]+$/, "", t)
    msg = (msg == "" ? t : msg " " t)
  }
' $REPORTS > "$WORK/violations.raw"

# Apply scope + main/test routing + advisory classification.
awk -v scope="$SCOPE" -v addedfile="$WORK/addedlines" \
    -v test_only="$TEST_ONLY" -v main_only="$MAIN_ONLY" -v advisory="$ADVISORY_RULES" \
    -v render_only="$RENDER_SCOPED_RULES" -v render_pattern="$RENDER_PATH_PATTERN" '
  BEGIN {
    n = split(test_only, a, /[ \t\n]+/); for (i=1;i<=n;i++) if(a[i]!="") TESTONLY[a[i]]=1
    n = split(main_only, b, /[ \t\n]+/); for (i=1;i<=n;i++) if(b[i]!="") MAINONLY[b[i]]=1
    n = split(advisory,  c, /[ \t\n]+/); for (i=1;i<=n;i++) if(c[i]!="") ADV[c[i]]=1
    n = split(render_only, d, /[ \t\n]+/); for (i=1;i<=n;i++) if(d[i]!="") RENDERONLY[d[i]]=1
  }
  # Explicit filename test, not NR==FNR: the added-lines file is empty in
  # --all mode, and NR==FNR is true for the FIRST record of the second file
  # when the first one is empty, which would silently eat a violation.
  FILENAME == addedfile { KEEPLINE[$0]=1; split($0,p,":"); KEEPFILE[p[1]]=1; next }
  {
    split($0, v, "|"); file=v[1]; line=v[2]; rule=v[3]
    if (scope != "all" && !(file in KEEPFILE)) next
    if (scope == "lines" && !((file ":" line) in KEEPLINE)) next
    isTest = (file ~ /^src\/test\//)
    if ((rule in TESTONLY) && !isTest) next
    if ((rule in MAINONLY) &&  isTest) next
    if ((rule in RENDERONLY) && (render_pattern == "" || file !~ render_pattern)) next
    print ((rule in ADV) ? "ADVISORY|" : "BLOCKING|") $0
  }
' "$WORK/addedlines" "$WORK/violations.raw" > "$WORK/violations"

pmd_block=$(grep -c '^BLOCKING|' "$WORK/violations" || true)
pmd_advise=$(grep -c '^ADVISORY|' "$WORK/violations" || true)

if [ "$pmd_block" -gt 0 ]; then
  echo "  FAIL  $pmd_block blocking violation(s):"
  echo
  grep '^BLOCKING|' "$WORK/violations" | sort -t'|' -k2,2 -k3,3n \
    | awk -F'|' '{ printf "    %s:%s\n      [%s] %s\n", $2, $3, $4, $5 }'
  blocking=$((blocking + pmd_block))
  sections_failed="$sections_failed clean-code"
else
  echo "  PASS  no blocking Clean Code violations in changed lines"
fi

if [ "$pmd_advise" -gt 0 ]; then
  echo
  echo "  ADVISORY  $pmd_advise heuristic finding(s) - do not block, but each"
  echo "            must be dispositioned in your completion report (fix, or"
  echo "            one line saying why it is correct as written):"
  echo
  grep '^ADVISORY|' "$WORK/violations" | sort -t'|' -k2,2 -k3,3n \
    | awk -F'|' '{ printf "    %s:%s\n      [%s] %s\n", $2, $3, $4, $5 }'
  advisory=$((advisory + pmd_advise))
fi

# ---------------------------------------------------------------------------
# 3. SpotBugs + fb-contrib bytecode-dataflow analysis
# ---------------------------------------------------------------------------

hr
echo "3. SpotBugs + fb-contrib bytecode dataflow (diff-scoped)"
hr

# Rules that are high-precision (blocking) and low-precision heuristics (advisory).
# Blocking: core defects that require dataflow analysis - exposed mutable references,
# equals/hashCode contract violations, null-deref paths, non-transient Serializable
# fields, ignored return values, self-assignment, unrelated-type comparisons.
# Advisory: fb-contrib heuristics that are lower-precision and must be dispositioned.
SPOTBUGS_BLOCKING="EI_EXPOSE_REP EI_EXPOSE_REP2 HE_EQUALS_USE_HASHCODE \
NP_DEREF_OF_READLINE_VALUE NP_GUARANTEED_DEREF NP_METHOD_PARAMETER_TAINT_PROPAGATION \
NP_NONNULL_PARAM_VIOLATION NP_NULL_ON_SOME_PATH NP_NULL_ON_SOME_PATH_EXCEPTION \
NP_NULL_PARAM_DEREF NP_POTENTIAL_NULL_POINTER_DEREFERENCE \
SE_BAD_FIELD RV_RETURN_VALUE_IGNORED RV_RETURN_VALUE_IGNORED_INFERRED SA_SELF_ASSIGNMENT \
EC_UNRELATED_TYPES"

# Everything not in SPOTBUGS_BLOCKING is advisory by default (below), not an
# explicit allowlist - fb-contrib alone has several hundred detector codes,
# so enumerating them is impractical and would just drift out of sync.

if ! command -v mvn >/dev/null 2>&1; then
  echo "  ERROR: maven not on PATH" >&2
  exit 2
fi

if ! mvn -B -q -o -P clean-code spotbugs:spotbugs > "$WORK/spotbugs.log" 2>&1; then
  # Retry online once: -o fails on a cold cache, which is not the user's fault.
  if ! mvn -B -q -P clean-code spotbugs:spotbugs > "$WORK/spotbugs.log" 2>&1; then
    echo "  ERROR: SpotBugs run failed:" >&2
    tail -25 "$WORK/spotbugs.log" | sed 's/^/    /' >&2
    exit 2
  fi
fi

SPOTBUGS_REPORT="target/clean-code/spotbugs.xml"
[ -f "$SPOTBUGS_REPORT" ] || { echo "  ERROR: no SpotBugs report at $SPOTBUGS_REPORT" >&2; exit 2; }

# SpotBugs' own XML report packs many tags onto very few physical lines (unlike
# PMD's one-tag-per-line output), which breaks a line-oriented awk state
# machine outright - and it uses single-quoted attributes, not PMD's double
# quotes. Force one tag per line first so the parser below can work the same
# way the PMD one does.
sed "s/</\\n</g" "$SPOTBUGS_REPORT" > "$WORK/spotbugs_lines.xml"

# Parse into: relpath|line|rule|message
#
# A <BugInstance> carries the bug's `type` as an attribute on its own opening
# tag, then nests a <SourceLine> inside each of <Class>/<Method>/<Field> (the
# bug's cross-referenced declaration sites - NOT where to report it), and
# finally, as a DIRECT child of <BugInstance> itself, one or more <SourceLine>
# elements marked `primary='true'` - that is the actual bug location. Nested
# Class/Method/Field SourceLines never carry `primary='true'` in SpotBugs'
# own output, so filtering on that attribute (plus requiring a `start=`,
# since the Field one omits it) reliably skips the decoys without needing to
# track XML nesting depth by hand.
# shellcheck disable=SC2086
cat > "$WORK/spotbugs_parse.awk" <<'AWKEOF'
/<BugInstance / && /type='/ {
  type = $0; sub(/.*type='/, "", type); sub(/'.*/, "", type)
  file = ""; line = ""; msg = ""
  inbug = 1
  next
}
inbug && /<\/BugInstance>/ {
  if (file != "" && line != "") {
    gsub(/\|/, "/", msg)
    print file "|" line "|" type "|" msg
  }
  inbug = 0; next
}
inbug && /<ShortMessage>/ {
  msg = $0; sub(/.*<ShortMessage>/, "", msg); sub(/<\/ShortMessage>.*/, "", msg)
  gsub(/^[ \t]+|[ \t]+$/, "", msg)
  next
}
inbug && /<SourceLine / && /primary='true'/ && /start='/ {
  # sourcepath is package-relative (e.g. com/example/app/Foo.java), not
  # repo-relative - unlike PMD's <file name=...> this never includes a "src/"
  # segment to key off of. The spotbugs goal analyzes only
  # ${project.build.outputDirectory} (src/main/java) unless includeTests is
  # set, which a default plugin config does not do, so the prefix is safe to
  # hardcode rather than inferred per-finding. Change it if you set
  # includeTests or use a non-standard source layout.
  sourcepath = $0; sub(/.*sourcepath='/, "", sourcepath); sub(/'.*/, "", sourcepath)
  gsub(/\\/, "/", sourcepath)
  file = "src/main/java/" sourcepath
  line = $0; sub(/.*start='/, "", line); sub(/'.*/, "", line)
  next
}
AWKEOF
awk -f "$WORK/spotbugs_parse.awk" "$WORK/spotbugs_lines.xml" > "$WORK/spotbugs.raw"

# Apply scope + blocking/advisory classification.
awk -v scope="$SCOPE" -v addedfile="$WORK/addedlines" \
    -v blocking="$SPOTBUGS_BLOCKING" '
  BEGIN {
    n = split(blocking, b, /[ \t\n]+/); for (i=1;i<=n;i++) if(b[i]!="") BLOCKING[b[i]]=1
  }
  FILENAME == addedfile { KEEPLINE[$0]=1; split($0,p,":"); KEEPFILE[p[1]]=1; next }
  {
    split($0, v, "|"); file=v[1]; line=v[2]; rule=v[3]
    if (scope != "all" && !(file in KEEPFILE)) next
    if (scope == "lines" && !((file ":" line) in KEEPLINE)) next
    print ((rule in BLOCKING) ? "BLOCKING|" : "ADVISORY|") $0
  }
' "$WORK/addedlines" "$WORK/spotbugs.raw" > "$WORK/spotbugs"

sb_block=$(grep -c '^BLOCKING|' "$WORK/spotbugs" || true)
sb_advise=$(grep -c '^ADVISORY|' "$WORK/spotbugs" || true)

if [ "$sb_block" -gt 0 ]; then
  echo "  FAIL  $sb_block blocking finding(s):"
  echo
  grep '^BLOCKING|' "$WORK/spotbugs" | sort -t'|' -k2,2 -k3,3n \
    | awk -F'|' '{ printf "    %s:%s\n      [%s] %s\n", $2, $3, $4, $5 }'
  blocking=$((blocking + sb_block))
  sections_failed="$sections_failed spotbugs"
else
  echo "  PASS  no blocking SpotBugs findings in changed lines"
fi

if [ "$sb_advise" -gt 0 ]; then
  echo
  echo "  ADVISORY  $sb_advise heuristic finding(s) - do not block, but each"
  echo "            must be dispositioned in your completion report (fix, or"
  echo "            one line saying why it is correct as written):"
  echo
  grep '^ADVISORY|' "$WORK/spotbugs" | sort -t'|' -k2,2 -k3,3n \
    | awk -F'|' '{ printf "    %s:%s\n      [%s] %s\n", $2, $3, $4, $5 }'
  advisory=$((advisory + sb_advise))
fi

# ---------------------------------------------------------------------------
# 4. Copy-paste duplication (CPD at 50 tokens, tighter than the repo gate)
# ---------------------------------------------------------------------------

hr
echo "4. Duplication (CPD, 50-token blocks)"
hr

CPD="target/clean-code/cpd.xml"
if [ -f "$CPD" ]; then
  awk -v scope="$SCOPE" '
    NR == FNR { split($0,p,":"); KEEPFILE[p[1]]=1; next }
    /<duplication / { tok=$0; sub(/.*tokens="/,"",tok); sub(/".*/,"",tok); nf=0; hit=0; buf="" }
    /<file / {
      f=$0; sub(/.*path="/,"",f); sub(/".*/,"",f); gsub(/\\/,"/",f); sub(/^.*\/src\//,"src/",f)
      l=$0; sub(/.*line="/,"",l); sub(/".*/,"",l)
      nf++; buf = buf sprintf("      %s:%s\n", f, l)
      if (scope == "all" || (f in KEEPFILE)) hit=1
    }
    /<\/duplication>/ { if (hit && nf > 1) printf "    %s duplicated tokens across %d sites:\n%s", tok, nf, buf }
  ' "$WORK/files" "$CPD" > "$WORK/cpd.out"

  if [ -s "$WORK/cpd.out" ]; then
    echo "  FAIL  duplicated blocks involving your changed files:"
    echo
    cat "$WORK/cpd.out"
    blocking=$((blocking + 1))
    sections_failed="$sections_failed duplication"
  else
    echo "  PASS  no 50+ token duplication involving changed files"
  fi
else
  echo "  SKIP  no CPD report produced (no duplication found)"
fi

# ---------------------------------------------------------------------------
# 5. Textual smells PMD has no rule for
# ---------------------------------------------------------------------------

hr
echo "5. Commented-out code, deferred work, suppressions"
hr

text_fail=0

# Only look at lines this change actually added, so a file's existing debt is
# not attributed to whoever touched it next.
if [ "$SCOPE" = "all" ]; then
  : > "$WORK/added.txt"
  while IFS= read -r f; do
    [ -f "$f" ] && awk -v F="$f" '{ print F "|" FNR "|" $0 }' "$f" >> "$WORK/added.txt"
  done < "$WORK/files"
else
  awk '
    /^\+\+\+ b\// { file = substr($0, 7); next }
    /^@@ / { split($3, a, ","); ln = a[1]; sub(/^\+/, "", ln); next }
    /^\+/ && !/^\+\+\+/ { print file "|" ln "|" substr($0, 2); ln++ }
  ' "$WORK/diff" > "$WORK/added.txt"

  # Untracked files again - see the note in the scope section above.
  while IFS= read -r uf; do
    [ -n "$uf" ] && [ -f "$uf" ] || continue
    awk -v F="$uf" '{ print F "|" FNR "|" $0 }' "$uf" >> "$WORK/added.txt"
  done < "$WORK/untracked"
fi

report_text_smell() {
  local label="$1" pattern="$2" advice="$3"
  local hits
  hits=$(grep -E "$pattern" "$WORK/added.txt" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "  FAIL  $label:"
    printf '%s\n' "$hits" | awk -F'|' '{ printf "    %s:%s\n      %s\n", $1, $2, substr($3,1,100) }'
    echo "      -> $advice"
    text_fail=1
  fi
}

# Commented-out code. Detected by SHAPE, not keywords: a comment whose body
# ends in ';', '{' or '}' is a statement or a block, and prose almost never
# ends that way. The keyword alternative catches a commented-out control
# structure whose body is on the following line.
report_text_smell \
  "commented-out code" \
  '\|[0-9]+\|[[:space:]]*//[[:space:]]*(([^[:space:]].*)?[;{}][[:space:]]*$|(if|for|while|switch|catch|else)[[:space:]]*\(|@Override)' \
  "Delete it. Version control is the record of code that used to exist."

# "We'll fix it later" markers - Clean Coder professionalism.
report_text_smell \
  "deferred-work marker" \
  '\|[0-9]+\|.*(//|/\*|\*)[[:space:]]*(TODO|FIXME|XXX|HACK)' \
  "Do it now, or open an issue and reference it by number instead."

# PMD suppressions. workflow.md says to decompose, never disable a check; this
# is that rule mechanized. The one documented exception (a library override
# whose signature mandates too many params) is ExcessiveParameterList only.
sup=$(grep -E '\|[0-9]+\|.*@SuppressWarnings\("PMD' "$WORK/added.txt" 2>/dev/null \
      | grep -v 'ExcessiveParameterList' || true)
if [ -n "$sup" ]; then
  echo "  FAIL  new PMD suppression:"
  printf '%s\n' "$sup" | awk -F'|' '{ printf "    %s:%s\n      %s\n", $1, $2, substr($3,1,100) }'
  echo "      -> \"Fixed\" means decomposed, not suppressed. The only allowed"
  echo "         suppression is ExcessiveParameterList on a library override"
  echo "         (.claude/workflow.md, 'Constraints')."
  text_fail=1
fi

if [ "$text_fail" -eq 0 ]; then
  echo "  PASS  no commented-out code, deferred-work markers, or new suppressions"
else
  blocking=$((blocking + 1))
  sections_failed="$sections_failed text-smells"
fi

# ---------------------------------------------------------------------------
# 6. CRAP (per-method complexity x coverage), repo-wide
#    Section 1 ran the CRAP gate with -Dcrap.mode=--report-only so the build
#    could finish; this section decides from its report. Not diff-scoped:
#    CRAP is per method, and crap-baseline.txt already covers legacy methods.
#    Optional: skipped when the project has no quality-gates.properties.
# ---------------------------------------------------------------------------

hr
echo "6. CRAP (per-method complexity x coverage, crap.max in quality-gates.properties)"
hr

CRAP_REPORT="target/crap/crap.txt"
if [ ! -f quality-gates.properties ]; then
  echo "  SKIP  no CRAP gate configured (no quality-gates.properties)"
elif [ "$RUN_MVN" = 0 ]; then
  echo "  SKIP  --fast skipped mvn verify, so no CRAP report was produced"
elif [ ! -f "$CRAP_REPORT" ]; then
  echo "  FAIL  $CRAP_REPORT was not produced - the CRAP gate did not run"
  blocking=$((blocking + 1))
  sections_failed="$sections_failed crap"
elif grep -q '^FAIL ' "$CRAP_REPORT"; then
  echo "  FAIL  $(grep -c '^FAIL ' "$CRAP_REPORT") CRAP violation(s) (split the method or cover it):"
  grep '^FAIL ' "$CRAP_REPORT" | sed 's/^/    /'
  blocking=$((blocking + 1))
  sections_failed="$sections_failed crap"
else
  echo "  PASS  every method within crap.max or at/under its crap-baseline.txt score"
fi

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------

echo
hr
if [ "$blocking" -gt 0 ]; then
  echo "RESULT: FAIL"
  hr
  echo
  echo "Blocking sections:$sections_failed"
  echo
  echo "You may NOT report this task as finished. Fix the violations above and"
  echo "rerun this exact command. Do not suppress a rule to get past it, and do"
  echo "not report the task done with a caveat - if a violation cannot be fixed,"
  echo "stop and report the blocker to the orchestrator instead."
  exit 1
fi

echo "RESULT: MECHANICAL CHECKS PASS"
hr
echo
if [ "$advisory" -gt 0 ]; then
  echo "$advisory advisory finding(s) above still need a disposition."
  echo
fi
cat <<'EOF'
The machine has checked what it can. These rules cannot be automated and are
still owed - answer every line, in the completion report, with PASS or FAIL and
one clause of evidence. "All good" is not an answer; name the file.

  [ ] SLAP        Every function I added does its work at ONE level of
                  abstraction - no function mixes orchestration (calling named
                  steps) with detail (index arithmetic, string building).
                  Evidence: name the longest function you added and its level.
  [ ] SRP         Every class I touched can be described in one sentence with
                  no "and". Evidence: give that sentence for each new class.
  [ ] Naming      Every name I introduced can be understood without reading its
                  implementation, and no name needs a comment to explain it.
  [ ] Why-not-what Every comment I added explains WHY, not WHAT. A comment that
                  restates the code below it has been deleted or the code
                  renamed instead. Evidence: quote one comment you kept.
  [ ] Test intent Each test I added fails for exactly ONE reason, and its name
                  says which. Evidence: name one test and the single reason.
  [ ] AAA         Each test has visible arrange / act / assert phases, in that
                  order, with no assertion before the act.
  [ ] No new debt I introduced no code path that exists only for tests, and no
                  abstraction with a single caller added "for later".
  [ ] Single answer For each thing a changed UI/presentation class shows or
                  decides, the domain method that supplies it - the UI
                  translates, it doesn't re-derive a rule the domain owns.
                  Evidence: name one UI method and the domain method it calls.

Design lens behind these: the uncle-bob-craft skill.
EOF
exit 0
