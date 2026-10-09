#!/usr/bin/env bash
#
# Sets a single-select field (Status, Priority, ...) on an issue's GitHub
# project-board item, adding the issue to the board first if needed, then
# reads the value back. A field that didn't land must not be reported as set,
# so the read-back decides the exit code, not the edit call.
#
#   bash .claude/tools/set-project-field.sh <issue-url> <field> <option>
#   bash .claude/tools/set-project-field.sh https://github.com/o/r/issues/12 Priority P2
#
# The board comes from the environment, falling back to the values below.
# Set them once to match .claude/workflow.md's project configuration.
#   PROJECT_NUMBER   the board's number (gh project list --owner <owner>)
#   PROJECT_OWNER    user or org that owns the board
#
# Needs: gh (authenticated, with the `project` scope) and jq.
# Exit: 0 value read back as requested, 1 read-back mismatch, 2 could not run.

set -uo pipefail

PROJECT_NUMBER="${PROJECT_NUMBER:-}"
PROJECT_OWNER="${PROJECT_OWNER:-}"

if [ $# -ne 3 ]; then
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi
ISSUE_URL="$1"; FIELD="$2"; OPTION="$3"

if [ -z "$PROJECT_NUMBER" ] || [ -z "$PROJECT_OWNER" ]; then
  echo "ERROR: set PROJECT_NUMBER and PROJECT_OWNER (env or this script's defaults)." >&2
  exit 2
fi

project_id=$(gh project view "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json --jq '.id') \
  || { echo "ERROR: cannot read project $PROJECT_OWNER/$PROJECT_NUMBER." >&2; exit 2; }

# item-add is idempotent: it returns the existing item when the issue is already on the board.
item_id=$(gh project item-add "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --url "$ISSUE_URL" --format json --jq '.id') \
  || { echo "ERROR: cannot add $ISSUE_URL to the board." >&2; exit 2; }

fields=$(gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json --limit 100) \
  || { echo "ERROR: cannot list the board's fields." >&2; exit 2; }

field_id=$(printf '%s' "$fields" | FIELD="$FIELD" jq -r '.fields[] | select(.name == env.FIELD) | .id')
option_id=$(printf '%s' "$fields" | FIELD="$FIELD" OPTION="$OPTION" \
  jq -r '.fields[] | select(.name == env.FIELD) | .options[]? | select(.name == env.OPTION) | .id')

if [ -z "$field_id" ]; then
  echo "ERROR: the board has no field named '$FIELD'." >&2; exit 2
fi
if [ -z "$option_id" ]; then
  echo "ERROR: field '$FIELD' has no option '$OPTION'. Options:" >&2
  printf '%s' "$fields" | FIELD="$FIELD" jq -r '.fields[] | select(.name == env.FIELD) | .options[]?.name' | sed 's/^/  /' >&2
  exit 2
fi

gh project item-edit --id "$item_id" --project-id "$project_id" \
  --field-id "$field_id" --single-select-option-id "$option_id" >/dev/null \
  || { echo "ERROR: item-edit failed." >&2; exit 2; }

# Read-back: item-list exposes each field under its lowercased name.
actual=$(gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json --limit 1000 \
  | ITEM="$item_id" KEY="$(printf '%s' "$FIELD" | tr '[:upper:]' '[:lower:]')" \
    jq -r '.items[] | select(.id == env.ITEM) | .[env.KEY] // ""')

if [ "$actual" = "$OPTION" ]; then
  echo "OK   $ISSUE_URL: $FIELD = $OPTION"
  exit 0
fi
echo "FAIL $ISSUE_URL: $FIELD read back as '${actual:-<empty>}', expected '$OPTION'" >&2
exit 1
