#!/bin/bash
# Fails when a string users see uses a term GLOSSARY.md keeps off screen (Decision 92).
#
# The terms are read from GLOSSARY.md's "Not shown to users" line, so the glossary stays the one list. A literal counts
# as copy when it holds a space or is one capitalized word; identifiers ("leftovers", "local-records") and environment
# names don't. "available" is checked only as a word for free space ("available space"). It reads the app and CacheDropCore;
# the Design gallery and the journal's SQL files are skipped.
# Strings that already break a term and wait on their ticket are listed in scripts/check-copy-allow.txt as
# `term<TAB>literal`; remove a line when its string is fixed.
#
#   scripts/check-copy.sh        exit 0 when clean; otherwise prints file:line: [term] literal for each finding
set -uo pipefail
cd "$(dirname "$0")/.."
python3 - "$@" <<'PY'
import re, subprocess, sys
line = re.search(r'## Not shown to users\n\n(.+)\n', open('GLOSSARY.md').read())
if not line: sys.exit("GLOSSARY.md has no \"Not shown to users\" line")
terms = [re.sub(r'\s*\(.*\)', '', t).strip().rstrip('.') for t in line.group(1).split(',')]
patterns = {t: re.compile(r'(?<![A-Za-z])' + (r'available space' if t == 'available' else re.escape(t)) + r'(?![A-Za-z])', re.I) for t in terms}
mechanics = {"straight apostrophe": re.compile(r"[A-Za-z]'[A-Za-z]"), "→ in a menu path": re.compile('→'), "backticks": re.compile('`')}
allowed = set()
for entry in open('scripts/check-copy-allow.txt', encoding='utf-8'):
    if entry.strip() and not entry.startswith('#'): allowed.add(tuple(entry.rstrip('\n').split('\t', 1)))
literal = re.compile(r'"((?:[^"\\]|\\.)*)"')
found = False
seen = set()
for path in subprocess.check_output(['git', 'ls-files', 'CacheDrop/App/*.swift', 'Packages/CacheDropCore/Sources/*.swift']).decode().split():
    # The Design gallery is synthetic; the journal's files hold SQL, not copy; SmartCleanReport is a developer's text report.
    if path.endswith(('DesignGallery.swift', 'SQLiteCleanupJournal.swift', 'LegacyStillMigration.swift', 'SmartCleanReport.swift')): continue
    for number, text in enumerate(open(path, encoding='utf-8'), 1):
        if text.lstrip().startswith('//'): continue
        for value in literal.findall(text):
            if ' ' not in value and not re.fullmatch(r'[A-Z][a-z]+', value): continue
            # Mechanics (#571): curly apostrophes, "›" between menu items, no code in backticks.
            for term, pattern in mechanics.items():
                if pattern.search(value):
                    if (term, value) in allowed: seen.add((term, value))
                    else: print(f'{path}:{number}: [{term}] {value}'); found = True
            for term, pattern in patterns.items():
                if not pattern.search(value): continue
                if (term, value) in allowed: seen.add((term, value))
                else: print(f'{path}:{number}: [{term}] {value}'); found = True
for term, value in sorted(allowed - seen):
    print(f'scripts/check-copy-allow.txt: [{term}] {value} no longer appears: remove its line'); found = True
if found: print('These terms stay off screen (GLOSSARY.md, Decision 92): use the glossary name instead.', file=sys.stderr)
sys.exit(1 if found else 0)
PY
