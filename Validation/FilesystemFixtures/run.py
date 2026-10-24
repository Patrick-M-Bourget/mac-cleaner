#!/usr/bin/env python3
"""Opt-in owned-image validation; refuses personal and persistent CI machines."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--ci-owned-images', action='store_true', required=True)
parser.add_argument('--executable', required=True, type=Path)
parser.add_argument('--reports', required=True, type=Path)
args = parser.parse_args()
if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted':
    parser.error('Only ephemeral GitHub-hosted CI is supported; no local image mounts')
if shutil.disk_usage(tempfile.gettempdir()).free < 512 * 1024 * 1024:
    parser.error('512 MiB fixture headroom required')
args.reports.mkdir(parents=True, exist_ok=True)
executable = args.executable.resolve(strict=True)
root = Path(tempfile.mkdtemp(prefix='StillFilesystemFixtures-')).resolve()
root.chmod(0o700)
image = root / 'owned.dmg'
mount = root / 'mount'
mount.mkdir()
device = None
attached = False
report = {'imageBytes': 64 * 1024 * 1024, 'filesystem': 'HFS+', 'source': os.environ.get('GITHUB_SHA'),
          'status': 'started', 'detached': False, 'ownedRootRemoved': False, 'ownedRoot': str(root)}


def run(argv):
    result = subprocess.run([str(x) for x in argv], check=False, capture_output=True, timeout=120)
    if result.returncode != 0:
        raise RuntimeError(f'{Path(str(argv[0])).name} failed ({result.returncode}): '
                           + result.stderr.decode(errors='replace'))
    return result.stdout


def verified_mapping():
    # Revalidate exact image/device association before detaching, never infer a disk number.
    info = plistlib.loads(run(['/usr/bin/hdiutil', 'info', '-plist']))
    matches = [entry for entry in info.get('images', [])
               if Path(entry.get('image-path', '')).resolve() == image]
    return len(matches) == 1 and any(entity.get('dev-entry') == device
        for entity in matches[0].get('system-entities', []))


def detach():
    global attached
    if not verified_mapping():
        raise RuntimeError('Owned image/device mapping changed; refusing detach and preserving fixture')
    run(['/usr/bin/hdiutil', 'detach', device])  # No force, no wildcard or other device.
    if os.path.ismount(mount):
        raise RuntimeError('Mount remains after detach; preserving fixture')
    attached = False
    report['detached'] = True


def interrupted(signum, frame):
    raise SystemExit(f'Interrupted by signal {signum}; attempting exact owned-device cleanup')


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
try:
    run(['/usr/bin/hdiutil', 'create', '-size', '64m', '-fs', 'HFS+', '-volname', 'StillOwnedFixture', '-type', 'UDIF', image])
    # Even partial/invalid attach output must prevent recursive removal across a possible mount.
    attached = True
    attachment = run(['/usr/bin/hdiutil', 'attach', '-plist', '-nobrowse', '-noautoopen', '-mountpoint', mount, image])
    (args.reports / 'attach.plist').write_bytes(attachment)
    entities = plistlib.loads(attachment).get('system-entities', [])
    mounted = [entry for entry in entities if entry.get('mount-point') and Path(entry['mount-point']).resolve() == mount]
    if len(mounted) != 1 or not re.fullmatch(r'/dev/disk\d+(?:s\d+)*', mounted[0].get('dev-entry', '')):
        raise RuntimeError('Unexpected attach identity; preserving fixture without guessing a detach target')
    device = mounted[0]['dev-entry']
    if not verified_mapping() or not os.path.ismount(mount):
        raise RuntimeError('Attach mapping/mount identity could not be verified')
    parent_dev, mounted_dev = root.stat().st_dev, mount.stat().st_dev
    if parent_dev == mounted_dev:
        raise RuntimeError('No genuine volume boundary was created')
    scope = mount / 'scope'
    scope.mkdir()
    (scope / 'sentinel.txt').write_bytes(b'owned sentinel!!!')
    source = root / 'plain.txt'
    source.write_bytes(b'A' * 1_048_576)
    run(['/usr/bin/ditto', '--hfsCompression', source, scope / 'compressed.txt'])
    run([executable, 'mounted', root, mounted_dev, parent_dev, args.reports / 'mounted.json'])
    detach()
    run([executable, 'unmounted', root, mounted_dev, parent_dev, args.reports / 'unmounted.json'])
    report['status'] = 'completed-see-native-compression-status'
except BaseException as error:
    report['status'] = 'failed'
    report['error'] = str(error)
    raise
finally:
    try:
        if attached and device is not None:
            detach()
        if not attached and not os.path.ismount(mount):
            shutil.rmtree(root)
            report['ownedRootRemoved'] = True
    except BaseException as error:
        report['status'] = 'failed-cleanup-preserving-owned-fixture'
        report['cleanupError'] = str(error)
        raise
    finally:
        # Persist failures and cleanup status even when no runtime claims can be made.
        (args.reports / 'lifecycle.json').write_text(json.dumps(report, indent=2) + '\n')
