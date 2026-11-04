"""ship-release.sh refuses before touching anything, and release.sh retries every stapler call (1.0.2's network drops)."""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ShipReleaseTests(unittest.TestCase):
    def run_ship(self, *args):
        return subprocess.run([str(ROOT / 'scripts/ship-release.sh'), *args], cwd=ROOT, capture_output=True, text=True)

    def test_it_needs_one_stable_version(self):
        for args in [(), ('1.0',), ('v1.0.2',), ('1.0.2', 'extra')]:
            result = self.run_ship(*args)
            self.assertEqual(result.returncode, 1, args)
            self.assertIn('usage: scripts/ship-release.sh x.y.z', result.stderr)

    def test_it_never_uploads(self):
        text = (ROOT / 'scripts/ship-release.sh').read_text()
        for command in ('publish-release', 'stage-release', 'promote-release', 'curl ', 'supabase '):
            code = [line for line in text.splitlines() if command in line and not line.lstrip().startswith('#') and 'echo' not in line]
            self.assertEqual(code, [], command)


class StaplerRetryTests(unittest.TestCase):
    def test_every_stapler_call_in_release_sh_retries(self):
        text = (ROOT / 'scripts/release.sh').read_text()
        direct = [line for line in text.splitlines() if 'xcrun stapler' in line]
        self.assertEqual(direct, ['    xcrun stapler "$1" "$2" && return 0'], 'only the retrying stapler() calls xcrun stapler')
        self.assertGreaterEqual(len(re.findall(r'^\s*(if .*then )?stapler (staple|validate) ', text, re.M)), 5)


if __name__ == '__main__':
    unittest.main()
