import contextlib
import importlib.util
import io
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('merge_pr', ROOT / 'scripts/merge-pr.py')
merge_pr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merge_pr)

PORCELAIN = '''worktree /w/mac-cleaner
HEAD aaa
branch refs/heads/main

worktree /w/mac-cleaner-669
HEAD bbb
branch refs/heads/chore/669-merge-pr-script

worktree /w/release
HEAD ccc
detached
'''


def check(conclusion='SUCCESS', status='COMPLETED', name='test-and-build'):
    return {'name': name, 'status': status, 'conclusion': conclusion}


class MergePrTests(unittest.TestCase):
    """The parts of scripts/merge-pr.py that don't need GitHub (#669)."""

    def test_the_worktree_is_found_by_its_checked_out_branch(self):
        self.assertEqual(merge_pr.worktree_for(PORCELAIN, 'chore/669-merge-pr-script'), '/w/mac-cleaner-669')
        self.assertEqual(merge_pr.worktree_for(PORCELAIN, 'main'), '/w/mac-cleaner')
        self.assertIsNone(merge_pr.worktree_for(PORCELAIN, 'chore/669'), 'a prefix is not a match')

    def test_ci_counts_only_finished_checks_on_the_pushed_head(self):
        self.assertEqual(merge_pr.ci_state({'headRefOid': 'old', 'statusCheckRollup': [check()]}, 'new'), 'pending')
        self.assertEqual(merge_pr.ci_state({'headRefOid': 'new', 'statusCheckRollup': []}, 'new'), 'pending')
        self.assertEqual(merge_pr.ci_state({'headRefOid': 'new', 'statusCheckRollup': [
            check(conclusion=None, status='IN_PROGRESS')]}, 'new'), 'pending')
        self.assertEqual(merge_pr.ci_state({'headRefOid': 'new', 'statusCheckRollup': [
            check(), check('SKIPPED', name='other')]}, 'new'), 'pass')
        self.assertEqual(merge_pr.ci_state({'headRefOid': 'new', 'statusCheckRollup': [
            check(), check('FAILURE', name='other')]}, 'new'), 'fail')


    def refused(self, argv):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
            merge_pr.parse_args(argv)
        return raised.exception.code

    def test_a_pr_that_closes_nothing_says_so_with_expect_none(self):
        args = merge_pr.parse_args(['692', '--expect-none'])
        self.assertEqual((args.pr, args.issues, args.expect_none), (692, [], True))
        self.assertEqual(merge_pr.closing_expectation(args), ['--expect-none'])

    def test_issues_are_passed_on_to_the_closing_check(self):
        args = merge_pr.parse_args(['700', '698', 'owner/repo#5', '--trailer', 'Key: value'])
        self.assertEqual((args.issues, args.expect_none), (['698', 'owner/repo#5'], False))
        self.assertEqual(merge_pr.closing_expectation(args), ['--expect', '698', 'owner/repo#5'])

    def test_neither_issues_nor_expect_none_is_refused(self):
        self.assertEqual(self.refused(['692']), 2)
        self.assertEqual(self.refused(['692', '--trailer', 'Key: value']), 2)

    def test_issues_and_expect_none_together_are_refused(self):
        self.assertEqual(self.refused(['692', '45', '--expect-none']), 2)


if __name__ == '__main__':
    unittest.main()
