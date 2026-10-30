import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'])

    def executable(self, path, body):
        path.write_text('#!' + sys.executable + '\n' + body)
        path.chmod(0o755)

    def run_command(self, args):
        return subprocess.run(args, env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


class CheckRunnerTests(CommandTests):
    def setUp(self):
        super().setUp()
        self.repo = self.home / 'repo'
        scripts = self.repo / 'scripts'
        scripts.mkdir(parents=True)
        shutil.copy2(ROOT / 'scripts/check.sh', scripts / 'check.sh')
        self.calls = self.home / 'calls'
        self.env['CALLS'] = str(self.calls)
        stub = '''import os, re, sys
from pathlib import Path
call = Path(sys.argv[0]).name + ' ' + ' '.join(sys.argv[1:])
if os.environ.get('LIBDISPATCH_COOPERATIVE_POOL_STRICT') == '1': call += ' [strict]'
with open(os.environ['CALLS'], 'a') as f: f.write(call + '\\n')
if re.search(os.environ.get('FAIL_PATTERN', r'(?!)'), call):
    for i in range(30): print('✔ Test failurePathIsHandled' + str(i) + ' passed')
    print('fixture.swift:7: error: Expectation failed: EARLY_ASSERTION')
    print('FULL_LINE_' + 'x' * 700)
    for i in range(100): print('later passing output', i)
    sys.exit(7)
'''
        for name in ['swift', 'xcodebuild', 'python3']:
            self.executable(self.bin / name, stub)
        for name in ['check-debug-seams.sh', 'check-decisions.sh', 'check-copy.sh', 'check-stored-keys.sh', 'check-release.sh']:
            self.executable(scripts / name, stub)

    def check(self, *args):
        result = self.run_command(['/bin/bash', str(self.repo / 'scripts/check.sh'), *args])
        calls = self.calls.read_text().splitlines()
        return result, calls

    def test_success_keeps_every_suite_and_both_builds(self):
        result, calls = self.check()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(any('CacheDropCore' in c and '[strict]' not in c for c in calls))
        self.assertTrue(any('--skip aRunningToolLeavesTheConcurrencyPoolFree' in c and '[strict]' in c for c in calls))
        self.assertTrue(any('--filter aRunningToolLeavesTheConcurrencyPoolFree' in c and '[strict]' in c for c in calls))
        self.assertTrue(any('Packages/StorageAlerts' in c for c in calls))
        self.assertTrue(any(c.startswith('xcodebuild build ') for c in calls))
        self.assertTrue(any(c.startswith('check-release.sh ') for c in calls))
        self.assertEqual(list(self.repo.glob('.build/check-logs/**/*.*')), [])

    def test_early_errors_and_separate_full_logs_survive(self):
        self.env['FAIL_PATTERN'] = r'^swift .*CacheDropCore'
        result, calls = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('EARLY_ASSERTION', result.stdout)
        logs = [Path(p) for p in re.findall(r'full log: (.+)', result.stdout)]
        self.assertEqual(len(logs), 3, result.stdout)
        self.assertEqual(len(set(logs)), 3)
        for path in logs:
            self.assertTrue(path.is_file())
            self.assertIn('FULL_LINE_' + 'x' * 700, path.read_text())
            self.assertIn('later passing output 99', path.read_text())
        self.assertFalse(any(c.startswith(('xcodebuild ', 'check-release.sh ')) for c in calls))
        self.assertTrue(any('Packages/StorageAlerts' in c for c in calls))

    def test_source_failure_also_prevents_app_builds(self):
        self.env['FAIL_PATTERN'] = r'^check-copy.sh '
        result, calls = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c.startswith(('xcodebuild ', 'check-release.sh ')) for c in calls))

    def test_failed_debug_build_prevents_release(self):
        self.env['FAIL_PATTERN'] = r'^xcodebuild '
        result, calls = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c.startswith('check-release.sh ') for c in calls))

    def test_fast_still_stops_after_normal_core(self):
        result, calls = self.check('--fast')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(any('[strict]' in c or 'StorageAlerts' in c or c.startswith(('xcodebuild ', 'check-release.sh ')) for c in calls))


class ClosingReferenceTests(CommandTests):
    def setUp(self):
        super().setUp()
        self.pages = self.home / 'pages.json'
        self.env['GH_PAGES'] = str(self.pages)
        self.executable(self.bin / 'gh', '''import json, os, sys
if os.environ.get('GH_FAIL'):
    print('GitHub unavailable', file=sys.stderr); sys.exit(1)
if sys.argv[1:3] == ['repo', 'view']:
    print(json.dumps({'nameWithOwner': 'owner/repo'})); sys.exit()
pages = json.load(open(os.environ['GH_PAGES']))
cursor = next((a.split('=', 1)[1] for a in sys.argv if a.startswith('cursor=')), '')
print(json.dumps(pages[int(cursor) if cursor else 0]))
''')

    def page(self, refs, more=False, cursor=None, head='abc123'):
        return {'data': {'repository': {'pullRequest': {
            'url': 'https://github.com/owner/repo/pull/12', 'headRefOid': head,
            'body': 'This does not close #449.',
            'closingIssuesReferences': {'nodes': [{'number': n, 'repository': {'nameWithOwner': repo}} for repo, n in refs],
                                        'pageInfo': {'hasNextPage': more, 'endCursor': cursor}}
        }}}}

    def check(self, pages, *args):
        self.pages.write_text(json.dumps(pages))
        return self.run_command([sys.executable, str(ROOT / 'scripts/check-pr-closing.py'), '12', *args])

    def test_partial_ticket_expects_no_links(self):
        result = self.check([self.page([])], '--expect-none')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('abc123', result.stdout)

    def test_negated_text_does_not_override_actual_closing_metadata(self):
        result = self.check([self.page([('owner/repo', 449)])], '--expect-none')
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('unexpected: owner/repo#449', result.stdout)

    def test_expected_set_is_exact_and_order_independent(self):
        result = self.check([self.page([('owner/repo', 2), ('owner/repo', 1)])], '--expect', '1', '2')
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_missing_and_cross_repository_links_are_reported(self):
        result = self.check([self.page([('other/repo', 1)])], '--expect', '1')
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('missing: owner/repo#1', result.stdout)
        self.assertIn('unexpected: other/repo#1', result.stdout)
        self.assertEqual(self.check([self.page([('other/repo', 1)])], '--expect', 'other/repo#1').returncode, 0)

    def test_later_pages_cannot_hide_unexpected_links(self):
        pages = [self.page([('owner/repo', 1)], True, '1'), self.page([('owner/repo', 2)])]
        self.assertEqual(self.check(pages, '--expect', '1').returncode, 1)
        self.assertEqual(self.check(pages, '--expect', '1', '2').returncode, 0)

    def test_api_failures_and_malformed_metadata_fail_closed(self):
        self.env['GH_FAIL'] = '1'
        self.assertEqual(self.check([], '--expect-none').returncode, 2)
        del self.env['GH_FAIL']
        for page in [{}, {'errors': [{'message': 'Unavailable'}]}]:
            self.assertEqual(self.check([page], '--expect-none').returncode, 2)

    def test_head_change_during_pagination_is_rejected(self):
        pages = [self.page([], True, '1'), self.page([], head='different')]
        self.assertEqual(self.check(pages, '--expect-none').returncode, 2)

    def test_expectation_must_be_explicit(self):
        self.assertEqual(self.check([self.page([])]).returncode, 2)
        self.assertEqual(self.check([self.page([])], '--expect', '0').returncode, 2)


if __name__ == '__main__':
    unittest.main()
