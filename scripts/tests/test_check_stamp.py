from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CheckStampTests(unittest.TestCase):
    """scripts/check-stamp.sh in a throwaway repository (#667)."""

    def setUp(self):
        self.repo = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.repo)
        (self.repo / 'scripts').mkdir()
        shutil.copy(ROOT / 'scripts/check-stamp.sh', self.repo / 'scripts/check-stamp.sh')
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.email', 'test@example.com')
        self.git('config', 'user.name', 'Test')
        self.write('a.txt', 'one\n')
        self.git('add', '.')
        self.git('commit', '-q', '-m', 'start')

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.repo, check=True, capture_output=True, text=True).stdout

    def write(self, name, text):
        (self.repo / name).write_text(text)

    def stamp(self, *args):
        return subprocess.run(['bash', 'scripts/check-stamp.sh', *args], cwd=self.repo,
                              capture_output=True, text=True).returncode

    def test_a_commit_needs_the_content_the_check_passed_on(self):
        self.write('a.txt', 'two\n')
        self.write('b.txt', 'new\n')
        self.git('add', 'b.txt')
        self.assertEqual(self.stamp('matches', '--all'), 1, 'nothing tested yet')
        self.assertEqual(self.stamp('write'), 0)
        self.assertEqual(self.stamp('matches', '--all'), 0, '`commit -a` commits what was tested')
        self.assertEqual(self.stamp('matches'), 1, 'b.txt without the a.txt edit was never tested')
        self.git('add', 'a.txt')
        self.assertEqual(self.stamp('matches'), 0)
        self.write('a.txt', 'three\n')
        self.git('add', 'a.txt')
        self.assertEqual(self.stamp('matches'), 1, 'an edit after the check needs another run')

    def test_untracked_files_dont_count_and_a_message_only_amend_passes(self):
        self.write('notes.txt', 'scratch\n')
        self.assertEqual(self.stamp('matches'), 0, 'the index is HEAD: nothing new is committed')
        self.write('a.txt', 'two\n')
        self.assertEqual(self.stamp('write'), 0)
        self.assertEqual(self.stamp('matches', '--all'), 0)

    def test_an_add_in_the_same_command_is_judged_on_the_working_tree(self):
        self.write('new.txt', 'untracked until the commit\n')
        self.assertEqual(self.stamp('matches', '--working'), 1)
        self.assertEqual(self.stamp('write'), 0)
        self.assertEqual(self.stamp('matches', '--working'), 0)
        self.write('later.txt', 'made after the check\n')
        self.assertEqual(self.stamp('matches', '--working'), 1)

    def test_each_worktree_keeps_its_own_stamp(self):
        other = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, other)
        self.git('worktree', 'add', '-q', '-b', 'other', str(other / 'wt'))
        self.write('a.txt', 'two\n')
        self.stamp('write')
        (other / 'wt/a.txt').write_text('two\n')
        result = subprocess.run(['bash', 'scripts/check-stamp.sh', 'matches', '--all'], cwd=other / 'wt',
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)


if __name__ == '__main__':
    unittest.main()
