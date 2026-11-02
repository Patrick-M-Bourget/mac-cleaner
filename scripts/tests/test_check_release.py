"""scripts/check-release.sh's license gating branch (#659), on small compiled stand-in apps."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PLACEHOLDER = 'CacheDrop license public key placeholder'
DEVELOPER_DIR = os.environ.get('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')


class LicenseGatingCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / 'repo'
        (self.repo / 'scripts').mkdir(parents=True)
        shutil.copy2(ROOT / 'scripts/check-release.sh', self.repo / 'scripts/check-release.sh')
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'], DEVELOPER_DIR=DEVELOPER_DIR)

    def release_settings(self, conditions):
        """Stand-in for `xcodebuild -showBuildSettings`, which check-release.sh reads the Release conditions from."""
        stub = self.bin / 'xcodebuild'
        stub.write_text('#!' + sys.executable + '\nprint("Build settings for action build and target CacheDrop:")\n'
                        f'print("    SWIFT_ACTIVE_COMPILATION_CONDITIONS = {conditions}")\n'
                        'print("    SWIFT_VERSION = 6.0")\n')
        stub.chmod(0o755)

    def app(self, text):
        """A CacheDrop.app whose executable is a real Mach-O that carries `text` as a string."""
        app = self.base / 'CacheDrop.app'
        macos = app / 'Contents/MacOS'
        macos.mkdir(parents=True)
        source = self.base / 'main.c'
        source.write_text('__attribute__((used)) static const char text[] = "%s";\nint main(void) { return 0; }\n' % text)
        subprocess.run(['xcrun', 'clang', '-o', str(macos / 'CacheDrop'), str(source)], env=self.env, check=True,
                       capture_output=True)
        return app

    def check(self, app):
        return subprocess.run(['/bin/bash', str(self.repo / 'scripts/check-release.sh'), '--app', str(app)],
                              env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def test_gating_on_with_the_placeholder_fails(self):
        self.release_settings('LICENSE_GATING')
        result = self.check(self.app(PLACEHOLDER))
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('still has the placeholder public key', result.stdout)

    def test_gating_on_with_a_real_key_passes(self):
        self.release_settings('LICENSE_GATING')
        result = self.check(self.app('hyBpRb4zRvBKKP/vwMcklOlN33k4IpMGqTqYKisCn8M='))
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_gating_among_other_conditions_still_counts(self):
        self.release_settings('SOMETHING_ELSE LICENSE_GATING')
        result = self.check(self.app(PLACEHOLDER))
        self.assertEqual(result.returncode, 1, result.stdout)

    def test_gating_off_allows_the_placeholder(self):
        self.release_settings('')
        result = self.check(self.app(PLACEHOLDER))
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_a_similar_condition_name_is_not_gating(self):
        self.release_settings('LICENSE_GATING_PREVIEW')
        result = self.check(self.app(PLACEHOLDER))
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_check_looks_for_the_text_the_source_documents(self):
        """#594's bug: guidance and check disagreed on the placeholder. Keep the check's text where the key lives."""
        self.assertIn(PLACEHOLDER, (ROOT / 'scripts/check-release.sh').read_text())
        self.assertIn(PLACEHOLDER, (ROOT / 'Packages/CacheDropCore/Sources/CacheDropCore/LicenseBuiltIns.swift').read_text())


if __name__ == '__main__':
    unittest.main()
