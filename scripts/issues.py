#!/usr/bin/env python3
"""Read, check and edit a batch of GitHub tickets, and look up Decisions.

  scripts/issues.py dump 590-645 [601 ...] | --milestone TITLE    raw bodies with labels, parent and blockers
  scripts/issues.py check 590-645 | --milestone TITLE             mechanical ticket problems, one line each
  scripts/issues.py edit N --replace OLD NEW [...] [--title T]    all-or-nothing body edit
  scripts/issues.py decision N [--site]                           print one whole Decision

`--repo owner/name` picks another repository (default: this checkout's, or $ISSUES_REPO). Exit 0 means clean or done,
1 means problems found or an edit that didn't match, 2 means GitHub or the input failed.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
FIELDS = '''number title state body milestone { title } labels(first: 50) { nodes { name } }
  parent { number state repository { nameWithOwner } }
  blockedBy(first: 50) { nodes { number state repository { nameWithOwner } } }
  subIssues(first: 100) { nodes { number state repository { nameWithOwner } } }'''
CHUNK = 40
REF = r'(?:([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+))?#(\d+)'
DECISION_CITE = re.compile(r'(?:\b(cachedrop-website|site|website|mac-cleaner)\s+)?\bDecisions?\s+(\d+(?:(?:,\s*|,?\s+and\s+)\d+)*)')


class Failure(Exception):
    pass


def gh(*args, stdin=None):
    result = subprocess.run(['gh', *args], cwd=ROOT, input=stdin, capture_output=True, text=True)
    if result.returncode:
        raise Failure(result.stderr.strip() or 'gh failed: ' + ' '.join(args[:3]))
    return json.loads(result.stdout or 'null')


def default_repo():
    if os.environ.get('ISSUES_REPO'):
        return os.environ['ISSUES_REPO']
    return gh('repo', 'view', '--json', 'nameWithOwner')['nameWithOwner']


def numbers(specs):
    found = []
    for spec in specs:
        match = re.fullmatch(r'(\d+)(?:-(\d+))?', spec)
        if not match:
            raise Failure(f'expected an issue number or range, got {spec!r}')
        first, last = int(match[1]), int(match[2] or match[1])
        found += range(first, last + 1)
    return sorted(set(found))


def select(args, repo):
    if args.milestone:
        listed = gh('issue', 'list', '-R', repo, '--milestone', args.milestone, '--state', 'all', '--limit', '1000',
                    '--json', 'number')
        return sorted(item['number'] for item in listed)
    if not args.issues:
        raise Failure('name issues or ranges, or --milestone')
    return numbers(args.issues)


def fetch(repo, wanted):
    owner, name = repo.split('/')
    issues = {}
    for start in range(0, len(wanted), CHUNK):
        chunk = wanted[start:start + CHUNK]
        aliases = '\n'.join(f'i{n}: issueOrPullRequest(number: {n}) {{ __typename ... on Issue {{ {FIELDS} }} }}' for n in chunk)
        query = f'query {{ repository(owner: "{owner}", name: "{name}") {{\n{aliases}\n}} }}'
        payload = gh('api', 'graphql', '-f', 'query=' + query)
        if not isinstance(payload, dict) or payload.get('errors') and not payload.get('data'):
            raise Failure('GitHub returned GraphQL errors')
        data = payload['data']['repository']
        for n in chunk:
            node = data.get(f'i{n}')
            if not node:
                raise Failure(f'#{n} not found in {repo} (moved or deleted?)')
            if node['__typename'] == 'Issue':
                issues[n] = node
    return issues


def label(node, repo):
    other = node['repository']['nameWithOwner']
    return ('' if other.lower() == repo.lower() else other) + f"#{node['number']}"


def labels(issue):
    return [node['name'] for node in issue['labels']['nodes']]


# Decisions

def decisions_text(site):
    if site:
        path = Path(os.environ.get('CACHEDROP_SITE', ROOT.parent / 'cachedrop-website')) / 'docs/DECISIONS.md'
        return path, (path.read_text() if path.exists() else None)
    path = Path(os.environ.get('ISSUES_DECISIONS', ROOT / 'docs/RESET.md'))
    text = path.read_text()
    marker = re.search(r'^## Decisions', text, re.M)
    return path, text[marker.start():] if marker else ''


def decisions(site):
    path, text = decisions_text(site)
    if text is None:
        return path, None
    return path, {int(m[1]): m[0] for m in re.finditer(r'^(\d+)\. .*$', text, re.M)}


# check

def problems(issue, repo, own, site):
    if issue['state'] != 'OPEN':
        return []
    body, names, found = issue['body'] or '', labels(issue), []
    # Blockers are independent of triage labels (docs/agents/triage-labels.md), so only label pairs are checked.
    if 'ready-for-agent' in names:
        for other in ('ready-for-human', 'needs-grilling'):
            if other in names:
                found.append(f'labels ready-for-agent and {other}')
    for match in re.finditer(r'(?<![#\w])##(\d+)', body):
        found.append(f'malformed reference ##{match[1]}')
    section = re.search(r'^## Parent\s*\n(.*?)(?=^## |\Z)', body, re.M | re.S)
    if section:
        named = re.search(REF, section[1])
        if named:
            named_label = ('' if not named[1] or named[1].lower() == repo.lower() else named[1]) + f'#{named[2]}'
            native = issue['parent']
            if not native:
                found.append(f'Parent section names {named_label} but there is no native parent')
            elif label(native, repo) != named_label:
                found.append(f'Parent section names {named_label} but the native parent is {label(native, repo)}')
    for match in DECISION_CITE.finditer(body):
        on_site_repo = repo.lower().endswith('/cachedrop-website')
        is_site = match[1] != 'mac-cleaner' and (bool(match[1]) or on_site_repo)
        path, known = site if is_site else own
        if known is None:
            continue
        for number in map(int, re.findall(r'\d+', match[2])):
            if number not in known:
                where = 'cachedrop-website ' if is_site and not on_site_repo else 'mac-cleaner ' if not is_site and on_site_repo else ''
                found.append(f'cites {where}Decision {number}, which {path.relative_to(path.parents[1]) if is_site else "docs/RESET.md"} does not have')
    if re.search(r'transfer it there', body, re.I):
        found.append('still asks to be transferred')
    return found


def check(args, repo):
    issues = fetch(repo, select(args, repo))
    own, site = decisions(False), decisions(True)
    lines = [f'#{n}: {p}' for n, issue in issues.items() for p in problems(issue, repo, own, site)]
    print('\n'.join(lines) if lines else f'ok    {len(issues)} tickets')
    if site[1] is None:
        print(f'note  {site[0]} not found; site Decision citations not checked')
    return 1 if lines else 0


# dump

def dump(args, repo):
    for n, issue in fetch(repo, select(args, repo)).items():
        links = []
        if issue['parent']:
            links.append(f"parent: {label(issue['parent'], repo)} ({issue['parent']['state'].lower()})")
        for key, name in (('blockedBy', 'blocked by'), ('subIssues', 'sub-issues')):
            nodes = issue[key]['nodes']
            if nodes:
                links.append(f'{name}: ' + ', '.join(f"{label(x, repo)} ({x['state'].lower()})" for x in nodes))
        milestone = (issue['milestone'] or {}).get('title', '-')
        print(f"=== #{n} [{issue['state'].lower()}] {issue['title']}")
        print(f"milestone: {milestone} | labels: {', '.join(labels(issue)) or '-'}")
        print(' | '.join(links) or 'no links')
        print((issue['body'] or '').rstrip() + '\n')
    return 0


# edit

def edit(args, repo):
    if not args.replace and args.title is None:
        raise Failure('nothing to change: give --replace or --title')
    body = fetch(repo, [args.number])[args.number]['body'] or ''
    misses = []
    for old, new in args.replace or []:
        count = body.count(old)
        if count != 1:
            hint = ''
            if count == 0:
                expanded = re.sub(r'(?<![\w/])#(\d+)', lambda m: f'{repo}#{m[1]}', old)
                if expanded != old and body.count(expanded) == 1:
                    hint = f' (the body spells it {expanded!r})'
            misses.append(f'{old[:70]!r} matches {count} times{hint}')
            continue
        body = body.replace(old, new)
    if misses:
        print(f'#{args.number} unchanged:\n  ' + '\n  '.join(misses))
        return 1
    payload = {'body': body} if args.replace else {}
    if args.title is not None:
        payload['title'] = args.title
    gh('api', '-X', 'PATCH', f'repos/{repo}/issues/{args.number}', '--input', '-', stdin=json.dumps(payload))
    print(f'ok    #{args.number} edited')
    return 0


def decision(args, _repo=None):
    path, known = decisions(args.site)
    if known is None:
        raise Failure(f'{path} not found')
    if args.number not in known:
        print(f'Decision {args.number} is not in {path}')
        return 1
    print(known[args.number])
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('dump', 'check'):
        command = commands.add_parser(name)
        command.add_argument('issues', nargs='*', help='issue numbers or ranges like 590-645')
        command.add_argument('--milestone')
        command.add_argument('--repo')
    command = commands.add_parser('edit')
    command.add_argument('number', type=int)
    command.add_argument('--replace', nargs=2, action='append', metavar=('OLD', 'NEW'))
    command.add_argument('--title')
    command.add_argument('--repo')
    command = commands.add_parser('decision')
    command.add_argument('number', type=int)
    command.add_argument('--site', action='store_true', help="the website's docs/DECISIONS.md")
    args = parser.parse_args()
    try:
        if args.command == 'decision':
            return decision(args)
        repo = args.repo or default_repo()
        return {'dump': dump, 'check': check, 'edit': edit}[args.command](args, repo)
    except (Failure, OSError, KeyError, TypeError, ValueError) as error:
        print(f'issues.py {args.command}: {error}')
        return 2


if __name__ == '__main__':
    sys.exit(main())
