#!/usr/bin/env python3
"""#520: record operator acceptance observations; never build, sign, install or publish."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile

CASES = (
    'manual-checks', 'signed-install', 'full-disk-access', 'saved-state',
    'cleanup-cancel-retry', 'maintenance', 'scan-save', 'sleeping-measurement',
    'running-measurement', 'unreachable-feed', 'invalid-signature',
    'incomplete-download', 'failed-update', 'manual-only', 'relaunch', 'updater-cache', 'distribution',
)


def digest(path):
    if not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError(f'artifact must be a regular file: {path}')
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def artifacts(file):
    entries = json.loads(file.read_text())
    if not isinstance(entries, list) or not entries:
        raise ValueError('provide a nonempty array of artifact identities, paths, SHA-256 hashes and modes')
    result = {}
    for entry in entries:
        identity, mode, expected = entry['identity'], entry['mode'], entry['sha256']
        if not isinstance(identity, str) or not identity.strip() or identity in result:
            raise ValueError('artifact identities must be nonempty and unique')
        if mode not in ('Release', 'fixture') or not re.fullmatch(r'[a-f0-9]{64}', expected):
            raise ValueError('use mode Release or fixture and a lowercase SHA-256 hash')
        path = Path(entry['path'])
        path = path if path.is_absolute() else file.resolve().parent / path
        if digest(path) != expected:
            raise ValueError(f'artifact hash mismatch: {identity}')
        result[identity] = dict(path=str(path.absolute()), sha256=expected, mode=mode)
    return result


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(value, stream, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def load(path, source):
    run = json.loads(path.read_text())
    if run['sourceCommit'] != source:
        raise ValueError('source changed; start a new run')
    for identity, entry in run['artifacts'].items():
        if digest(Path(entry['path'])) != entry['sha256']:
            raise ValueError(f'artifact changed: {identity}; start a new run')
    return run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='operation', required=True)
    for name in ('init', 'status', 'record'):
        p = sub.add_parser(name)
        p.add_argument('--run', required=True, help='name under .build/updater-acceptance/')
        if name == 'init':
            p.add_argument('--artifacts', required=True, type=Path, help='operator-supplied JSON array')
        if name == 'record':
            p.add_argument('--case', required=True, choices=CASES)
            p.add_argument('--result', required=True, choices=('pass', 'fail'))
            p.add_argument('--artifact', required=True, action='append', help='artifact identity; repeat for A and B')
            p.add_argument('--note', required=True, help='explicit operator observation, without secrets')
    args = parser.parse_args()
    try:
        repo = Path(subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip())
        source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}', args.run):
            raise ValueError('run name must contain only letters, digits, underscores or hyphens')
        path = repo / '.build/updater-acceptance' / args.run / 'run.json'
        if args.operation == 'init':
            if path.exists():
                raise ValueError('run already exists; resume with status')
            run = dict(schema=1, sourceCommit=source, artifacts=artifacts(args.artifacts),
                       cases={name: dict(result='pending') for name in CASES})
        else:
            run = load(path, source)
            if args.operation == 'record':
                if not args.note.strip() or any(name not in run['artifacts'] for name in args.artifact):
                    raise ValueError('provide an observation and identities from this run')
                run['cases'][args.case] = dict(result=args.result, artifacts=args.artifact, note=args.note.strip(),
                                              recordedAt=datetime.now(timezone.utc).isoformat())
        if args.operation != 'status':
            save(path, run)
            print(f'Saved {path}')
            return
        print(f'Source {run["sourceCommit"]}; observations are operator assertions')
        unfinished = []
        for name, entry in run['cases'].items():
            labels = ', '.join(f'{identity} [{run["artifacts"][identity]["mode"]}]' for identity in entry.get('artifacts', []))
            print(f'{entry["result"]} {name}' + (f': {labels} — {entry["note"]}' if labels else ''))
            if entry['result'] != 'pass':
                unfinished.append(name)
        print('NEXT ' + unfinished[0] if unfinished else 'COMPLETE: all required observations passed')
        raise SystemExit(1 if unfinished else 0)
    except (ValueError, TypeError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(2, f'updater-acceptance: {error}\n')


if __name__ == '__main__':
    main()
