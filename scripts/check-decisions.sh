#!/bin/bash
# Fails when docs/RESET.md's Decisions aren't numbered uniquely and in increasing order.
#
# RESET.md merges with git's union driver (.gitattributes), so parallel branches that each append a Decision merge
# without conflicts, though their Decisions may land in either order. Union keeps both sides of any clash too: two
# branches amending the same Decision leave it twice. This check catches all three, and two branches that took the same
# number; reorder or deduplicate the lines it names. Gaps in the numbering are historical.
#
#   scripts/check-decisions.sh        exit 0 when clean; otherwise prints each offending number
set -uo pipefail
cd "$(dirname "$0")/.."
grep -E '^[0-9]+\. \*\*' docs/RESET.md | sed -E 's/^([0-9]+)\..*/\1/' | awk '
  NR > 1 && $1 <= last { printf "Decision %d follows %d in docs/RESET.md: renumber it or remove the duplicate.\n", $1, last; bad = 1 }
  { last = $1 }
  END { exit bad }
'
