"""Version preparation through the owner's release command, in disposable checkouts."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PROJECT = Path('CacheDrop/CacheDrop.xcodeproj/project.pbxproj')


class VersionPreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / 'repo'
        (self.repo / 'scripts').mkdir(parents=True)
        (self.repo / PROJECT).parent.mkdir(parents=True)
        # Keep fixture expectations independent of the owner's next committed release.
        source = (ROOT / PROJECT).read_text()
        source = re.sub(r'(\bMARKETING_VERSION\s*=\s*)[^;]+;', r'\g<1>0.9.3;', source)
        source = re.sub(r'(\bCURRENT_PROJECT_VERSION\s*=\s*)[^;]+;', r'\g<1>4;', source)
        (self.repo / PROJECT).write_text(source)
        for name in ['release.sh', 'prepare-version.py']:
            source = ROOT / 'scripts' / name
            if source.exists():
                shutil.copy2(source, self.repo / 'scripts' / name)
        self.git('init', '-q')
        self.git('add', '.')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'Fixture')
        self.starting_head = self.git('rev-parse', 'HEAD').stdout
        self.calls = Path(self.temp.name) / 'calls'
        bin_dir = Path(self.temp.name) / 'bin'
        bin_dir.mkdir()
        for name in ['xcode-select', 'xcodebuild', 'security', 'codesign', 'hdiutil', 'xcrun']:
            stub = bin_dir / name
            stub.write_text('#!' + sys.executable + '\nimport os, sys\nwith open(os.environ["CALLS"], "a") as f: f.write(sys.argv[0] + "\\n")\nsys.exit(99)\n')
            stub.chmod(0o755)
        self.env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'], CALLS=str(self.calls))

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.repo), *args], text=True, capture_output=True, check=True)

    def bump(self, *args):
        return subprocess.run(['/bin/bash', str(self.repo / 'scripts/release.sh'), '--bump', *args],
                              cwd=self.temp.name, env=self.env, text=True, capture_output=True)

    def test_prepares_explicit_version_and_next_build_without_downstream_operations(self):
        unrelated = self.repo / 'unrelated.txt'
        unrelated.write_text('Keep my local changes.\n')
        result = self.bump('0.10.0')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        contents = (self.repo / PROJECT).read_text()
        self.assertEqual(re.findall(r'MARKETING_VERSION = ([^;]+);', contents), ['0.10.0', '0.10.0'])
        self.assertEqual(re.findall(r'CURRENT_PROJECT_VERSION = ([^;]+);', contents), ['5', '5'])
        self.assertIn('0.10.0 (5)', result.stdout)
        self.assertIn('commit', result.stdout.lower())
        self.assertEqual(unrelated.read_text(), 'Keep my local changes.\n')
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout, self.starting_head)
        self.assertEqual(self.git('diff', '--cached', '--name-only').stdout, '')
        self.assertEqual(self.git('diff', '--name-only').stdout.strip(), str(PROJECT))
        self.assertFalse((self.repo / 'build').exists())
        self.assertFalse(self.calls.exists())

    def test_only_version_values_change_in_the_project_bytes(self):
        project = self.repo / PROJECT
        original = project.read_bytes().replace(b'\n', b'\r\n')
        project.write_bytes(original)
        self.git('add', str(PROJECT))
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'Keep line endings')
        result = self.bump('0.10.0')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        expected = original.replace(b'MARKETING_VERSION = 0.9.3;', b'MARKETING_VERSION = 0.10.0;')
        expected = expected.replace(b'CURRENT_PROJECT_VERSION = 4;', b'CURRENT_PROJECT_VERSION = 5;')
        self.assertEqual(project.read_bytes(), expected)

    def test_invalid_non_increasing_and_ambiguous_arguments_leave_all_files_unchanged(self):
        before = (self.repo / PROJECT).read_bytes()
        for arguments in [(), ('0.10',), ('v0.10.0',), ('0.10.0-beta.1',), ('00.10.0',),
                          ('0.9.3',), ('0.9.2',), ('0.8.99',), ('0.10.0', '--adhoc')]:
            with self.subTest(arguments=arguments):
                result = self.bump(*arguments)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((self.repo / PROJECT).read_bytes(), before)
                self.assertEqual(self.git('status', '--porcelain').stdout, '')
                self.assertEqual(self.git('rev-parse', 'HEAD').stdout, self.starting_head)
                self.assertFalse(self.calls.exists())

    def test_project_changes_are_refused_without_overwriting_or_staging_them(self):
        project = self.repo / PROJECT
        project.write_text(project.read_text().replace('ONLY_ACTIVE_ARCH = YES', 'ONLY_ACTIVE_ARCH = NO', 1))
        self.git('add', str(PROJECT))
        project.write_text(project.read_text() + '\n// Another local edit.\n')
        before = project.read_bytes()
        staged = self.git('show', ':' + str(PROJECT)).stdout
        result = self.bump('0.10.0')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('local changes', result.stderr)
        self.assertEqual(project.read_bytes(), before)
        self.assertEqual(self.git('show', ':' + str(PROJECT)).stdout, staged)
        self.assertFalse(self.calls.exists())

    def commit_project(self, source):
        (self.repo / PROJECT).write_text(source)
        self.git('add', str(PROJECT))
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'Configure fixture')

    def test_next_build_is_above_every_app_configuration(self):
        project = self.repo / PROJECT
        self.commit_project(project.read_text().replace('CURRENT_PROJECT_VERSION = 4;', 'CURRENT_PROJECT_VERSION = 12;', 1))
        result = self.bump('1.0.0')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(re.findall(r'CURRENT_PROJECT_VERSION = ([^;]+);', project.read_text()), ['13', '13'])
        self.assertIn('1.0.0 (13)', result.stdout)
        self.assertFalse(self.calls.exists())

    def test_inconsistent_or_invalid_configuration_fails_before_any_edit(self):
        original = (self.repo / PROJECT).read_text()
        invalid_sources = [original.replace('MARKETING_VERSION = 0.9.3;', 'MARKETING_VERSION = 0.9.2;', 1),
                           original.replace('CURRENT_PROJECT_VERSION = 4;', 'CURRENT_PROJECT_VERSION = 4.2;', 1),
                           original.replace('CURRENT_PROJECT_VERSION = 4;', '', 1)]
        for source in invalid_sources:
            with self.subTest(source=source):
                self.commit_project(source)
                before = (self.repo / PROJECT).read_bytes()
                result = self.bump('0.10.0')
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((self.repo / PROJECT).read_bytes(), before)
                self.assertEqual(self.git('status', '--porcelain').stdout, '')
                self.assertFalse(self.calls.exists())


if __name__ == '__main__':
    unittest.main()
