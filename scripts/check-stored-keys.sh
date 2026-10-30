#!/bin/bash
# Fails when a type CacheDrop saves leaves its stored keys to the compiler (#448).
#
# A synthesized key is the property's or case's name, so a rename silently changes what is stored and older files read
# as empty. Every `Codable` or `Encodable` struct, class or enum in library sources therefore declares `CodingKeys`, and
# every `String` enum that is `Codable` gives each case an explicit raw value. `Decodable`-only types read other tools'
# output (Docker, Ollama, simctl), whose keys those tools own, and are skipped. New fields also go into the StoredKeys
# fixtures (Packages/CacheDropCore/Tests/CacheDropCoreTests/StoredKeysTests.swift).
#
#   scripts/check-stored-keys.sh        exit 0 when clean; otherwise prints file:line: type for each finding
set -uo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import re, subprocess, sys
files = subprocess.check_output(['git', 'ls-files', 'Packages/*/Sources/*.swift',]).decode().split()
declaration = re.compile(r'\b(struct|class|enum)\s+(\w+)\s*:\s*([^{]*)\{')
found = False
for path in files:
    source = open(path, encoding='utf-8').read()
    for match in declaration.finditer(source):
        kind, name, conformances = match.groups()
        listed = [c.strip() for c in conformances.split(',')]
        if not ({'Codable', 'Encodable'} & set(listed)): continue
        depth, end = 0, match.end() - 1
        for end in range(match.end() - 1, len(source)):
            depth += {'{': 1, '}': -1}.get(source[end], 0)
            if depth == 0: break
        body = source[match.end():end]
        line = source.count('\n', 0, match.start()) + 1
        if kind == 'enum' and listed and listed[0] == 'String':
            cases = re.findall(r'^\s*case\s+(.+)$|\{\s*case\s+([^}]+)', body, re.M)
            names = [part.strip() for group in cases for chunk in group if chunk for part in re.split(r'[;,]\s*(?:case\s+)?', chunk.split('//')[0]) if part.strip()]
            bare = [n for n in names if '=' not in n and re.fullmatch(r'\w+', n)]
            if bare: print(f'{path}:{line}: {name} has cases without a stored raw value: {", ".join(bare)}'); found = True
        elif 'CodingKeys' not in body:
            print(f'{path}:{line}: {name} is saved but declares no CodingKeys'); found = True
if found: print('Pin stored keys so a rename keeps them (scripts/check-stored-keys.sh, #448).', file=sys.stderr)
sys.exit(1 if found else 0)
PY
