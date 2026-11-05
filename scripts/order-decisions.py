#!/usr/bin/env python3
"""Put docs/RESET.md's Decisions back in number order after a merge, changing no text (#727).

RESET.md merges with git's union driver (.gitattributes), so merging main into a branch that added Decisions can leave
them out of order. This moves each whole Decision (its numbered line and the lines under it) into number order. Blank
lines between Decisions stay where they were, and the text before and after the list is untouched. A file already in
order is not rewritten. A number used twice is refused: renumber one by hand.

  scripts/order-decisions.py [FILE]    default docs/RESET.md; exit 0 when in order (now or already), 1 when refused
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
NUMBERED = re.compile(r'(\d+)\. ')


def split(text):
    """(before, entries, after) for the `## Decisions` section, or None when there is none.

    A Decision is its numbered line and every line under it up to the next numbered line, the next `## ` heading or the
    end of the file. Each entry is (number, body, gap): its lines without the blank lines that end it, then those blank
    lines. `before + ''.join(body + gap) + after` is the text again.
    """
    lines = text.splitlines(keepends=True)
    heading = next((i for i, line in enumerate(lines) if line.startswith('## Decisions')), None)
    if heading is None:
        return None
    end = next((i for i in range(heading + 1, len(lines)) if lines[i].startswith('## ')), len(lines))
    starts = [i for i in range(heading + 1, end) if NUMBERED.match(lines[i])]
    if not starts:
        return ''.join(lines[:end]), [], ''.join(lines[end:])
    entries = []
    for start, stop in zip(starts, starts[1:] + [end]):
        last = stop
        while last > start + 1 and not lines[last - 1].strip():
            last -= 1
        number = int(NUMBERED.match(lines[start])[1])
        entries.append((number, ''.join(lines[start:last]), ''.join(lines[last:stop])))
    return ''.join(lines[:starts[0]]), entries, ''.join(lines[end:])


def ordered(text):
    """The text with its Decisions in number order; raises ValueError on a duplicate number or no Decisions section."""
    parts = split(text if text.endswith('\n') else text + '\n')
    if parts is None:
        raise ValueError('no "## Decisions" section')
    before, entries, after = parts
    numbers = [number for number, _, _ in entries]
    duplicates = sorted({n for n in numbers if numbers.count(n) > 1})
    if duplicates:
        raise ValueError(', '.join(f'Decision {n}' for n in duplicates) + ' appears more than once: renumber one by hand')
    bodies = [body for _, body, _ in sorted(entries, key=lambda entry: entry[0])]
    result = before + ''.join(body + gap for body, (_, _, gap) in zip(bodies, entries)) + after
    return result if text.endswith('\n') else result[:-1]


def main(argv):
    path = Path(argv[1]) if len(argv) > 1 else ROOT / 'docs/RESET.md'
    text = path.read_text()
    try:
        result = ordered(text)
    except ValueError as error:
        print(f'order-decisions: {path}: {error}')
        return 1
    if result == text:
        print(f'ok    Decisions already in order in {path}')
        return 0
    path.write_text(result)
    print(f'ok    moved Decisions into number order in {path}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
