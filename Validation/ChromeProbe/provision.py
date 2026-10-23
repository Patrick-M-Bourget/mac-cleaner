#!/usr/bin/env python3
"""Hosted-only pinned development browser provisioning; no system installation."""
import hashlib, json, os, pathlib, platform, shutil, stat, subprocess, sys, time, urllib.request, zipfile, posixpath
VERSION = '156.0.8078.47'
URL = f'https://storage.googleapis.com/chrome-for-testing-public/{VERSION}/mac-arm64/chrome-mac-arm64.zip'

def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted' or platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('ephemeral GitHub-hosted macOS arm64 runner required')
    runner = pathlib.Path(os.environ['RUNNER_TEMP']).resolve(strict=True)
    destination = pathlib.Path(sys.argv[1])
    if not destination.is_absolute(): raise ValueError('absolute owned destination required')
    parent = destination.parent.resolve(strict=True)
    parent.relative_to(runner)
    destination = parent / destination.name
    if destination.exists() or destination.is_symlink(): raise ValueError('fresh destination required')
    if shutil.disk_usage(parent).free < 3 * 1024**3: raise ValueError('3 GiB provisioning headroom required')
    destination.mkdir(mode=0o700)
    evidence = destination / 'evidence'; evidence.mkdir()
    archive = destination / 'chrome.zip'
    started = time.monotonic(); size = 0; digest = hashlib.sha256()
    with urllib.request.urlopen(URL, timeout=30) as response, archive.open('xb') as output:
        if response.url != URL: raise ValueError('unexpected download redirect')
        while True:
            block = response.read(1024 * 1024)
            if not block: break
            size += len(block)
            if size > 500 * 1024**2 or time.monotonic() - started > 300: raise ValueError('bounded download exceeded')
            digest.update(block); output.write(block)
    with zipfile.ZipFile(archive) as zipped:
        members = zipped.infolist()
        if len(members) > 50000 or sum(m.file_size for m in members) > 2 * 1024**3:
            raise ValueError('bounded archive exceeded')
        links = set(); names = set()
        for member in members:
            name = member.filename.rstrip('/')
            parts = pathlib.PurePosixPath(name).parts
            if not parts or name.startswith('/') or '\\' in name or any(p in ('.', '..') for p in parts):
                raise ValueError('unsafe archive member')
            if parts[0] != 'chrome-mac-arm64' or name in names: raise ValueError('unexpected root or duplicate')
            names.add(name)
            mode = member.external_attr >> 16
            kind = stat.S_IFMT(mode)
            if kind not in (0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK): raise ValueError('unexpected member type')
            if stat.S_ISLNK(mode):
                if member.file_size > 4096: raise ValueError('oversized link')
                target = zipped.read(member).decode('utf8')
                normalized = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
                if target.startswith('/') or normalized == '..' or normalized.startswith('../') or not normalized.startswith('chrome-mac-arm64/'):
                    raise ValueError('escaping archive link')
                links.add(name)
        for name in names:
            if any(parent.as_posix() in links for parent in pathlib.PurePosixPath(name).parents):
                raise ValueError('archive member descends through link')
        unpacked = sum(m.file_size for m in members)
    if shutil.disk_usage(destination).free < unpacked + 1024**3: raise ValueError('unpacked size plus 1 GiB headroom required')
    subprocess.run(['/usr/bin/ditto', '-x', '-k', str(archive), str(destination)], check=True, timeout=180)
    bundle = destination / 'chrome-mac-arm64' / 'Google Chrome for Testing.app'
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(bundle)], check=True, timeout=60)
    signature = subprocess.run(['/usr/bin/codesign', '-dvv', str(bundle)], text=True, capture_output=True, check=True, timeout=10)
    binary = bundle / 'Contents' / 'MacOS' / 'Google Chrome for Testing'
    actual_version = subprocess.check_output([str(binary), '--version'], text=True, timeout=15).strip()
    if VERSION not in actual_version: raise ValueError('downloaded version mismatch')
    metadata = dict(version=VERSION, actualVersion=actual_version, sourceURL=URL,
                    versionManifestURL=f'https://googlechromelabs.github.io/chrome-for-testing/{VERSION}.json',
                    archiveSHA256=digest.hexdigest(), archiveBytes=size, unpackedBytes=unpacked,
                    digestMeaning='observed downloaded archive, not a publisher-published checksum',
                    signature=signature.stderr, os=platform.platform(), python=platform.python_version(),
                    githubSHA=os.environ.get('GITHUB_SHA'), githubRunID=os.environ.get('GITHUB_RUN_ID'))
    (evidence / 'provision.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(str(binary))

if __name__ == '__main__':
    try: main()
    except Exception as error:
        print('Provisioning refused/failed: ' + str(error), file=sys.stderr); sys.exit(1)
