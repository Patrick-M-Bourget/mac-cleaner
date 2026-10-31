from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/release-notes.py'
GOOD = ('<div class="cd-card">\n<p class="cd-eyebrow">What’s new in 1.2.3</p>\n<p class="cd-summary">One sentence.</p>\n'
        '<ul class="cd-changes">\n<li>A change.</li>\n</ul>\n</div>\n')


def build(content, version='1.2.3', css='body{margin:0}\n'):
    with tempfile.TemporaryDirectory() as temporary:
        folder = Path(temporary)
        (folder / 'notes.css').write_text(css)
        (folder / f'{version}.html').write_text(content)
        out = folder / 'out.html'
        result = subprocess.run([sys.executable, '-B', str(SCRIPT), version, '--source', str(folder), '--out', str(out)],
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        return result, (out.read_text() if out.exists() else None)


class ReleaseNotesTests(unittest.TestCase):
    def test_combines_the_shared_style_with_the_version_content(self):
        result, text = build(GOOD)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(text.startswith('<style>\nbody{margin:0}\n</style>\n'))
        self.assertTrue(text.endswith(GOOD))

    def test_the_shipped_notes_build(self):
        result = subprocess.run([sys.executable, '-B', str(SCRIPT), '0.9.4', '--out', '/dev/null'], text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_refuses_content_outside_the_format(self):
        for bad, reason in [(GOOD.replace('<li>A change.</li>', '<li>a</li>' * 7), 'at most 6'),
                            (GOOD.replace('One sentence.', 'See <a href="https://x">this</a>.'), 'not allowed'),
                            (GOOD.replace('</div>', '<style>p{}</style></div>'), 'not allowed'),
                            (GOOD.replace('1.2.3', '1.2.4'), 'eyebrow'),
                            (GOOD.replace('<p class="cd-summary">One sentence.</p>\n', ''), 'summary')]:
            result, text = build(bad)
            self.assertNotEqual(result.returncode, 0, bad)
            self.assertIn(reason, result.stdout)
            self.assertIsNone(text)


if __name__ == '__main__':
    unittest.main()
