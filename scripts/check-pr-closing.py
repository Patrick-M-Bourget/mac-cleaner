#!/usr/bin/env python3
"""Check a PR's actual GitHub closing references against an explicit expected set."""
import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
QUERY = '''query($owner: String!, $name: String!, $pr: Int!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      url headRefOid
      closingIssuesReferences(first: 100, after: $cursor) {
        nodes { number repository { nameWithOwner } }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}'''


def gh(*args):
    result = subprocess.run(['gh', *args], cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        raise ValueError(result.stderr.strip() or 'GitHub command failed')
    payload = json.loads(result.stdout)
    if not isinstance(payload, dict) or payload.get('errors'):
        raise ValueError('GitHub returned invalid metadata or GraphQL errors')
    return payload


def repository(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', value):
        raise ValueError('Expected a GitHub owner/repository name')
    return value


def issue(value, default_repo):
    repo, number = value.rsplit('#', 1) if '#' in value else (default_repo, value)
    if not number.isascii() or not number.isdigit() or int(number) < 1:
        raise ValueError('Expected a positive issue number or owner/repository#number')
    return repository(repo).lower() + '#' + str(int(number))


def references(repo, number):
    owner, name = repo.split('/')
    actual, cursors = set(), set()
    cursor = head = url = None
    while True:
        args = ['api', 'graphql', '-f', 'query=' + QUERY, '-f', 'owner=' + owner,
                '-f', 'name=' + name, '-F', 'pr=' + str(number)]
        if cursor is not None:
            args += ['-f', 'cursor=' + cursor]
        pr = gh(*args)['data']['repository']['pullRequest']
        current_head = pr['headRefOid']
        if not isinstance(current_head, str) or not current_head or (head is not None and head != current_head):
            raise ValueError('PR head is missing or changed during validation; retry')
        head, url = current_head, pr['url']
        if not isinstance(url, str) or not url:
            raise ValueError('GitHub omitted the PR URL')
        links = pr['closingIssuesReferences']
        nodes, page = links['nodes'], links['pageInfo']
        if not isinstance(nodes, list) or type(page['hasNextPage']) is not bool:
            raise ValueError('GitHub omitted closing-reference metadata')
        for node in nodes:
            if type(node['number']) is not int or node['number'] < 1:
                raise ValueError('GitHub returned an invalid issue number')
            actual.add(issue(str(node['number']), repository(node['repository']['nameWithOwner'])))
        if not page['hasNextPage']:
            return actual, head, url
        cursor = page['endCursor']
        if not isinstance(cursor, str) or not cursor or cursor in cursors:
            raise ValueError('GitHub returned invalid pagination metadata')
        cursors.add(cursor)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pr', type=int, help='PR number in this checkout’s GitHub repository')
    expected = parser.add_mutually_exclusive_group(required=True)
    expected.add_argument('--expect-none', action='store_true', help='No issues should close (partial-ticket PRs)')
    expected.add_argument('--expect', nargs='+', metavar='ISSUE', help='Exact issue numbers or owner/repository#numbers')
    args = parser.parse_args()
    if args.pr < 1:
        parser.error('PR number must be positive')
    try:
        repo = repository(gh('repo', 'view', '--json', 'nameWithOwner')['nameWithOwner'])
        wanted = {issue(value, repo) for value in args.expect or []}
        actual, head, url = references(repo, args.pr)
        missing, unexpected = wanted - actual, actual - wanted
        if missing or unexpected:
            print(f'FAIL  {url} at {head}')
            if missing:
                print('missing: ' + ', '.join(sorted(missing)))
            if unexpected:
                print('unexpected: ' + ', '.join(sorted(unexpected)))
            return 1
        print(f'ok    {url} at {head}; closes: ' + (', '.join(sorted(actual)) or 'none'))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(2, f'Cannot validate PR closing references: {error}\n')


if __name__ == '__main__':
    raise SystemExit(main())
