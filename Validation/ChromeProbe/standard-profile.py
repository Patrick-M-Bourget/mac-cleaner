#!/usr/bin/env python3
"""Hosted-only default Stable split-root observation; never cleans personal files.

Usage: standard-profile.py VERIFIED_PROVISION_JSON NEW_EVIDENCE_DIRECTORY
No CDP, preference/DB seeding or installer; same-run fresh roots only.
"""
import hashlib
import html
import stat
import http.server
import json
import os
import pathlib
import platform
import plistlib
import re
import subprocess
import sys
import threading

REQUIREMENT = 'anchor apple generic and identifier "com.google.Chrome" and certificate leaf[subject.OU] = "EQHXZ8M8AV"'


def main():
    if (os.environ.get('GITHUB_ACTIONS') != 'true' or
            os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted' or
            platform.system() != 'Darwin'):
        raise ValueError('fresh hosted macOS required; no local browser access')
    runner = pathlib.Path(os.environ['RUNNER_TEMP']).resolve(strict=True)
    provenance_path = pathlib.Path(sys.argv[1]).resolve(strict=True)
    provenance_path.relative_to(runner)
    provenance = json.loads(provenance_path.read_text())
    if not provenance.get('provisioningComplete') or not provenance.get('sealedBundleVerified'):
        raise ValueError('verified Stable provision required')
    if provenance.get('githubRunID') != os.environ['GITHUB_RUN_ID']:
        raise ValueError('same-run provision required')
    bundle = pathlib.Path(provenance['bundle']).resolve(strict=True)
    bundle.relative_to(runner)
    binary = bundle / 'Contents/MacOS/Google Chrome'
    digest = lambda: hashlib.sha256(binary.read_bytes()).hexdigest()
    if digest() != provenance['executableSHA256']:
        raise ValueError('provisioned executable changed')
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict',
                    '-R=' + REQUIREMENT, str(bundle)], check=True, timeout=90)
    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != 'com.google.Chrome':
        raise ValueError('regular Stable required')
    # Do not redirect HOME: Foundation derives the actual user's standard dirs.
    home = pathlib.Path.home()
    data = home / 'Library/Application Support/Google/Chrome'
    cache = home / 'Library/Caches/Google/Chrome'
    for target in (data, cache):
        if target.exists() or target.is_symlink():
            raise ValueError('standard Stable root already exists; no inspection permitted')
        parent = target.parent
        while not parent.exists():
            parent = parent.parent
        if parent.is_symlink() or parent.resolve() != parent:
            raise ValueError('noncanonical standard ancestor')
    processes = subprocess.check_output(['/bin/ps', '-axo', 'command='], text=True)
    if re.search(r'/[^\n]*Google Chrome(?:\.app/| Helper)', processes):
        raise ValueError('existing browser owner; fresh runner required')
    # Managed configuration is outside this one-layout qualification contract.
    for policy in (home / 'Library/Preferences/com.google.Chrome.plist',
                   pathlib.Path('/Library/Preferences/com.google.Chrome.plist'),
                   home / 'Library/Managed Preferences/com.google.Chrome.plist',
                   pathlib.Path('/Library/Managed Preferences/com.google.Chrome.plist')):
        if policy.exists() or policy.is_symlink():
            raise ValueError('pre-existing/managed Chrome preferences unsupported')
    evidence = pathlib.Path(sys.argv[2])
    if not evidence.is_absolute() or evidence.exists() or evidence.is_symlink():
        raise ValueError('fresh absolute evidence destination required')
    evidence.parent.resolve(strict=True).relative_to(runner)
    evidence.mkdir(mode=0o700)
    report = {'schema': 1, 'qualification': 'fresh standard split-root close-and-clean',
              'productionMutationSupported': False, 'githubSHA': os.environ['GITHUB_SHA'],
              'githubRunID': os.environ['GITHUB_RUN_ID'], 'version': provenance['version'],
              'executableSHA256': provenance['executableSHA256'],
              'dataRoot': str(data), 'cacheRoot': str(cache),
              'cleanupExercised': False, 'personalFilesInspected': False,
              'initialRootsAbsent': True, 'verifiedProvision': str(provenance_path),
              'explicitFreshStandardUserDataDir': True,
              'limitations': ['headless explicitly selects fresh standard data root; not unflagged headed startup',
                             'no saved-password/address semantics in this check',
                             'managed/custom disk-cache/shared layouts unsupported',
                             'hosted fresh-root qualification authority only; no production adapter']}
    save = lambda: (evidence / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    save()
    # Actual prior DOM showed headless auto-selects a temporary incognito root.
    # Explicitly select ONLY the standard root whose absence was proved above.
    # No HOME redirect, remote debugging or sandbox/signature bypass.
    flags = [str(binary), '--headless=new', '--no-first-run', '--no-default-browser-check',
             '--profile-directory=Default', '--user-data-dir=' + str(data), '--dump-dom']
    def launch(url, name):
        # Chrome documents chrome:// access as an explicit headless opt-in since123.
        scheme_access = ['--allow-chrome-scheme-url'] if url == 'chrome://version' else []
        result = subprocess.run(flags + scheme_access + [url], capture_output=True, text=True, timeout=45)
        (evidence / (name + '.html')).write_text(result.stdout)
        (evidence / (name + '.stderr')).write_text(result.stderr)
        if result.returncode:
            raise ValueError(name + ' browser exit ' + str(result.returncode))
        return result.stdout
    requests = []
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            body = (b'<!doctype html><title>Still default-root probe</title>'
                    b'<script src="/asset.js"></script>') if self.path == '/' else (
                    b'window.stillDefaultRootProbe=true;\n' * 4096)
            self.send_response(200)
            self.send_header('Cache-Control', 'public, max-age=86400')
            self.send_header('Content-Type', 'text/html' if self.path == '/' else 'application/javascript')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def log_message(self, *args):
            pass
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        dom = launch('chrome://version', 'browser-version')
        expected_profile = data / 'Default'
        match = re.search(r'id=[\"\']profile_path[\"\'][^>]*>(.*?)</td>', dom, re.S)
        actual_profile = html.unescape(re.sub('<[^>]+>', '', match.group(1))).strip() if match else None
        if actual_profile != str(expected_profile):
            raise ValueError('browser-owned Profile Path does not identify standard Default')
        command_match = re.search(r'id=[\"\']command_line[\"\'][^>]*>(.*?)</td>', dom, re.S)
        actual_command = html.unescape(re.sub('<[^>]+>', '', command_match.group(1))).strip() if command_match else None
        if actual_command is None or re.search(r'(^|\s)--incognito(?:\s|=|$)', actual_command):
            raise ValueError('browser command line missing or profile remains incognito')
        report.update(browserProfilePathMatched=True, actualProfilePath=actual_profile,
                      actualBrowserCommandLine=actual_command, incognitoObserved=False)
        launch('http://127.0.0.1:' + str(server.server_port) + '/', 'loopback')
        if '/asset.js' not in requests:
            raise ValueError('browser did not request synthetic downloaded asset')
        group = cache / 'Default/Cache/Cache_Data'
        group_info = group.lstat()
        if not group.is_dir() or group.is_symlink() or group_info.st_uid != os.getuid():
            raise ValueError('browser-created standard asset group missing or unowned')
        for parent in [cache, cache / 'Default', group.parent]:
            if parent.is_symlink() or parent.resolve() != parent or parent.stat().st_uid != os.getuid():
                raise ValueError('ambiguous standard cache association')
        leaves = list(group.iterdir())
        if not leaves:
            raise ValueError('browser-created group empty')
        report.update(browserRequestedAsset=True, cacheGroup=str(group),
                      groupIdentity=[group_info.st_dev, group_info.st_ino, group_info.st_uid],
                      dataRootIdentity=[data.stat().st_dev, data.stat().st_ino, data.stat().st_uid],
                      cacheRootIdentity=[cache.stat().st_dev, cache.stat().st_ino, cache.stat().st_uid],
                      immediateCacheEntryCount=len(leaves), result='passed mapping observation')
        save()  # Proof is usable only after actual browser-reported mapping.
        owned = runner / 'StillChromeProbe-Standard'
        owned.mkdir(mode=0o700)  # existing sandbox means this is not a fresh experiment
        def protected_snapshot():
            snapshot = {}
            total = 0
            for directory, directories, files in os.walk(data, followlinks=False):
                for name in directories + files:
                    target = pathlib.Path(directory) / name
                    item = target.lstat()
                    key = str(target.relative_to(data))
                    if stat.S_ISLNK(item.st_mode):
                        snapshot[key] = ['link', os.readlink(target)]
                    elif stat.S_ISREG(item.st_mode):
                        total += item.st_size
                        if total > 500 * 1024**2:
                            raise ValueError('bounded protected-data snapshot exceeded')
                        snapshot[key] = ['file', item.st_size, hashlib.sha256(target.read_bytes()).hexdigest()]
                    elif not stat.S_ISDIR(item.st_mode):
                        raise ValueError('unexpected protected profile object')
            return snapshot
        protected = protected_snapshot()
        if not protected:
            raise ValueError('no browser-created protected profile data')
        helper = pathlib.Path(__file__).with_name('cache-group.py')
        args = [sys.executable, str(helper), str(owned), str(group), str(bundle)]
        option = ['--standard-proof', str(evidence / 'report.json')]
        observe = subprocess.run(args + ['observe'] + option, capture_output=True, text=True, timeout=120)
        (evidence / 'observe.stdout').write_text(observe.stdout)
        (evidence / 'observe.stderr').write_text(observe.stderr)
        if observe.returncode:
            raise ValueError('standard group observation refused')
        clean = subprocess.run(args + ['clean'] + option, input=observe.stdout,
                               capture_output=True, text=True, timeout=120)
        (evidence / 'cleanup.stdout').write_text(clean.stdout)
        (evidence / 'cleanup.stderr').write_text(clean.stderr)
        if clean.returncode:
            raise ValueError('standard group cleanup refused or stopped')
        outcome = json.loads(clean.stdout)
        if outcome.get('status') != 'completed' or outcome.get('removed', 0) <= 0:
            raise ValueError('standard cleanup removed no eligible entries')
        if protected_snapshot() != protected:
            raise ValueError('protected browser-created profile changed during cache cleanup')
        report.update(cleanupExercised=True, cleanup=outcome, protectedProfileUnchanged=True,
                      protectedObjectCount=len(protected))
        # Regrowth may legitimately update profile databases; compare them before reopening.
        asset_requests_before = requests.count('/asset.js')
        launch('http://127.0.0.1:' + str(server.server_port) + '/', 'regrowth')
        if requests.count('/asset.js') <= asset_requests_before:
            raise ValueError('deleted asset was not requested again')
        report['assetRequestedAgainAfterCleanup'] = True
        if not any(re.fullmatch(r'[0-9a-f]{16}_[0-9]+', item.name) and item.is_file()
                   for item in group.iterdir()):
            raise ValueError('standard asset cache did not regenerate')
        report.update(cacheRegenerated=True, result='passed standard split-root close-and-clean')
        if digest() != provenance['executableSHA256']:
            raise ValueError('executable changed during observation')
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict',
                        '-R=' + REQUIREMENT, str(bundle)], check=True, timeout=90)
        save()
    except Exception as error:
        report.update(result='unsupported or failed observation', reason=str(error))
        save()
        raise
    finally:
        server.shutdown()
        # Leave only this runner's Chrome-created evidence roots until runner disposal.
        # Never add a fallback deletion or kill other Chrome instances here.
    print(json.dumps(report))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Standard-profile qualification refused: ' + str(error), file=sys.stderr)
        sys.exit(1)
