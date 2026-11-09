"""The release gate on a full UI suite pass (#807): scripts/ui-suite-stamp.sh and ship-release.sh's refusal, in
throwaway repositories. ship-release.sh is only run where it refuses, before it checks out or builds anything."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PBXPROJ = 'CacheDrop/CacheDrop.xcodeproj/project.pbxproj'


class StampRepo(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.home)
        self.repo = self.home / 'mac-cleaner'
        (self.repo / 'scripts').mkdir(parents=True)
        for script in ('ui-suite-stamp.sh', 'ship-release.sh'):
            shutil.copy2(ROOT / 'scripts' / script, self.repo / 'scripts' / script)
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.email', 'test@example.com')
        self.git('config', 'user.name', 'Test')
        self.write(PBXPROJ, 'MARKETING_VERSION = 1.2.3;\n')
        self.write('CacheDrop/UITests/AUITests.swift', 'one\n')
        self.write('Packages/CacheDropCore/Core.swift', 'one\n')
        self.write('docs/releases/1.2.3.html', '<p>notes</p>\n')
        self.commit('start')

    def git(self, *args, cwd=None):
        return subprocess.run(['git', *args], cwd=cwd or self.repo, check=True, capture_output=True,
                              text=True).stdout.strip()

    def write(self, name, text):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def commit(self, message):
        self.git('add', '-A')
        self.git('commit', '-q', '-m', message)
        return self.git('rev-parse', 'HEAD')

    def stamp(self, *args, cwd=None):
        return subprocess.run(['bash', 'scripts/ui-suite-stamp.sh', *args], cwd=cwd or self.repo,
                              capture_output=True, text=True)


class UISuiteStampTests(StampRepo):
    def test_no_stamp_is_refused_with_the_command_to_run(self):
        result = self.stamp('matches', 'HEAD')
        self.assertEqual(result.returncode, 1)
        self.assertIn('No full UI suite pass is recorded', result.stderr)
        self.assertIn('scripts/ui-journeys.sh --all', result.stderr)

    def test_a_stamp_holds_across_docs_scripts_and_release_notes_only(self):
        stamped = self.git('rev-parse', 'HEAD')
        self.assertEqual(self.stamp('write', stamped).returncode, 0)
        self.write('docs/releases/1.2.4.html', '<p>more</p>\n')
        self.write('scripts/other.sh', 'echo\n')
        self.write('docs/RESET.md', 'Decision\n')
        release = self.commit('release notes only')
        result = self.stamp('matches', release)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(stamped[:12], result.stdout)

    def test_a_change_to_app_or_package_sources_is_refused_naming_the_stamped_commit(self):
        stamped = self.git('rev-parse', 'HEAD')
        self.stamp('write', stamped)
        for path in ('CacheDrop/UITests/AUITests.swift', 'Packages/CacheDropCore/Core.swift'):
            with self.subTest(path):
                self.write(path, path + ' changed\n')
                release = self.commit('change ' + path)
                result = self.stamp('matches', release)
                self.assertEqual(result.returncode, 1)
                self.assertIn(f'The last full UI suite pass is for {stamped[:12]}', result.stderr)
                self.assertIn('scripts/ui-journeys.sh --all', result.stderr)

    def test_current_needs_committed_app_sources(self):
        head = self.git('rev-parse', 'HEAD')
        self.write('docs/notes.md', 'uncommitted docs don\'t matter\n')
        self.assertEqual(self.stamp('current').stdout.strip(), head)
        self.write('CacheDrop/New.swift', 'untracked\n')
        result = self.stamp('current')
        self.assertEqual(result.returncode, 1)
        self.assertIn('uncommitted changes', result.stderr)

    def test_a_stamp_written_in_a_worktree_counts_in_the_main_checkout(self):
        worktree = self.home / 'wt'
        self.git('worktree', 'add', '-q', '--detach', str(worktree))
        self.assertEqual(self.stamp('write', 'HEAD', cwd=worktree).returncode, 0)
        self.assertEqual(self.stamp('matches', 'HEAD').returncode, 0)


class ShipReleaseGateTests(StampRepo):
    def setUp(self):
        super().setUp()
        origin = self.home / 'origin.git'
        self.git('clone', '-q', '--bare', str(self.repo), str(origin), cwd=self.home)
        self.git('remote', 'add', 'origin', str(origin))
        self.checkout = self.home / 'mac-cleaner-release-1.2.3'

    def ship(self):
        return subprocess.run(['bash', 'scripts/ship-release.sh', '1.2.3'], cwd=self.repo, capture_output=True,
                              text=True)

    def test_without_a_stamp_it_refuses_before_any_checkout(self):
        result = self.ship()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('No full UI suite pass is recorded', result.stderr)
        self.assertFalse(self.checkout.exists())

    def test_a_stamp_for_other_app_code_is_refused_before_any_checkout(self):
        self.write('CacheDrop/UITests/AUITests.swift', 'unreleased\n')
        self.stamp('write', self.commit('unreleased app change'))
        result = self.ship()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('The last full UI suite pass is for', result.stderr)
        self.assertFalse(self.checkout.exists())

    def test_a_stamp_for_the_same_app_code_passes_the_gate(self):
        # The throwaway repository has no release-notes.py or release.sh, so the run stops right after the gate.
        self.stamp('write', 'HEAD')
        self.write('docs/releases/1.2.3.html', '<p>final notes</p>\n')
        self.commit('docs only')
        self.git('push', '-q', 'origin', 'main')
        result = self.ship()
        self.assertIn('The full UI suite passed on', result.stdout, result.stderr)
        self.assertIn('==> Clean checkout', result.stdout)

    def test_the_gate_runs_before_the_checkout_and_the_build(self):
        text = (ROOT / 'scripts/ship-release.sh').read_text()
        gate = text.index('ui-suite-stamp.sh" matches "$commit"')
        self.assertLess(gate, text.index('worktree add'))
        self.assertLess(gate, text.index('scripts/release.sh --artifact-base-url'))


if __name__ == '__main__':
    unittest.main()
