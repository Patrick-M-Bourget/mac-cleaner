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
        for name in ['check-debug-seams.sh', 'check-decisions.sh', 'check-copy.sh', 'check-stored-keys.sh', 'check-release.sh',
                     'check-stamp.sh']:
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
        self.assertEqual(calls[-1], 'check-stamp.sh write', 'a full pass records the pass stamp last (#667)')
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
        self.assertFalse(any(c.startswith(('xcodebuild ', 'check-release.sh ', 'check-stamp.sh ')) for c in calls))
        self.assertTrue(any('Packages/StorageAlerts' in c for c in calls))

    def test_source_failure_also_prevents_app_builds(self):
        self.env['FAIL_PATTERN'] = r'^check-copy.sh '
        result, calls = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c.startswith(('xcodebuild ', 'check-release.sh ', 'check-stamp.sh ')) for c in calls))

    def test_failed_debug_build_prevents_release(self):
        self.env['FAIL_PATTERN'] = r'^xcodebuild '
        result, calls = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c.startswith('check-release.sh ') for c in calls))

    def test_fast_still_stops_after_normal_core(self):
        result, calls = self.check('--fast')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(any('[strict]' in c or 'StorageAlerts' in c or c.startswith(('xcodebuild ', 'check-release.sh ', 'check-stamp.sh ')) for c in calls))


class DecisionsCheckTests(CommandTests):
    """scripts/check-decisions.sh: numbering, and append-only against origin/main (#668)."""

    def setUp(self):
        super().setUp()
        self.repo = self.home / 'repo'
        (self.repo / 'scripts').mkdir(parents=True)
        (self.repo / 'docs').mkdir()
        for name in ('check-decisions.sh', 'order-decisions.py'):  # the check reads Decisions with the ordering script's parser
            shutil.copy2(ROOT / 'scripts' / name, self.repo / 'scripts' / name)
        for args in (['init', '-q', '-b', 'main'], ['config', 'user.email', 't@example.com'], ['config', 'user.name', 'T']):
            self.git(*args)
        self.reset('1. **One.** First.\n2. **Two.** Second:\n    - a point.\n')
        self.git('add', '.')
        self.git('commit', '-q', '-m', 'start')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')

    def git(self, *args):
        subprocess.run(['git', *args], cwd=self.repo, check=True, capture_output=True)

    def reset(self, decisions):
        (self.repo / 'docs/RESET.md').write_text('# Plan\n\n## Decisions\nIntro.\n\n' + decisions)

    def check(self):
        return self.run_command(['/bin/bash', str(self.repo / 'scripts/check-decisions.sh')])

    def test_appending_passes_and_editing_an_existing_decision_fails(self):
        self.reset('1. **One.** First.\n2. **Two.** Second:\n    - a point.\n3. **Three (amends 2).** Third.\n')
        self.assertEqual(self.check().returncode, 0)
        self.reset('1. **One.** First.\n2. **Two.** Second:\n    - a changed point.\n3. **Three.** Third.\n')
        result = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertIn('Decision 2 was edited', result.stdout)

    def test_a_branch_behind_main_keeps_its_older_copy(self):
        self.git('checkout', '-q', '-b', 'branch')
        self.git('checkout', '-q', 'main')
        self.reset('1. **One.** First.\n2. **Two.** Second:\n    - a point.\n3. **Three.** Third.\n')
        self.git('commit', '-q', '-am', 'main appends')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')
        self.git('checkout', '-q', 'branch')
        self.assertEqual(self.check().returncode, 0)

    def test_order_still_checked_and_append_only_skipped_without_origin_main(self):
        self.git('update-ref', '-d', 'refs/remotes/origin/main')
        self.reset('1. **One.** Edited.\n3. **Three.** Third.\n2. **Two.** Second.\n')
        result = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertIn('Decision 2 follows 3', result.stdout)
        self.assertIn('scripts/order-decisions.py', result.stdout, 'the fix for a union merge is named (#727)')
        self.assertNotIn('was edited', result.stdout)


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

    def test_head_or_body_change_during_pagination_is_rejected(self):
        pages = [self.page([], True, '1'), self.page([], head='different')]
        self.assertEqual(self.check(pages, '--expect-none').returncode, 2)
        pages = [self.page([], True, '1'), self.page([])]
        pages[1]['data']['repository']['pullRequest']['body'] = 'Edited during validation'
        self.assertEqual(self.check(pages, '--expect-none').returncode, 2)

    def test_expectation_must_be_explicit(self):
        self.assertEqual(self.check([self.page([])]).returncode, 2)
        self.assertEqual(self.check([self.page([])], '--expect', '0').returncode, 2)


if __name__ == '__main__':
    unittest.main()


class UIJourneysTests(CommandTests):
    """scripts/ui-journeys.sh names the journeys that never reported and reruns them once (#724). xcodebuild is a stub
    that replays canned logs, one per test run."""

    def setUp(self):
        super().setUp()
        self.repo = self.home / 'repo'
        (self.repo / 'scripts').mkdir(parents=True)
        shutil.copy2(ROOT / 'scripts/ui-journeys.sh', self.repo / 'scripts/ui-journeys.sh')
        tests = self.repo / 'CacheDrop/UITests'
        tests.mkdir(parents=True)
        (tests / 'AUITests.swift').write_text('''import XCTest
final class AUITests: XCTestCase {
    private final class Observer: NSObject, XCTestObservation {
        func testCaseDidFinish(_ testCase: XCTestCase) {}
    }
    @MainActor func testOne() throws {}
    func testTwo() {}
}
final class BUITests: XCTestCase {
    @MainActor func testThree() throws {}
}
extension AUITests {
    @MainActor func testFour() throws {}
}
''')
        self.calls = self.home / 'calls'
        self.runs = self.home / 'runs'
        self.runs.mkdir()
        self.env.update(CALLS=str(self.calls), RUNS=str(self.runs), TMPDIR=str(self.home))
        self.executable(self.bin / 'xcodebuild', '''import os, sys
from pathlib import Path
calls = Path(os.environ['CALLS'])
with open(calls, 'a') as f: f.write(' '.join(sys.argv[1:]) + '\\n')
if sys.argv[1] != 'test-without-building': sys.exit(0)
run = sum(1 for line in calls.read_text().splitlines() if line.startswith('test-without-building'))
log = Path(os.environ['RUNS']) / str(run)
lines = log.read_text().splitlines() if log.exists() else []
code = 0
for line in lines:
    if line.startswith('EXIT '): code = int(line.split()[1])
    else: print(line)
sys.exit(code)
''')
        self.executable(self.bin / 'pkill', 'import sys; sys.exit(1)')  # never stop the owner's real processes

    def run_log(self, number, *results, exit_code=0):
        lines = ["Test Suite 'Selected tests' started at 2026-11-04 10:00:00.000"]
        for result in results:
            test, outcome = result.split()
            cls, name = test.split('/')
            lines.append(f"Test Case '-[CacheDropUITests.{cls} {name}]' started.")
            if outcome == 'restart':
                lines.append(f'Restarting after unexpected exit, crash, or test timeout in {cls}.{name}(); summary will include totals from previous launches.')
            elif outcome != 'none':
                lines.append(f"Test Case '-[CacheDropUITests.{cls} {name}]' {outcome} (1.234 seconds).")
        lines.append(f'EXIT {exit_code}')
        (self.runs / str(number)).write_text('\n'.join(lines) + '\n')

    def journeys(self, *args):
        result = self.run_command(['/bin/bash', str(self.repo / 'scripts/ui-journeys.sh'), '--no-build', *args])
        runs = [c for c in self.calls.read_text().splitlines() if c.startswith('test-without-building')]
        return result, runs

    def test_all_reported_runs_once_and_prints_one_line_per_test(self):
        self.run_log(1, 'AUITests/testOne passed', 'AUITests/testFour skipped')
        result, runs = self.journeys('testOne', 'testFour')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(len(runs), 1)
        self.assertIn('-only-testing:CacheDropUITests/AUITests/testFour', runs[0], 'a test in an extension resolves to its class')
        self.assertIn('AUITests/testOne passed (1.234 seconds).', result.stdout)
        self.assertIn('AUITests/testFour skipped (1.234 seconds).', result.stdout)
        self.assertNotIn('No result', result.stdout)
        self.assertTrue(result.stdout.splitlines()[-1].startswith('xcodebuild exit 0; full log: '), result.stdout)

    def test_one_missing_is_named_and_rerun_once_and_still_missing_fails(self):
        self.run_log(1, 'AUITests/testOne passed', 'BUITests/testThree restart', exit_code=65)
        self.run_log(2, 'BUITests/testThree none', exit_code=65)
        result, runs = self.journeys('testOne', 'testThree')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('Restarting after unexpected exit, crash, or test timeout in BUITests.testThree()', result.stdout)
        self.assertIn('No result: BUITests/testThree', result.stdout)
        self.assertEqual(len(runs), 2, 'reruns once, not again')
        self.assertIn('-only-testing:CacheDropUITests/BUITests/testThree', runs[1])
        self.assertNotIn('testOne', runs[1])
        last = result.stdout.splitlines()[-1]
        self.assertIn('still no result: BUITests/testThree', last)

    def test_one_missing_then_rerun_passing_succeeds(self):
        self.run_log(1, 'AUITests/testOne passed', 'BUITests/testThree none', exit_code=65)
        self.run_log(2, 'BUITests/testThree passed')
        result, runs = self.journeys('testOne', 'testThree')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(len(runs), 2)
        self.assertIn('BUITests/testThree passed (1.234 seconds).', result.stdout)
        self.assertIn('rerun', result.stdout.splitlines()[-1])

    def test_a_failure_in_the_first_run_still_fails_after_a_passing_rerun(self):
        self.run_log(1, 'AUITests/testOne failed', 'BUITests/testThree none', exit_code=65)
        self.run_log(2, 'BUITests/testThree passed')
        result, runs = self.journeys('testOne', 'testThree')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(len(runs), 2)

    def test_all_requests_every_test_in_classes_and_extensions(self):
        self.run_log(1, 'AUITests/testOne passed', 'AUITests/testTwo passed', 'BUITests/testThree passed', exit_code=65)
        self.run_log(2, 'AUITests/testFour passed')
        result, runs = self.journeys('--all')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn('-only-testing', runs[0], '--all runs the whole suite')
        self.assertIn('No result: AUITests/testFour', result.stdout)
        self.assertNotIn('testCaseDidFinish', result.stdout)
        self.assertEqual(runs[1].count('-only-testing'), 1)
        self.assertIn('-only-testing:CacheDropUITests/AUITests/testFour', runs[1])
