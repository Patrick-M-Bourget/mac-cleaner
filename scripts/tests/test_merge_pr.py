import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import subprocess
import tempfile
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

    def test_after_a_merge_the_decisions_are_put_back_in_order_and_staged(self):
        # main and the branch each append a Decision; the union merge puts main's after the branch's (#727).
        with tempfile.TemporaryDirectory() as temp:
            wt = Path(temp)
            git = lambda *args: subprocess.run(['git', *args], cwd=wt, check=True, capture_output=True, text=True).stdout
            (wt / 'scripts').mkdir()
            (wt / 'docs').mkdir()
            shutil.copy(ROOT / 'scripts/order-decisions.py', wt / 'scripts')
            (wt / '.gitattributes').write_text('docs/RESET.md merge=union\n')
            reset = wt / 'docs/RESET.md'
            reset.write_text('## Decisions\n1. One.\n')
            git('init', '-q', '-b', 'main')
            git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '--allow-empty', '-m', 'empty')
            git('add', '.')
            git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '-m', 'base')
            git('checkout', '-q', '-b', 'branch')
            reset.write_text('## Decisions\n1. One.\n3. Branch.\n')
            git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '-am', 'branch')
            git('checkout', '-q', 'main')
            reset.write_text('## Decisions\n1. One.\n2. Main.\n')
            git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '-am', 'main')
            git('checkout', '-q', 'branch')
            git('merge', '--no-commit', '--no-ff', 'main')
            self.assertEqual(reset.read_text(), '## Decisions\n1. One.\n3. Branch.\n2. Main.\n', 'the fixture reproduces the union merge')

            self.assertIn('moved', merge_pr.order_decisions(str(wt)))
            self.assertEqual(git('show', ':docs/RESET.md'), '## Decisions\n1. One.\n2. Main.\n3. Branch.\n')
            self.assertEqual(git('status', '--porcelain'), 'M  docs/RESET.md\n')

    def test_without_a_merge_in_progress_the_decisions_are_left_to_the_check(self):
        with tempfile.TemporaryDirectory() as temp:
            subprocess.run(['git', 'init', '-q'], cwd=temp, check=True)
            self.assertEqual(merge_pr.order_decisions(temp), 'no merge in progress')


if __name__ == '__main__':
    unittest.main()
