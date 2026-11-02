"""release.sh finds the Sparkle tools without --sparkle-tools (#657), in disposable checkouts."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ('generate_keys', 'sign_update', 'generate_appcast')


class SparkleToolsLookupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = self.base = Path(self.temp.name).resolve()  # git reports /private/var, not /var
        self.main = base / 'main'
        (self.main / 'scripts').mkdir(parents=True)
        shutil.copy2(ROOT / 'scripts/release.sh', self.main / 'scripts/release.sh')
        # Stand-in preflight: records the tools folder it was given, then stops the release before any build.
        (self.main / 'scripts/sparkle-release.py').write_text(
            'import os, sys\n'
            'with open(os.environ["CALLS"], "a") as f: f.write(sys.argv[sys.argv.index("--tools") + 1] + "\\n")\n'
            'sys.exit(99)\n')
        (self.main / '.gitignore').write_text('.build/\n')
        self.git(self.main, 'init', '-q')
        self.git(self.main, 'add', '.')
        self.git(self.main, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'Fixture')
        self.worktree = base / 'release-worktree'
        self.git(self.main, 'worktree', 'add', '-q', '--detach', str(self.worktree))
        self.notes = base / 'notes.html'
        self.notes.write_text('<p>Notes</p>\n')
        self.calls = base / 'calls'
        env = {k: v for k, v in os.environ.items() if k != 'CACHEDROP_SPARKLE_TOOLS'}
        self.env = dict(env, CALLS=str(self.calls))

    def git(self, repo, *args):
        return subprocess.run(['git', '-C', str(repo), *args], text=True, capture_output=True, check=True)

    def tools_in(self, folder):
        folder.mkdir(parents=True)
        for name in TOOLS:
            (folder / name).write_text('')
        return folder

    def release(self, checkout, *args):
        result = subprocess.run(['/bin/bash', str(checkout / 'scripts/release.sh'),
                                 '--artifact-base-url', 'https://example.invalid/updates/1.0.1/',
                                 '--release-notes', str(self.notes), *args],
                                env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        tools = self.calls.read_text().splitlines() if self.calls.exists() else []
        return result, tools

    def test_release_worktree_uses_the_main_checkouts_tools(self):
        tools = self.tools_in(self.main / '.build/sparkle-tools/bin')
        result, used = self.release(self.worktree)
        self.assertEqual(used, [str(tools)], result.stdout)

    def test_checkouts_own_tools_come_before_the_main_checkouts(self):
        self.tools_in(self.main / '.build/sparkle-tools/bin')
        own = self.tools_in(self.worktree / '.build/sparkle-tools/bin')
        result, used = self.release(self.worktree)
        self.assertEqual(used, [str(own)], result.stdout)

    def test_main_checkout_uses_its_own_tools(self):
        tools = self.tools_in(self.main / '.build/sparkle-tools/bin')
        result, used = self.release(self.main)
        self.assertEqual(used, [str(tools)], result.stdout)

    def test_environment_and_flag_override_the_default(self):
        self.tools_in(self.main / '.build/sparkle-tools/bin')
        from_env = self.tools_in(self.base / 'env-tools')
        from_flag = self.tools_in(self.base / 'flag-tools')
        self.env['CACHEDROP_SPARKLE_TOOLS'] = str(from_env)
        result, used = self.release(self.worktree)
        self.assertEqual(used, [str(from_env)], result.stdout)
        result, used = self.release(self.worktree, '--sparkle-tools', str(from_flag))
        self.assertEqual(used, [str(from_env), str(from_flag)], result.stdout)

    def test_missing_tools_name_every_folder_checked(self):
        (self.main / '.build/sparkle-tools/bin').mkdir(parents=True)
        (self.main / '.build/sparkle-tools/bin/generate_keys').write_text('')  # incomplete set
        result, used = self.release(self.worktree)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(used, [])
        self.assertIn(str(self.worktree / '.build/sparkle-tools/bin'), result.stdout)
        self.assertIn(str(self.main / '.build/sparkle-tools/bin'), result.stdout)

    def test_missing_tools_from_the_flag_name_that_folder(self):
        self.tools_in(self.main / '.build/sparkle-tools/bin')
        missing = self.base / 'nowhere'
        result, used = self.release(self.worktree, '--sparkle-tools', str(missing))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(used, [], 'an explicit folder never falls back to the default')
        self.assertIn(str(missing), result.stdout)


if __name__ == '__main__':
    unittest.main()
