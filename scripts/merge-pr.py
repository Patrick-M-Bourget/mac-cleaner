#!/usr/bin/env python3
"""Merge one PR the way the workflow requires, one line per step, stopping at the first failure (#669).

Run it only after the owner says "merge". UI journeys stay your call before it starts.

  scripts/merge-pr.py PR ISSUE... [--trailer "Key: value"]...
  scripts/merge-pr.py PR --expect-none [--trailer "Key: value"]...   (a PR that closes no issue, #693)

  1. finds the worktree that has the PR's branch checked out; it must be clean
  2. merges origin/main with --no-commit when the branch is behind (a conflict stops here: resolve it in that
     worktree, then run the same command again)
  3. scripts/order-decisions.py when a merge is in progress (RESET.md's union merge can leave Decisions out of order,
     #727), then scripts/check-decisions.sh, then scripts/check.sh (which records the pass stamp)
  4. commits the merge with the given trailers, and pushes
  5. waits for CI on the pushed head
  6. scripts/check-pr-closing.py PR --expect ISSUE... (or --expect-none)
  7. squash-merges, deletes the remote branch and confirms each issue closed (none with --expect-none)
"""
import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PASSING = {'SUCCESS', 'NEUTRAL', 'SKIPPED'}


class Failure(Exception):
    pass


def run(*args, cwd=None, check=True):
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if check and result.returncode:
        raise Failure((result.stderr or result.stdout).strip() or f'{" ".join(args)} failed')
    return result


def gh_json(*args, cwd=None):
    return json.loads(run('gh', *args, cwd=cwd).stdout)


def worktree_for(porcelain, branch):
    """The path of the worktree that has refs/heads/<branch> checked out, from `git worktree list --porcelain`."""
    path = None
    for line in porcelain.splitlines():
        if line.startswith('worktree '):
            path = line[len('worktree '):]
        elif line == f'branch refs/heads/{branch}':
            return path
    return None


def merging(wt):
    return run('git', 'rev-parse', '-q', '--verify', 'MERGE_HEAD', cwd=wt, check=False).returncode == 0


def order_decisions(wt):
    """Puts docs/RESET.md's Decisions back in number order after a merge and stages the file (#727)."""
    if not merging(wt):
        return 'no merge in progress'
    result = run(sys.executable, 'scripts/order-decisions.py', cwd=wt, check=False)
    if result.returncode:
        raise Failure(result.stdout + result.stderr)
    run('git', 'add', 'docs/RESET.md', cwd=wt)
    return result.stdout.strip().removeprefix('ok    ')


def ci_state(pr, head):
    """'pending', 'pass' or 'fail' for the PR's checks on `head`; checks still on an older head are pending."""
    if pr.get('headRefOid') != head:
        return 'pending'
    checks = pr.get('statusCheckRollup') or []
    if not checks:
        return 'pending'
    states = [(c.get('conclusion') or c.get('state') or '').upper() for c in checks]
    if any(c.get('status', 'COMPLETED').upper() != 'COMPLETED' for c in checks) or any(s in ('', 'PENDING', 'EXPECTED') for s in states):
        return 'pending'
    return 'pass' if all(s in PASSING for s in states) else 'fail'


def step(name, action):
    try:
        detail = action()
    except Failure as error:
        print(f'FAIL  {name}')
        for line in str(error).splitlines()[:20]:
            print('      ' + line[:300])
        sys.exit(1)
    print(f'ok    {name}' + (f': {detail}' if detail else ''), flush=True)
    return detail


def parse_args(argv=None):
    """The command line; it must name the issues the PR closes or say --expect-none, never both nor neither (#693)."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('pr', type=int)
    parser.add_argument('issues', nargs='*', help='the issues the PR must close, as check-pr-closing.py expects')
    parser.add_argument('--expect-none', action='store_true', help='the PR closes no issue (a release bump, a docs-only change)')
    parser.add_argument('--trailer', action='append', default=[], help='a trailer for the merge commit; repeatable')
    parser.add_argument('--ci-timeout', type=int, default=45 * 60, help='seconds to wait for CI (default 45 min)')
    args = parser.parse_args(argv)
    if bool(args.issues) == args.expect_none:
        parser.error('give the issues the PR closes, or --expect-none if it closes none' if not args.issues
                     else 'give either issues or --expect-none, not both')
    return args


def closing_expectation(args):
    """The expectation passed to check-pr-closing.py after the PR number."""
    return ['--expect-none'] if args.expect_none else ['--expect', *args.issues]


def main():
    args = parse_args()
    state = {}

    def find():
        pr = gh_json('pr', 'view', str(args.pr), '--json', 'headRefName,baseRefName,state', cwd=ROOT)
        if pr['state'] != 'OPEN' or pr['baseRefName'] != 'main':
            raise Failure(f'PR #{args.pr} is {pr["state"]} on {pr["baseRefName"]}; expected an open PR on main')
        path = worktree_for(run('git', 'worktree', 'list', '--porcelain', cwd=ROOT).stdout, pr['headRefName'])
        if not path:
            raise Failure(f'No worktree has {pr["headRefName"]} checked out')
        state.update(branch=pr['headRefName'], wt=path)
        dirty = [l for l in run('git', 'status', '--porcelain', cwd=path).stdout.splitlines() if not l.startswith('??')]
        if dirty and not merging(path):
            raise Failure(f'{path} has uncommitted changes:\n' + '\n'.join(dirty))
        return f'{pr["headRefName"]} in {path}'

    def merge_main():
        wt = state['wt']
        if merging(wt):
            unmerged = run('git', 'diff', '--name-only', '--diff-filter=U', cwd=wt).stdout.split()
            if unmerged:
                raise Failure('Resolve and `git add` these, then run this again:\n' + '\n'.join(unmerged))
            return 'continuing the merge in progress'
        run('git', 'fetch', '-q', 'origin', cwd=wt)
        if run('git', 'merge-base', '--is-ancestor', 'origin/main', 'HEAD', cwd=wt, check=False).returncode == 0:
            return 'already up to date'
        result = run('git', 'merge', '--no-commit', '--no-ff', 'origin/main', cwd=wt, check=False)
        unmerged = run('git', 'diff', '--name-only', '--diff-filter=U', cwd=wt).stdout.split()
        if result.returncode or unmerged:
            raise Failure('Conflicts; resolve and `git add` these in the worktree, then run this again:\n'
                          + '\n'.join(unmerged or [result.stderr.strip()]))
        return 'merged without conflicts (not committed yet)'

    def decisions():
        result = run('scripts/check-decisions.sh', cwd=state['wt'], check=False)
        if result.returncode:
            raise Failure(result.stdout + result.stderr)

    def checks():
        result = subprocess.run(['scripts/check.sh'], cwd=state['wt'], text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT)
        if result.returncode:
            raise Failure(result.stdout)

    def commit_and_push():
        wt = state['wt']
        if merging(wt):
            trailers = [a for t in args.trailer for a in ('--trailer', t)]
            run('git', 'commit', '-q', '--no-edit', *trailers, cwd=wt)
        state['head'] = run('git', 'rev-parse', 'HEAD', cwd=wt).stdout.strip()
        run('git', 'push', '-q', 'origin', 'HEAD', cwd=wt)
        return state['head'][:8]

    def wait_for_ci():
        deadline = time.monotonic() + args.ci_timeout
        while True:
            pr = gh_json('pr', 'view', str(args.pr), '--json', 'headRefOid,statusCheckRollup', cwd=ROOT)
            result = ci_state(pr, state['head'])
            if result == 'pass':
                return ', '.join(c.get('name') or c.get('context') or '?' for c in pr['statusCheckRollup'])
            if result == 'fail':
                raise Failure('\n'.join(f'{c.get("name")}: {c.get("conclusion") or c.get("state")} {c.get("detailsUrl", "")}'
                                        for c in pr['statusCheckRollup']))
            if time.monotonic() > deadline:
                raise Failure(f'CI still pending after {args.ci_timeout // 60} min')
            time.sleep(30)

    def closing():
        result = run(sys.executable, str(ROOT / 'scripts/check-pr-closing.py'), str(args.pr), *closing_expectation(args),
                     cwd=ROOT, check=False)
        if result.returncode:
            raise Failure(result.stdout + result.stderr)

    def merge():
        run('gh', 'pr', 'merge', str(args.pr), '--squash', '--match-head-commit', state['head'], cwd=ROOT)
        merged = gh_json('pr', 'view', str(args.pr), '--json', 'state,mergeCommit', cwd=ROOT)
        if merged['state'] != 'MERGED':
            raise Failure(f'PR #{args.pr} is {merged["state"]} after the merge call')
        run('git', 'push', '-q', 'origin', '--delete', state['branch'], cwd=ROOT)
        return f'{merged["mergeCommit"]["oid"][:8]}; remote branch deleted'

    def issues_closed():
        numbers = [i.rsplit('#', 1)[-1] for i in args.issues]
        for _ in range(12):  # GitHub closes linked issues a few seconds after the merge
            open_ = [n for n in numbers if gh_json('issue', 'view', n, '--json', 'state', cwd=ROOT)['state'] != 'CLOSED']
            if not open_:
                return ', '.join('#' + n for n in numbers) + ' closed'
            time.sleep(5)
        raise Failure('Still open: ' + ', '.join('#' + n for n in open_))

    step('find the worktree', find)
    step('merge origin/main', merge_main)
    step('decision order', lambda: order_decisions(state['wt']))
    step('decision numbers', decisions)
    step('check.sh', checks)
    step('commit and push', commit_and_push)
    step('CI', wait_for_ci)
    step('closing references', closing)
    step('squash-merge', merge)
    if args.issues:
        step('issues closed', issues_closed)
    print(f'Next: remove {state["wt"]} once nothing else needs it.')


if __name__ == '__main__':
    main()
