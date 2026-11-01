import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/issues.py'

# Stand-in gh: answers `issue list` and GraphQL from GH_ISSUES, records PATCH payloads in GH_PATCHES.
GH = r'''import json, os, re, sys
issues = json.load(open(os.environ['GH_ISSUES']))
args = sys.argv[1:]
if args[:2] == ['issue', 'list']:
    milestone = args[args.index('--milestone') + 1]
    print(json.dumps([{'number': i['number']} for i in issues.values() if (i.get('milestone') or {}).get('title') == milestone]))
    sys.exit()
if args[:2] == ['api', 'graphql']:
    query = next(a for a in args if a.startswith('query='))
    data = {}
    for alias, number in re.findall(r'(i\d+): issueOrPullRequest\(number: (\d+)\)', query):
        data[alias] = issues.get(number)
    print(json.dumps({'data': {'repository': data}}))
    sys.exit()
if args[:3] == ['api', '-X', 'PATCH']:
    number = args[3].rsplit('/', 1)[1]
    payload = json.load(sys.stdin)
    with open(os.environ['GH_PATCHES'], 'a') as log:
        log.write(json.dumps({'number': int(number), **payload}) + '\n')
    print('{}')
    sys.exit()
print('unexpected gh call: ' + ' '.join(args), file=sys.stderr)
sys.exit(1)
'''


def ref(number, state='OPEN', repo='owner/repo'):
    return {'number': number, 'state': state, 'repository': {'nameWithOwner': repo}}


def issue(number, title='Ticket', body='', labels=(), parent=None, blocked_by=(), milestone=None, state='OPEN'):
    return {'__typename': 'Issue', 'number': number, 'title': title, 'state': state, 'body': body,
            'milestone': {'title': milestone} if milestone else None,
            'labels': {'nodes': [{'name': name} for name in labels]},
            'parent': parent, 'blockedBy': {'nodes': list(blocked_by)}, 'subIssues': {'nodes': []}}


class IssuesTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name)
        bin_dir = self.home / 'bin'
        bin_dir.mkdir()
        gh = bin_dir / 'gh'
        gh.write_text('#!' + sys.executable + '\n' + GH)
        gh.chmod(0o755)
        self.issues_file = self.home / 'issues.json'
        self.patches = self.home / 'patches.jsonl'
        self.decisions = self.home / 'RESET.md'
        self.decisions.write_text('# Plan\n\n1. **Not a decision:** a phase step.\n\n## Decisions\n\n'
                                  '4. User-owned scope only.\n68. **Empty from the Trash** what CacheDrop moved.\n')
        self.site = self.home / 'site'
        (self.site / 'docs').mkdir(parents=True)
        (self.site / 'docs/DECISIONS.md').write_text('# Decisions\n\n13. **Supabase.** Two projects.\n'
                                                     '35. **Launch without Pro plans.** The platform claim follows the build.\n')
        self.env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'],
                        GH_ISSUES=str(self.issues_file), GH_PATCHES=str(self.patches),
                        ISSUES_REPO='owner/repo', ISSUES_DECISIONS=str(self.decisions), CACHEDROP_SITE=str(self.site))

    def given(self, *issues):
        self.issues_file.write_text(json.dumps({str(i['number']): i for i in issues}))

    def run_issues(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *args], env=self.env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def patched(self):
        return [json.loads(line) for line in self.patches.read_text().splitlines()] if self.patches.exists() else []

    # check

    def test_clean_batch_passes(self):
        self.given(issue(1, body='## Parent\n\n#2\n\nIn line with Decision 4.', parent=ref(2), labels=['ready-for-agent']),
                   issue(2))
        result = self.run_issues('check', '1-2')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('ok', result.stdout)

    def test_blockers_are_independent_of_triage_labels(self):
        self.given(issue(1, labels=['ready-for-agent'], blocked_by=[ref(2)]))
        self.assertEqual(self.run_issues('check', '1').returncode, 0)

    def test_conflicting_triage_labels_are_flagged(self):
        self.given(issue(1, labels=['ready-for-agent', 'ready-for-human']),
                   issue(2, labels=['ready-for-agent', 'needs-grilling']))
        result = self.run_issues('check', '1', '2')
        self.assertEqual(result.returncode, 1)
        self.assertIn('#1: labels ready-for-agent and ready-for-human', result.stdout)
        self.assertIn('#2: labels ready-for-agent and needs-grilling', result.stdout)

    def test_malformed_reference_is_flagged_but_headings_are_not(self):
        self.given(issue(1, body='## Parent\n\n##590\n', parent=ref(590)))
        result = self.run_issues('check', '1')
        self.assertEqual(result.returncode, 1)
        self.assertIn('malformed reference ##590', result.stdout)

    def test_parent_section_must_match_the_native_parent(self):
        self.given(issue(1, body='## Parent\n\n#591\n', parent=ref(590)),
                   issue(2, body='## Parent\n\nowner/other#7\n', parent=ref(7, repo='owner/other')),
                   issue(3, body='## Parent\n\n#5\n'))
        result = self.run_issues('check', '1-3')
        self.assertIn('#1: Parent section names #591 but the native parent is #590', result.stdout)
        self.assertNotIn('#2:', result.stdout)
        self.assertIn('#3: Parent section names #5 but there is no native parent', result.stdout)

    def test_cited_decisions_must_exist_in_the_right_repository(self):
        self.given(issue(1, body='Amends Decision 68, in line with Decisions 4 and 99. Not phase step 1.'),
                   issue(2, body='See cachedrop-website Decision 35 and site Decision 13; website Decision 40 is gone.'),
                   issue(3, body='Revisit Decision 1 here.'))
        result = self.run_issues('check', '1-3')
        self.assertEqual(result.returncode, 1)
        self.assertIn('#1: cites Decision 99, which docs/RESET.md does not have', result.stdout)
        self.assertNotIn('Decision 68,', result.stdout)
        self.assertIn('#2: cites cachedrop-website Decision 40', result.stdout)
        self.assertNotIn('Decision 35', result.stdout)
        self.assertIn('#3: cites Decision 1', result.stdout)  # numbered lists before ## Decisions don't count

    def test_site_tickets_cite_site_decisions_unless_they_name_mac_cleaner(self):
        self.env['ISSUES_REPO'] = 'owner/cachedrop-website'
        self.given(issue(1, body='Per Decision 13 and mac-cleaner Decision 68; Decision 4 is not a site one; mac-cleaner Decision 5 is gone.'))
        result = self.run_issues('check', '1')
        self.assertIn('#1: cites Decision 4, which docs/DECISIONS.md does not have', result.stdout)
        self.assertIn('#1: cites mac-cleaner Decision 5', result.stdout)
        self.assertNotIn('Decision 13', result.stdout)
        self.assertNotIn('Decision 68', result.stdout)

    def test_stale_transfer_note_is_flagged(self):
        self.given(issue(1, body='Created here; transfer it there.'))
        self.assertIn('#1: still asks to be transferred', self.run_issues('check', '1').stdout)

    def test_closed_tickets_are_skipped(self):
        self.given(issue(1, body='##5', labels=['ready-for-agent'], blocked_by=[ref(2)], state='CLOSED'))
        self.assertEqual(self.run_issues('check', '1').returncode, 0)

    def test_milestone_selects_tickets(self):
        self.given(issue(1, milestone='Parity 1', body='##9'), issue(2, milestone='Other', body='##9'))
        result = self.run_issues('check', '--milestone', 'Parity 1')
        self.assertIn('#1:', result.stdout)
        self.assertNotIn('#2:', result.stdout)

    def test_missing_ticket_fails_closed(self):
        self.given(issue(1))
        result = self.run_issues('check', '1-2')
        self.assertEqual(result.returncode, 2)
        self.assertIn('#2', result.stdout)

    def test_pull_requests_in_a_range_are_skipped(self):
        self.given(issue(1), {'__typename': 'PullRequest'} | {'number': 2})
        result = self.run_issues('check', '1-2')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('ok    1 tickets', result.stdout)

    # dump

    def test_dump_shows_raw_body_and_links(self):
        self.given(issue(1, title='Spike', body='Raw Patrick-M-Bourget/x#3 text', labels=['spike'], milestone='M',
                         parent=ref(2), blocked_by=[ref(4), ref(64, repo='owner/site')]))
        result = self.run_issues('dump', '1')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('=== #1 [open] Spike', result.stdout)
        self.assertIn('milestone: M | labels: spike', result.stdout)
        self.assertIn('parent: #2 (open) | blocked by: #4 (open), owner/site#64 (open)', result.stdout)
        self.assertIn('Raw Patrick-M-Bourget/x#3 text', result.stdout)

    # edit

    def test_edit_replaces_each_text_once_and_patches(self):
        self.given(issue(1, title='Old', body='alpha beta gamma'))
        result = self.run_issues('edit', '1', '--replace', 'alpha', 'A', '--replace', 'gamma', 'G', '--title', 'New')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.patched(), [{'number': 1, 'body': 'A beta G', 'title': 'New'}])

    def test_edit_changes_nothing_when_any_text_does_not_match_once(self):
        self.given(issue(1, body='see #5 and #5'))
        for old in ('#5', 'missing'):
            result = self.run_issues('edit', '1', '--replace', 'see', 'look', '--replace', old, 'x', '--title', 'New')
            self.assertEqual(result.returncode, 1)
        self.assertEqual(self.patched(), [])

    def test_edit_hints_at_full_references(self):
        self.given(issue(1, body='decided in owner/repo#592 later'))
        result = self.run_issues('edit', '1', '--replace', 'decided in #592', 'x')
        self.assertEqual(result.returncode, 1)
        self.assertIn('owner/repo#592', result.stdout)

    # decision

    def test_decision_prints_the_whole_decision(self):
        self.assertEqual(self.run_issues('decision', '68').stdout.strip(),
                         '68. **Empty from the Trash** what CacheDrop moved.')
        self.assertIn('platform claim follows the build', self.run_issues('decision', '35', '--site').stdout)
        self.assertEqual(self.run_issues('decision', '1').returncode, 1)

    def test_decision_reads_the_real_reset(self):
        env = dict(self.env)
        del env['ISSUES_DECISIONS']
        result = subprocess.run([sys.executable, str(SCRIPT), 'decision', '4'], env=env, text=True, stdout=subprocess.PIPE)
        self.assertTrue(result.stdout.startswith('4. User-owned scope only'), result.stdout)


if __name__ == '__main__':
    unittest.main()
