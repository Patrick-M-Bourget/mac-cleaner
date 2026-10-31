#!/usr/bin/env python3
"""Builds a version's release notes for the signed release (Decision 122).

docs/releases/<version>.html holds only the content, in one fixed shape: a card with the eyebrow
"What’s new in <version>", one summary sentence and at most six changes. docs/releases/notes.css is the one
shared style. This joins them into the single file release.sh signs into the appcast, and refuses content
outside the shape, so the same notes can also feed an email or an in-app page later.

    scripts/release-notes.py 0.9.4 --out .build/release-notes/0.9.4.html
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALLOWED_TAGS = {'div', 'p', 'ul', 'li'}
MAX_CHANGES = 6


def check(content: str, version: str) -> None:
    tags = set(re.findall(r'</?\s*([a-zA-Z0-9]+)', content))
    if tags - ALLOWED_TAGS:
        raise ValueError(f'tags not allowed in release notes: {", ".join(sorted(tags - ALLOWED_TAGS))}')
    if re.search(r'\s(style|href|src|on[a-z]+)\s*=', content):
        raise ValueError('inline styles, links, images and scripts are not allowed in release notes')
    if not content.lstrip().startswith('<div class="cd-card">'):
        raise ValueError('release notes must be one <div class="cd-card">')
    if f'<p class="cd-eyebrow">What’s new in {version}</p>' not in content:
        raise ValueError(f'the eyebrow must read "What’s new in {version}"')
    if len(re.findall(r'<p class="cd-summary">[^<]+</p>', content)) != 1:
        raise ValueError('release notes need exactly one plain summary sentence')
    changes = re.findall(r'<li>[^<]+</li>', content)
    if not 1 <= len(changes) <= MAX_CHANGES or content.count('<li') != len(changes):
        raise ValueError(f'release notes list 1 to at most {MAX_CHANGES} plain changes')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('version')
    parser.add_argument('--source', type=Path, default=ROOT / 'docs/releases', help='folder with notes.css and <version>.html')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
        print('version must be x.y.z'); return 2
    try:
        content = (args.source / f'{args.version}.html').read_text()
        css = (args.source / 'notes.css').read_text()
        check(content, args.version)
    except (OSError, ValueError) as error:
        print(error); return 1
    if '</style' in css:
        print('notes.css must be plain CSS'); return 1
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text('<style>\n' + css + '</style>\n' + content)
    print(args.out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
