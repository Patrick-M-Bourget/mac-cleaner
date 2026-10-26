#!/usr/bin/env python3
"""Official moving-Stable package, extracted only; no installer/scripts/updater."""
import datetime, hashlib, json, os, pathlib, platform, plistlib, shutil, subprocess, sys, time, urllib.request
URL = 'https://dl.google.com/chrome/mac/stable/accept_tos%3Dhttps%253A%252F%252Fwww.google.com%252Fintl%252Fen_ph%252Fchrome%252Fterms%252F%26_and_accept_tos%3Dhttps%253A%252F%252Fpolicies.google.com%252Fterms/googlechrome.pkg'
REQUIREMENT = 'anchor apple generic and identifier "com.google.Chrome" and certificate leaf[subject.OU] = "EQHXZ8M8AV"'
def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted' or platform.system() != 'Darwin' or platform.machine() != 'arm64': raise ValueError('ephemeral hosted macOS arm64 required')
    runner = pathlib.Path(os.environ['RUNNER_TEMP']).resolve(strict=True); destination = pathlib.Path(sys.argv[1])
    if not destination.is_absolute() or destination.exists() or destination.is_symlink(): raise ValueError('fresh absolute destination required')
    destination.parent.resolve(strict=True).relative_to(runner)
    if shutil.disk_usage(runner).free < 5 * 1024**3: raise ValueError('5 GiB extraction headroom required')
    destination.mkdir(mode=0o700); evidence = destination/'evidence'; evidence.mkdir(); package = destination/'googlechrome.pkg'
    report = {'sourceURL': URL, 'retrievedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'githubSHA': os.environ['GITHUB_SHA'], 'githubRunID': os.environ['GITHUB_RUN_ID'], 'os': platform.platform(), 'productionMutationSupported': False}
    def save(): (evidence/'provision.json').write_text(json.dumps(report, indent=2)+'\n')
    save(); started = time.monotonic(); size = 0; digest = hashlib.sha256()
    with urllib.request.urlopen(URL, timeout=30) as response, package.open('xb') as output:
        if not response.url.startswith('https://dl.google.com/'): raise ValueError('unexpected non-Google redirect')
        report['effectiveURL'] = response.url; report['responseHeaders'] = dict(response.headers)
        while True:
            block = response.read(1024**2)
            if not block: break
            size += len(block)
            if size > 500*1024**2 or time.monotonic()-started > 300: raise ValueError('download bounded limit exceeded')
            output.write(block); digest.update(block)
    report.update(archiveSHA256=digest.hexdigest(), archiveBytes=size, digestMeaning='observed moving Stable artifact, not publisher checksum'); save()
    subprocess.run(['/usr/sbin/pkgutil','--expand-full',str(package),str(destination/'expanded')], check=True, timeout=180)
    candidates = list((destination/'expanded').rglob('Google Chrome.app'))
    if len(candidates) != 1: raise ValueError('ambiguous extracted Chrome bundle')
    bundle = candidates[0]; binary = bundle/'Contents/MacOS/Google Chrome'
    info = plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != 'com.google.Chrome': raise ValueError('not regular Chrome Stable bundle')
    report.update(bundleIdentifier=info['CFBundleIdentifier'], version=info['CFBundleShortVersionString'], bundle=str(bundle), executableSHA256=hashlib.sha256(binary.read_bytes()).hexdigest())
    signatures = {}
    for name, path in [('bundle',bundle),('executable',binary),('framework',bundle/'Contents/Frameworks/Google Chrome Framework.framework')]:
        args = ['/usr/bin/codesign','--verify','--strict']
        if name == 'bundle': args += ['--deep','-R='+REQUIREMENT]
        result = subprocess.run(args+[str(path)], capture_output=True, text=True, timeout=90)
        signatures[name] = {'status':result.returncode,'stdout':result.stdout,'stderr':result.stderr}
        report['signatureVerification'] = signatures; save()
        if result.returncode: raise ValueError('invalid vendor signature: '+name)
    report['signatureMetadata'] = subprocess.run(['/usr/bin/codesign','-dvv',str(bundle)], capture_output=True,text=True,check=True).stderr
    report['sealedBundleVerified'] = True; report['provisioningComplete'] = True; save()
    print(str(binary))
if __name__ == '__main__':
    try: main()
    except Exception as error: print('Stable provisioning refused: '+str(error),file=sys.stderr); sys.exit(1)
