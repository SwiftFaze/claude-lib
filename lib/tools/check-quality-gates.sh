#!/usr/bin/env bash
#
# Ratchets the JaCoCo/PIT quality gates in pom.xml so weakening one requires
# a human to explicitly approve it, instead of landing as one quiet line in
# a 400+ line file nobody diffs closely.
#
# Prose documenting a ratchet is not enforcement against the actor these
# gates exist to constrain - the same reasoning behind
# .claude/tools/check-instruction-budget.sh's own ratchet: if it is
# mechanically checkable, write the check, not the rule.
#
# Compares the PR's gate configuration in pom.xml against the base branch's
# and fails on any change in the weaker direction:
#   - a lowered (or removed) JaCoCo <minimum>, at BUNDLE or SOURCEFILE,
#     LINE or BRANCH
#   - a lowered (or removed) PIT <mutationThreshold>
#   - a newly added entry in JaCoCo's jacoco-check <excludes>, PMD's
#     <excludes>, or PIT's <excludedClasses>
#   - a removed entry from PIT's <targetClasses> (un-targeting a class
#     removes it from mutation testing entirely - the same shape of
#     weakening as an exclusion, just phrased as a removal instead of an
#     addition)
#   - a newly added (or reintroduced) archunit_ignore_patterns.txt anywhere
#     in the tree - this file makes ArchUnit silently skip any violation
#     matching its regex patterns, and nothing in the filename says so
#   - a raised (or removed) crap.max in quality-gates.properties, or an
#     added entry / raised score in crap-baseline.txt (the CRAP gate;
#     here RAISING the number is the weakening)
#   - new @Generated usage in src/main/java - JaCoCo (0.8.2+) and PIT both
#     drop any class/method carrying an annotation whose SIMPLE NAME is
#     Generated from the coverage denominator, regardless of which package
#     it comes from, which raises the score with no threshold or exclusion
#     change to review. Checked as a delta (occurrence count per changed
#     file, base vs head), not an absolute ban, so a genuinely justified
#     @Generated on real generated code stays possible - it just can't land
#     silently. Unlike a visible suppression annotation, this bypass leaves
#     no trace in the diff of the gate configuration itself.
#
# Raising a floor, adding a target, or removing an exclusion always passes.
# This does not block weakening outright - a genuinely justified change
# (e.g. a whole excluded subsystem being deleted) must still be possible -
# it just stops being silent: the check fails loudly, and a human has to
# read the diff and explicitly approve past it, with the reason recorded in
# the PR.
#
# It fails LOUDLY (exit 2), not silently, if it cannot find a gate it
# expects to find - a structural pom.xml reformat could otherwise make this
# check stop checking without anyone noticing. See die_missing() below.
# A list or gate absent on BOTH sides is simply not configured and is skipped.
#
# Usage:  bash .claude/tools/check-quality-gates.sh [--base <ref>]
# Env:    BASE_REF (default develop), HEAD_REF (default: current branch).
# Exit:   0 no weakening found (or branch exempt)
#         1 a weakening was found
#         2 the script could not read a gate it expected to find

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

BASE_REF="${BASE_REF:-develop}"
while [ $# -gt 0 ]; do
  case "$1" in
    --base) shift; BASE_REF="${1:-}" ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

HEAD_REF="${HEAD_REF:-$(git branch --show-current 2>/dev/null)}"
case "$HEAD_REF" in
  release-please--branches--*|"$BASE_REF")
    echo "Exempt branch '$HEAD_REF' - skipping."; exit 0 ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

HEAD_POM="pom.xml"
BASE_POM="$WORK/base-pom.xml"
BASE_REV="origin/$BASE_REF"
if ! git show "$BASE_REV:pom.xml" > "$BASE_POM" 2>/dev/null; then
  BASE_REV="$BASE_REF"
  if ! git show "$BASE_REV:pom.xml" > "$BASE_POM" 2>/dev/null; then
    echo "::error::could not read pom.xml from base ref '$BASE_REF' (tried origin/$BASE_REF and $BASE_REF)." >&2
    exit 2
  fi
fi
# $BASE_REV now names whichever of origin/$BASE_REF or $BASE_REF actually
# resolved - reused below for the tree-wide (not just pom.xml) diff checks.

status=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# extract_block FILE START_PATTERN END_PATTERN - print the lines from the
# first line matching START_PATTERN through the next line matching
# END_PATTERN (inclusive). Prints nothing if START_PATTERN never matches.
extract_block() {
  awk -v s="$2" -v e="$3" '
    $0 ~ s {f=1}
    f {print}
    f && $0 ~ e {exit}
  ' "$1"
}

# jacoco_minimum FILE ELEMENT COUNTER - the <minimum> of the JaCoCo rule
# with <element>ELEMENT</element> at the first <counter>COUNTER</counter>
# limit inside that rule, or empty if that rule/counter doesn't exist.
jacoco_minimum() {
  awk -v el="$2" -v co="$3" '
    $0 ~ "<element>" el "</element>" {inrule=1}
    inrule && $0 ~ "<counter>" co "</counter>" {inlimit=1}
    inlimit && match($0, /<minimum>[0-9.]+<\/minimum>/) {
      val=substr($0, RSTART, RLENGTH)
      gsub(/<\/?minimum>/, "", val)
      print val
      exit
    }
    inrule && /<\/rule>/ {exit}
  ' "$1"
}

# mutation_threshold FILE - the committed <mutationThreshold>, or empty.
mutation_threshold() {
  grep -oE '<mutationThreshold>[0-9.]+</mutationThreshold>' "$1" \
    | grep -oE '[0-9.]+' | head -1
}

# list_entries FILE START_PATTERN END_PATTERN TAG - the text content of
# every <TAG>...</TAG> between START_PATTERN and END_PATTERN, one per line.
list_entries() {
  extract_block "$1" "$2" "$3" \
    | grep -oE "<$4>[^<]+</$4>" | sed -E "s#</?$4>##g"
}

die_missing() {
  echo "::error::check-quality-gates.sh could not find $1 in $2 - a gate" >&2
  echo "this check expects went missing (pom.xml restructured?). Failing" >&2
  echo "loudly rather than silently passing - see check-quality-gates.sh." >&2
  exit 2
}

lowered() { awk -v h="$1" -v b="$2" 'BEGIN{exit !(h < b)}'; }

# ---------------------------------------------------------------------------
# JaCoCo floors: BUNDLE/SOURCEFILE x LINE/BRANCH
# ---------------------------------------------------------------------------

for element in BUNDLE SOURCEFILE; do
  for counter in LINE BRANCH; do
    head_val=$(jacoco_minimum "$HEAD_POM" "$element" "$counter")
    base_val=$(jacoco_minimum "$BASE_POM" "$element" "$counter")

    # Neither side has this rule/counter - not this check's problem.
    [ -z "$head_val" ] && [ -z "$base_val" ] && continue

    if [ -n "$base_val" ] && [ -z "$head_val" ]; then
      echo "::error file=pom.xml::JaCoCo $element/$counter floor was removed (was $base_val on $BASE_REF)."
      status=1
      continue
    fi

    [ -z "$base_val" ] && continue  # newly added on head - strengthening

    if lowered "$head_val" "$base_val"; then
      echo "::error file=pom.xml::JaCoCo $element/$counter floor lowered from $base_val ($BASE_REF) to $head_val."
      status=1
    fi
  done
done

# ---------------------------------------------------------------------------
# PIT mutationThreshold
# ---------------------------------------------------------------------------

head_mt=$(mutation_threshold "$HEAD_POM")
base_mt=$(mutation_threshold "$BASE_POM")

if [ -n "$base_mt" ] && [ -z "$head_mt" ]; then
  echo "::error file=pom.xml::PIT mutationThreshold was removed (was $base_mt on $BASE_REF)."
  status=1
elif [ -n "$base_mt" ] && [ -n "$head_mt" ] && lowered "$head_mt" "$base_mt"; then
  echo "::error file=pom.xml::PIT mutationThreshold lowered from $base_mt ($BASE_REF) to $head_mt."
  status=1
fi

# ---------------------------------------------------------------------------
# Exclusion lists: JaCoCo jacoco-check, PMD, PIT excludedClasses - any
# newly-added entry is a weakening; a removed entry is fine.
# ---------------------------------------------------------------------------

check_no_added_entries() {
  local label="$1" start="$2" end="$3" tag="$4"
  local head_entries base_entries

  head_entries=$(list_entries "$HEAD_POM" "$start" "$end" "$tag")
  base_entries=$(list_entries "$BASE_POM" "$start" "$end" "$tag")

  [ -z "$head_entries" ] && [ -z "$base_entries" ] && return 0
  [ -z "$head_entries" ] && die_missing "$label's <$tag> list" "pom.xml (head)"

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    if ! grep -qxF "$entry" <<< "$base_entries"; then
      echo "::error file=pom.xml::$label gained a new exclusion not on $BASE_REF: $entry"
      echo "  Adding an exclusion is a gate weakening - state the reason in the PR body."
      status=1
    fi
  done <<< "$head_entries"
}

check_no_added_entries "JaCoCo jacoco-check excludes" \
  '<id>jacoco-check</id>' '</excludes>' "exclude"

check_no_added_entries "PMD excludes" \
  '<artifactId>maven-pmd-plugin</artifactId>' '</excludes>' "exclude"

check_no_added_entries "PIT excludedClasses" \
  '<excludedClasses>' '</excludedClasses>' "param"

# ---------------------------------------------------------------------------
# PIT targetClasses: a REMOVED entry is the weakening here (un-targeting a
# class drops it from mutation testing entirely) - the reverse direction
# from the exclusion lists above.
# ---------------------------------------------------------------------------

head_targets=$(list_entries "$HEAD_POM" '<targetClasses>' '</targetClasses>' "param")
base_targets=$(list_entries "$BASE_POM" '<targetClasses>' '</targetClasses>' "param")

if [ -n "$base_targets" ] && [ -z "$head_targets" ]; then
  die_missing "PIT's <targetClasses> list" "pom.xml (head)"
fi

while IFS= read -r target; do
  [ -z "$target" ] && continue
  if ! grep -qxF "$target" <<< "$head_targets"; then
    echo "::error file=pom.xml::PIT targetClasses lost an entry present on $BASE_REF: $target"
    echo "  Un-targeting a class removes it from mutation testing entirely - state the reason in the PR body."
    status=1
  fi
done <<< "$base_targets"

# ---------------------------------------------------------------------------
# ArchUnit ignore file: archunit_ignore_patterns.txt anywhere in the tree
# makes ArchUnit silently skip every violation matching its regex patterns.
# Added (or reintroduced after a rename/delete-then-readd) is always a
# weakening; a plain removal is fine, hence --diff-filter=d.
# ---------------------------------------------------------------------------

ignore_file_hits=$(git diff --name-only --diff-filter=d "$BASE_REV...HEAD" -- . \
  | grep -E '(^|/)archunit_ignore_patterns\.txt$' || true)

while IFS= read -r f; do
  [ -z "$f" ] && continue
  echo "::error file=$f::archunit_ignore_patterns.txt makes ArchUnit silently skip any violation matching its regex patterns - nothing about the filename says so. Adding or changing one is a gate weakening - state the reason in the PR body, or remove the offending rule from the frozen violation store the normal way instead."
  status=1
done <<< "$ignore_file_hits"

# ---------------------------------------------------------------------------
# CRAP gate (optional). The direction is the REVERSE of
# the coverage floors above: RAISING crap.max is the weakening. crap-baseline.txt
# may only shrink: an added entry or a raised recorded score is a weakening, a
# removed entry passes. A base branch without either file (the change that
# introduces the gate) has nothing to ratchet against, so it passes.
# ---------------------------------------------------------------------------

# Prints "<key> <score>" per baseline entry, skipping comments and blank lines.
baseline_entries() {
  awk '!/^[[:space:]]*(#|$)/ { print $1, $2 }'
}

base_crap_max=$(git show "$BASE_REV:quality-gates.properties" 2>/dev/null   | sed -n 's/^crap\.max[[:space:]]*=[[:space:]]*//p' | tr -d '[:space:]')
head_crap_max=$(sed -n 's/^crap\.max[[:space:]]*=[[:space:]]*//p' quality-gates.properties 2>/dev/null   | tr -d '[:space:]')
if [ -n "$base_crap_max" ]; then
  if [ -z "$head_crap_max" ]; then
    echo "::error file=quality-gates.properties::crap.max was removed (base branch: $base_crap_max) - that disables the CRAP gate."
    status=1
  elif awk -v h="$head_crap_max" -v b="$base_crap_max" 'BEGIN { exit !(h > b) }'; then
    echo "::error file=quality-gates.properties::crap.max raised: base branch $base_crap_max, proposed $head_crap_max."
    echo "  Raising the CRAP limit weakens the gate. If it is genuinely justified, state why in the PR."
    status=1
  fi
fi

if git cat-file -e "$BASE_REV:crap-baseline.txt" 2>/dev/null; then
  base_entries=$(git show "$BASE_REV:crap-baseline.txt" | baseline_entries)
  head_entries=$( { cat crap-baseline.txt 2>/dev/null || true; } | baseline_entries)
  while read -r key head_score; do
    [ -n "$key" ] || continue
    base_score=$(awk -v k="$key" '$1 == k { print $2; exit }' <<< "$base_entries")
    if [ -z "$base_score" ]; then
      echo "::error file=crap-baseline.txt::baseline entry added: $key $head_score"
      echo "  A baseline entry is a gate weakening: it exempts a method from crap.max. State the reason in the PR."
      status=1
    elif awk -v h="$head_score" -v b="$base_score" 'BEGIN { exit !(h > b) }'; then
      echo "::error file=crap-baseline.txt::baseline score raised for $key: base branch $base_score, proposed $head_score"
      status=1
    fi
  done <<< "$head_entries"
fi

# ---------------------------------------------------------------------------
# @Generated usage in src/main/java: JaCoCo (0.8.2+) and PIT both drop any
# class/method carrying an annotation whose SIMPLE NAME is Generated
# (CLASS/RUNTIME retention) from the coverage denominator, regardless of
# which package it's imported from (javax.annotation, jakarta.annotation,
# lombok, a hand-rolled one - all match). Checked as a per-file occurrence
# delta against $BASE_REV, not an absolute ban, so a genuinely justified
# @Generated on real generated code stays possible - it just can't land
# silently. Anchored to start-of-line + whitespace so a comment or string
# literal mentioning @Generated doesn't false-positive.
# ---------------------------------------------------------------------------

generated_pattern='^[[:space:]]*@Generated\b'

changed_main_java=$(git diff --name-only --diff-filter=d "$BASE_REV...HEAD" -- '*.java' \
  | grep '^src/main/java/' || true)

while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue  # path no longer exists at HEAD (rename target elsewhere)

  head_count=$(grep -cE "$generated_pattern" "$f" 2>/dev/null || true)
  head_count=${head_count:-0}
  base_count=$(git show "$BASE_REV:$f" 2>/dev/null | grep -cE "$generated_pattern" || true)
  base_count=${base_count:-0}

  if [ "$head_count" -gt "$base_count" ]; then
    echo "::error file=$f::new @Generated usage ($BASE_REF: $base_count -> head: $head_count) - JaCoCo/PIT silently drop any @Generated class or method from the coverage denominator, whatever package the annotation comes from. State the reason in the PR body, or remove it."
    status=1
  fi
done <<< "$changed_main_java"

if [ "$status" -eq 0 ]; then
  echo "No quality-gate weakening found relative to $BASE_REF."
fi
exit $status
