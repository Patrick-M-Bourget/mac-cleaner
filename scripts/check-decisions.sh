#!/bin/bash
# Fails when docs/RESET.md's Decisions aren't numbered uniquely and in increasing order, or when a branch edits a
# Decision that already exists (#668).
#
# Decisions are append-only: a Decision that changes an earlier one says "amends N" in its own header, and Decision N
# stays as written (`scripts/issues.py decision N` lists what amends it). RESET.md merges with git's union driver
# (.gitattributes), which is safe only for appended text: parallel branches that each append a Decision merge without
# conflicts, though their Decisions may land in either order (scripts/order-decisions.py sorts them, #727), and an
# edited Decision would be kept twice. Gaps in the numbering are historical.
#
# The append-only part compares each Decision with origin/main and with this branch's merge base; it is skipped when
# origin/main isn't available (CI's shallow checkout).
#
#   scripts/check-decisions.sh        exit 0 when clean; otherwise prints each offending number
set -uo pipefail
cd "$(dirname "$0")/.."
base=""
if git rev-parse -q --verify origin/main >/dev/null 2>&1; then
  base=$(git merge-base HEAD origin/main 2>/dev/null || true)
fi
python3 -B - "$base" <<'PY'
import importlib.util
import subprocess
import sys

# What a Decision entry is lives once, in the script that puts them back in order (#727).
spec = importlib.util.spec_from_file_location('order_decisions', 'scripts/order-decisions.py')
order = importlib.util.module_from_spec(spec)
spec.loader.exec_module(order)


def decisions(text):
    """Each Decision's whole text (its numbered line and any indented lines under it), by number, in file order."""
    parts = order.split(text)
    return [(number, body.rstrip()) for number, body, _ in parts[1]] if parts else []


def at(ref):
    result = subprocess.run(['git', 'show', f'{ref}:docs/RESET.md'], capture_output=True, text=True)
    return dict(decisions(result.stdout)) if result.returncode == 0 else {}


bad = False
here = decisions(open('docs/RESET.md').read())
last = None
for number, _ in here:
    if last is not None and number <= last:
        print(f'Decision {number} follows {last} in docs/RESET.md: after a merge, scripts/order-decisions.py puts them '
              f'back in order; a duplicate number needs renumbering or removing.')
        bad = True
    last = number

base = sys.argv[1]
if base:
    main, merge_base = at('origin/main'), at(base)
    for number, text in here:
        known = {v for v in (main.get(number), merge_base.get(number)) if v is not None}
        if known and text not in known:
            print(f'Decision {number} was edited. Decisions are append-only: restore it and say what changed in a new '
                  f'Decision whose header says "amends {number}".')
            bad = True
sys.exit(1 if bad else 0)
PY
