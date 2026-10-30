import base64
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SparkleReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / 'CacheDrop.app'
        (self.app / 'Contents').mkdir(parents=True)
        self.public = base64.b64encode(b'k' * 32).decode()
        self.info = dict(CFBundleIdentifier='com.patrickbourget.CacheDrop', CFBundleShortVersionString='0.9.4',
                         CFBundleVersion='5', LSMinimumSystemVersion='26.0', SUPublicEDKey=self.public)
        with (self.app / 'Contents/Info.plist').open('wb') as f:
            plistlib.dump(self.info, f)
        self.dmg = self.root / 'CacheDrop-0.9.4.dmg'
        self.dmg.write_bytes(b'final stapled disk image')
        self.notes = self.root / 'notes.html'
        self.notes.write_text('<p>Reviewed improvements.</p>')
        self.tools = self.root / 'tools'
        self.tools.mkdir()
        self.signature = base64.b64encode(b's' * 64).decode()
        self.env = dict(os.environ, PUBLIC=self.public, SIGNATURE=self.signature)
        self.tool('generate_keys', 'print(os.environ["PUBLIC"])')
        self.tool('sign_update', '''
if '--verify' not in sys.argv: print(os.environ['SIGNATURE'])
''')
        self.tool('generate_appcast', '''
from pathlib import Path
out = Path(sys.argv[sys.argv.index('-o') + 1])
source = Path(sys.argv[-1]); dmg = next(source.glob('*.dmg'))
url = sys.argv[sys.argv.index('--download-url-prefix') + 1] + dmg.name
out.write_text(''' + repr('''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>5</sparkle:version><sparkle:shortVersionString>0.9.4</sparkle:shortVersionString><description>&lt;p&gt;Reviewed improvements.&lt;/p&gt;</description><enclosure url="{url}" length="{length}" type="application/octet-stream" sparkle:edSignature="{signature}"/></item></channel></rss>''') + '''.format(url=url, length=dmg.stat().st_size, signature=os.environ['SIGNATURE']))
''')

    def tool(self, name, body):
        path = self.tools / name
        path.write_text('#!' + sys.executable + '\nimport os, sys\n' + body + '\n')
        path.chmod(0o755)

    def generate(self):
        return subprocess.run([sys.executable, str(ROOT / 'scripts/sparkle-release.py'), 'generate',
                               '--app', str(self.app), '--dmg', str(self.dmg), '--tools', str(self.tools),
                               '--artifact-base-url', 'https://acceptance.example/updates/0.9.4/',
                               '--release-notes', str(self.notes), '--commit', 'abc123'],
                              env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def test_generates_feed_and_identity_for_exact_final_bytes(self):
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stdout)
        identity = json.loads((self.root / 'release-identity.json').read_text())
        self.assertEqual(identity['version'], '0.9.4')
        self.assertEqual(identity['build'], '5')
        self.assertEqual(identity['length'], 24)
        self.assertEqual(identity['url'], 'https://acceptance.example/updates/0.9.4/CacheDrop-0.9.4.dmg')
        self.assertEqual(identity['edSignature'], self.signature)
        self.assertIn('Reviewed improvements.', (self.root / 'appcast.xml').read_text())

    def test_rejects_mismatched_key_and_does_not_generate_metadata(self):
        self.env['PUBLIC'] = base64.b64encode(b'x' * 32).decode()
        result = self.generate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('does not match', result.stdout)
        self.assertFalse((self.root / 'appcast.xml').exists())
        self.assertFalse((self.root / 'release-identity.json').exists())

    def test_rejects_generator_metadata_mismatch(self):
        self.tool('generate_appcast', "from pathlib import Path\nPath(sys.argv[sys.argv.index('-o') + 1]).write_text('<rss><channel><item><enclosure length=\"999\"/></item></channel></rss>')")
        result = self.generate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('does not match', result.stdout)
        self.assertFalse((self.root / 'release-identity.json').exists())

    def test_signing_failure_is_clear_without_echoing_tool_output(self):
        self.tool('sign_update', "print('PRIVATE_KEY_MUST_NOT_LEAK'); sys.exit(3)")
        result = self.generate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('sign_update failed', result.stdout)
        self.assertNotIn('PRIVATE_KEY_MUST_NOT_LEAK', result.stdout)
        self.assertFalse((self.root / 'appcast.xml').exists())

    def test_rejects_artifact_mutation_during_generation(self):
        self.tool('sign_update', "from pathlib import Path\nif '--verify' in sys.argv: Path(sys.argv[-2]).write_bytes(b'changed')\nelse: print(os.environ['SIGNATURE'])")
        result = self.generate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('changed after signing', result.stdout)
        self.assertFalse((self.root / 'release-identity.json').exists())

    def test_verify_rejects_tampered_identity_metadata(self):
        self.assertEqual(self.generate().returncode, 0)
        path = self.root / 'release-identity.json'
        original = json.loads(path.read_text())
        for key in ('version', 'build', 'bundleID', 'teamID', 'url', 'filename', 'releaseNotesSHA256'):
            changed = dict(original, **{key: 'incorrect'})
            path.write_text(json.dumps(changed))
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/sparkle-release.py'), 'verify',
                                     '--app', str(self.app), '--dmg', str(self.dmg), '--tools', str(self.tools),
                                     '--artifact-base-url', 'https://acceptance.example/updates/0.9.4/',
                                     '--release-notes', str(self.notes)],
                                    env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertNotEqual(result.returncode, 0, key + ': ' + result.stdout)


if __name__ == '__main__':
    unittest.main()
