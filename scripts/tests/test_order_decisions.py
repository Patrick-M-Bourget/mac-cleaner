import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/order-decisions.py'

BEFORE = '''# Plan

1. A numbered step before the Decisions, never moved.
3. Another one, out of order on purpose.

## Decisions (grilled)
Decisions are append-only.

1. First.
2. **Second, with a list:**
    - one indented line;
    - another.

'''
AFTER = '''## Later section
2. Not a Decision either.
'''


def section(*entries):
    """The Decisions section with `entries` in the given order and the gaps they had in the fixture."""
    return BEFORE + ''.join(entries) + AFTER


FIVE = '5. Fifth, one line.\n'
SEVEN = '7. **Seventh, two lines.**\n    Its second line.\n\n'
NINE = '9. Ninth.\n'


class OrderDecisionsTests(unittest.TestCase):
    """scripts/order-decisions.py puts a union merge's Decisions back in number order (#727)."""

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.path = Path(temp.name) / 'RESET.md'

    def order(self, text):
        self.path.write_text(text)
        os.utime(self.path, (1, 1))
        result = subprocess.run([sys.executable, '-B', str(SCRIPT), str(self.path)], capture_output=True, text=True)
        return result, self.path.read_text()

    def test_out_of_order_entries_move_whole_and_nothing_else_changes(self):
        # A union merge appends main's 9 after the branch's 5 and 7, and the gap after 7 stays where it was.
        result, text = self.order(BEFORE + '5. Fifth, one line.\n9. Ninth.\n7. **Seventh, two lines.**\n    Its second line.\n\n' + AFTER)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(text, BEFORE + '5. Fifth, one line.\n7. **Seventh, two lines.**\n    Its second line.\n9. Ninth.\n\n' + AFTER)
        self.assertIn('moved', result.stdout)

    def test_the_last_entry_of_the_file_moves_too(self):
        tail = '## Decisions\n\n2. Two.\n3. Three,\n    continued.\n1. One, last in the file without a newline'
        result, text = self.order(tail)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(text, '## Decisions\n\n1. One, last in the file without a newline\n2. Two.\n3. Three,\n    continued.')

    def test_entries_already_in_order_leave_the_file_untouched(self):
        result, text = self.order(section(FIVE, SEVEN, NINE))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(text, section(FIVE, SEVEN, NINE))
        self.assertEqual(self.path.stat().st_mtime, 1, 'an in-order file is not rewritten')
        self.assertIn('already in order', result.stdout)

    def test_a_duplicate_number_is_refused_and_the_file_left_alone(self):
        duplicate = section(NINE, FIVE, '5. Another fifth.\n')
        result, text = self.order(duplicate)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Decision 5', result.stdout)
        self.assertEqual(text, duplicate)
        self.assertEqual(self.path.stat().st_mtime, 1)

    def test_a_file_without_decisions_is_refused(self):
        result, text = self.order('# Plan\n\n2. Two.\n1. One.\n')
        self.assertEqual(result.returncode, 1)
        self.assertIn('no "## Decisions" section', result.stdout)
        self.assertEqual(text, '# Plan\n\n2. Two.\n1. One.\n')


if __name__ == '__main__':
    unittest.main()
