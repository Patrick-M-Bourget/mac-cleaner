import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReleaseSigningTests(unittest.TestCase):
    def test_distribution_requires_all_sparkle_nested_helpers(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / 'CacheDrop.app'
            (app / 'Contents/Frameworks/Sparkle.framework/Versions/B').mkdir(parents=True)
            result = subprocess.run(['/bin/bash', str(ROOT / 'scripts/sign-release-app.sh'), str(app), '-', '8F5K2ZRP5T', '--adhoc'],
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('missing Sparkle code', result.stdout)


if __name__ == '__main__':
    unittest.main()
