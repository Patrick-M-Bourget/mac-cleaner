#!/usr/bin/env python3
"""Hosted-only native mapping observation; never removes generated artifacts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import sys
import tempfile
import time

from run import PROJECT, SCHEME


def identity(path):
    item = path.lstat()
    if stat.S_ISLNK(item.st_mode) or item.st_uid != os.getuid():
        raise RuntimeError('Unknown ownership or symbolic link')
    if item.st_flags & 0x40000000:
        raise RuntimeError('Dataless fixture unsupported')
    return dict(device=item.st_dev, inode=item.st_ino, owner=item.st_uid,
                mode=item.st_mode, size=item.st_size)


def command(args, output, timeout=60):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=timeout, check=False)
    output.write_bytes(result.stdout)
    if result.returncode:
        raise RuntimeError('Native command failed; original output retained')
    return result.stdout.decode('utf-8')


def descendants(parent):
    # Inventory occurs only after strict hosted guard. Retain exact child lineage only.
    data = subprocess.check_output(['/bin/ps', '-axo', 'pid=,ppid=,comm='], timeout=5).decode()
    rows = []
    for line in data.splitlines():
        fields = line.strip().split(None, 2)
        if len(fields) == 3:
            rows.append((int(fields[0]), int(fields[1]), fields[2]))
    owned = {parent}
    while True:
        found = owned | {pid for pid, ppid, _ in rows if ppid in owned}
        if found == owned:
            break
        owned = found
    return [dict(pid=pid, parent=ppid, executableBasename=Path(name).name)
            for pid, ppid, name in rows if pid in owned]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    report = dict(schema=1, experiment='hosted-standard-deriveddata-mapping',
                  productionMutationQualified=False, cleanupExercised=False,
                  noOwnerTermination=True, standardRootInitiallyAbsent=False)
    output = None
    try:
        if (sys.platform != 'darwin' or os.environ.get('GITHUB_ACTIONS') != 'true'
                or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted'
                or not os.environ.get('GITHUB_RUN_ID') or not os.environ.get('RUNNER_TEMP')):
            raise RuntimeError('Fresh GitHub-hosted macOS runner required')
        runner = Path(os.environ['RUNNER_TEMP']).resolve(strict=True)
        output = Path(args.output).absolute()
        if output.parent.resolve(strict=True) != runner or output.exists():
            raise RuntimeError('New direct RUNNER_TEMP evidence directory required')
        output.mkdir(mode=0o700)
        home = Path.home()
        standard = home / 'Library/Developer/Xcode/DerivedData'
        # No personal/preexisting root traversal, even on an unexpectedly reused runner.
        if os.path.lexists(standard):
            raise RuntimeError('Standard DerivedData preexists; refusing inspection')
        report['standardRootInitiallyAbsent'] = True
        ancestor = standard.parent
        while not ancestor.exists():
            ancestor = ancestor.parent
        cursor = ancestor
        while cursor != home.parent:
            identity(cursor)
            cursor = cursor.parent
        # Custom Xcode preferences make a default-location experiment ambiguous.
        for candidate in [home / 'Library/Preferences/com.apple.dt.Xcode.plist',
                          home / 'Library/Managed Preferences/com.apple.dt.Xcode.plist',
                          Path('/Library/Managed Preferences/com.apple.dt.Xcode.plist')]:
            if os.path.lexists(candidate):
                raise RuntimeError('Preexisting Xcode preferences; fresh default configuration required')
        report.update(source=os.environ.get('GITHUB_SHA'), runID=os.environ['GITHUB_RUN_ID'],
                      os=command(['/usr/bin/sw_vers'], output / 'os.txt'),
                      architecture=os.uname().machine,
                      toolchain=command(['/usr/bin/xcodebuild', '-version'], output / 'toolchain.txt'))
        root = Path(tempfile.mkdtemp(prefix='StillXcodeStandard-', dir=runner)).resolve()
        root.chmod(0o700)
        project = root / 'Sources/Probe.xcodeproj'
        schemes = project / 'xcshareddata/xcschemes'
        schemes.mkdir(parents=True)
        (project / 'project.pbxproj').write_text(PROJECT)
        (schemes / 'Probe.xcscheme').write_text(SCHEME)
        (root / 'Sources/main.c').write_text('int helper(void); int main(void) { return helper(); }\n')
        (root / 'Sources/helper.c').write_text('int helper(void) { return 0; }\n')
        protected = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in (root / 'Sources').rglob('*') if p.is_file()}
        invocation = ['/usr/bin/xcodebuild', '-project', str(project), '-scheme', 'Probe',
                      '-configuration', 'Debug', '-destination', 'platform=macOS',
                      '-disableAutomaticPackageResolution', 'CODE_SIGNING_ALLOWED=NO']
        report['buildArguments'] = invocation + ['build']
        observations = {}
        with (output / 'build.log').open('wb') as log:
            child = subprocess.Popen(invocation + ['build'], stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 120
            while child.poll() is None:
                for row in descendants(child.pid):
                    observations[row['pid']] = row
                if time.monotonic() >= deadline:
                    # No termination: workflow timeout owns runner disposal.
                    raise RuntimeError('Owned build deadline exceeded; no cleanup or termination attempted')
                time.sleep(0.15)
            if child.returncode:
                raise RuntimeError('Owned default-layout build failed; original log retained')
        report['ownedBuildDescendants'] = list(observations.values())
        # Observe only previously captured PIDs after natural parent completion.
        lifecycle = []
        for delay in [0, 1, 2]:
            time.sleep(delay)
            remaining = []
            for pid in observations:
                result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'pid=,ppid=,stat=,comm='],
                                        capture_output=True, timeout=5, text=True)
                if result.stdout.strip():
                    fields = result.stdout.strip().split(None, 3)
                    remaining.append(dict(pid=int(fields[0]), parent=int(fields[1]),
                                          state=fields[2], executableBasename=Path(fields[3]).name))
            lifecycle.append(dict(secondsAfterPreviousObservation=delay, capturedPIDRows=remaining))
        report['capturedHelperLifetimeAfterBuild'] = lifecycle
        identity(standard)
        groups = []
        for folder in sorted(standard.iterdir()):
            if not folder.is_dir() or folder.is_symlink():
                continue
            metadata = folder / 'info.plist'
            if not metadata.exists():
                continue
            identity(folder)
            item = identity(metadata)
            if not stat.S_ISREG(item['mode']) or item['size'] > 65536:
                raise RuntimeError('Unexpected native project metadata shape')
            contents = metadata.read_bytes()
            parsed = plistlib.loads(contents)
            if not isinstance(parsed, dict):
                raise RuntimeError('Native project metadata is not a dictionary')
            (output / ('metadata-' + str(len(groups)) + '.plist')).write_bytes(contents)
            association = parsed.get('WorkspacePath')
            groups.append(dict(folder=folder.name, rootIdentity=identity(folder),
                               metadataIdentity=item, keys={k: type(v).__name__ for k, v in parsed.items()},
                               workspacePath=association,
                               knownOwnedAssociation=isinstance(association, str) and association in
                               [str(project), str(project / 'project.xcworkspace')]))
        report['nativeProjectMetadata'] = groups
        matched = [group for group in groups if group['knownOwnedAssociation']]
        if len(matched) != 1:
            raise RuntimeError('Native plist did not uniquely associate the owned project; schema remains unsupported')
        derived = standard / matched[0]['folder']
        settings_text = command(invocation + ['-showBuildSettings', '-json'], output / 'settings.json')
        settings = json.loads(settings_text)
        relevant = [{key: entry['buildSettings'].get(key) for key in
                     ['PROJECT_FILE_PATH', 'PROJECT_TEMP_DIR', 'TARGET_TEMP_DIR', 'OBJROOT',
                      'OBJECT_FILE_DIR_normal', 'SYMROOT', 'BUILT_PRODUCTS_DIR']}
                    for entry in settings if entry.get('target') == 'Probe']
        report['nativeOwnedBuildSettings'] = relevant
        objects = []
        for directory, dirs, files in os.walk(derived / 'Build/Intermediates.noindex', followlinks=False):
            dirs[:] = [name for name in dirs if not (Path(directory) / name).is_symlink()]
            for name in files:
                if name.endswith('.o'):
                    path = Path(directory) / name
                    item = identity(path)
                    if not stat.S_ISREG(item['mode']):
                        raise RuntimeError('Nonregular generated object')
                    objects.append(dict(relativePath=str(path.relative_to(derived)), identity=item))
        report['nativeObjectLeaves'] = objects
        if len(objects) != 2 or {Path(o['relativePath']).name for o in objects} != {'main.o', 'helper.o'}:
            raise RuntimeError('Owned compiler object layout differs from known recipe')
        if len(relevant) != 1 or Path(relevant[0]['OBJROOT']).resolve() != derived / 'Build/Intermediates.noindex':
            raise RuntimeError('Native settings do not independently match standard intermediates')
        report['protectedSourcesUnchanged'] = all(
            hashlib.sha256((root / name).read_bytes()).hexdigest() == digest
            for name, digest in protected.items())
        if not report['protectedSourcesUnchanged']:
            raise RuntimeError('Protected owned source changed')
        report.update(mappingObserved=True, completed=True,
                      limits='Discovery only; no deletion, production Core, owner-inactivity guarantee, archive or crash replay claim. Fixture outputs retained for runner disposal.')
    except Exception as error:
        report.update(completed=False, reason=str(error))
    if output is not None and output.is_dir():
        (output / 'report.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    return 0 if report.get('completed') else 1


if __name__ == '__main__':
    raise SystemExit(main())
