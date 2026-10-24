#!/usr/bin/env python3
"""Observe genuine pip21.2.4 removal semantics in a new owned offline venv/cache only."""
import hashlib
import json
import os
import platform
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import zipfile


def snapshot(root):
    result = {}
    for path in sorted(root.rglob('*')):
        info = path.lstat()
        relative = str(path.relative_to(root))
        if stat.S_ISLNK(info.st_mode):
            payload = ['symlink', os.readlink(path)]
        elif stat.S_ISREG(info.st_mode):
            payload = ['file', hashlib.sha256(path.read_bytes()).hexdigest(), info.st_size]
        else:
            payload = ['directory']
        result[relative] = payload + [info.st_mode, info.st_mtime_ns]
    return result


def seed_wheel(path, name='still_fixture', version='1.0'):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Owned wheel-format fixture; not downloaded, built by pip, installed or executed.
    with zipfile.ZipFile(path, 'w') as wheel:
        wheel.writestr(name + '/__init__.py', '# disposable fixture\n')
        prefix = name + '-' + version + '.dist-info/'
        wheel.writestr(prefix + 'METADATA', 'Metadata-Version: 2.1\nName: ' + name + '\nVersion: ' + version + '\n')
        wheel.writestr(prefix + 'WHEEL', 'Wheel-Version: 1.0\nGenerator: Still-owned-fixture\nRoot-Is-Purelib: true\nTag: py3-none-any\n')
        wheel.writestr(prefix + 'RECORD', '')


def main():
    root = Path(tempfile.mkdtemp(prefix='StillPipMutation-')).resolve()
    os.chmod(root, 0o700)
    try:
        protected = root / 'protected'; protected.mkdir()
        home = protected / 'home'; home.mkdir()
        temp = root / 'tmp'; temp.mkdir()
        source = protected / 'project'; source.mkdir()
        (source / 'pyproject.toml').write_text('[project]\nname="protected-source"\nversion="1.0"\n')
        (source / 'never-remove.py').write_text('# protected original\n')
        env = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME': str(home), 'TMPDIR': str(temp), 'LANG': 'C', 'LC_ALL': 'C', 'PIP_CONFIG_FILE': '/dev/null', 'PIP_DISABLE_PIP_VERSION_CHECK': '1', 'PIP_NO_INDEX': '1', 'PYTHONDONTWRITEBYTECODE': '1'}
        def run(arguments, timeout=15):
            value = subprocess.run(arguments, env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout)
            return {'exit': value.returncode, 'stdout': value.stdout.replace(str(root), '<owned>'), 'stderr': value.stderr.replace(str(root), '<owned>')}
        bootstrap = 'import venv,sys,subprocess; venv.EnvBuilder(with_pip=False).create(sys.argv[1]); subprocess.run([sys.argv[1]+"/bin/python3","-I","-B","-m","ensurepip","--default-pip"],check=True,capture_output=True)'
        venv = protected / 'venv'
        bootstrap_result = run(['/usr/bin/python3', '-I', '-B', '-c', bootstrap, str(venv)], 45)
        assert bootstrap_result['exit'] == 0, bootstrap_result
        python = str(venv / 'bin/python3')
        version = run([python, '-I', '-B', '-m', 'pip', '--version'])
        assert version['exit'] == 0 and version['stdout'].startswith('pip 21.2.4 ') and '(python 3.9)' in version['stdout'], version
        protected_before = snapshot(protected)
        scenarios = []
        for mode in ('absolute-path', 'exact-basename', 'version-prefix', 'package-name', 'replaced-entry'):
            cache = root / ('cache-' + mode)
            approved = cache / 'wheels/aa/reviewed/still_fixture-1.0-py3-none-any.whl'
            unrelated = cache / 'wheels/zz/unrelated/other_package-1.0-py3-none-any.whl'
            seed_wheel(approved); seed_wheel(unrelated, 'other_package')
            http = cache / 'http/owned-response-sentinel'; http.parent.mkdir(); http.write_bytes(b'protected-http-fixture')
            prefix = [python, '-I', '-B', '-m', 'pip', '--disable-pip-version-check', '--cache-dir', str(cache)]
            inventory = run(prefix + ['cache', 'list', '--format=abspath'])
            assert inventory['exit'] == 0 and str(approved).replace(str(root), '<owned>') in inventory['stdout']
            selected = {str(approved.relative_to(cache)): [approved.lstat().st_dev, approved.lstat().st_ino]}
            late = cache / 'wheels/bb/new/still_fixture-1.0-py3-none-any.whl'
            other_version = cache / 'wheels/cc/new/still_fixture-2.0-py3-none-any.whl'
            if mode != 'replaced-entry':
                seed_wheel(late); seed_wheel(other_version, version='2.0')
            else:
                replacement = approved.with_suffix('.replacement')
                seed_wheel(replacement); replacement.replace(approved)
                assert [approved.lstat().st_dev, approved.lstat().st_ino] != list(selected.values())[0]
            before_files = {str(path.relative_to(cache)) for path in cache.rglob('*') if path.is_file()}
            protected_cache = {str(unrelated.relative_to(cache)): hashlib.sha256(unrelated.read_bytes()).hexdigest(), str(http.relative_to(cache)): hashlib.sha256(http.read_bytes()).hexdigest()}
            pattern = str(approved) if mode == 'absolute-path' else 'still_fixture' if mode == 'package-name' else 'still_fixture-1.0-' if mode in ('version-prefix', 'replaced-entry') else approved.name
            operation = run(prefix + ['cache', 'remove', pattern])
            after_files = {str(path.relative_to(cache)) for path in cache.rglob('*') if path.is_file()}
            deleted = sorted(before_files - after_files)
            unapproved_deleted = sorted(set(deleted) - set(selected))
            assert protected_cache == {name: hashlib.sha256((cache / name).read_bytes()).hexdigest() for name in protected_cache}
            scenarios.append({'mode': mode, 'command': ['<owned-venv-python>', '-I', '-B', '-m', 'pip', '--disable-pip-version-check', '--cache-dir', '<owned-cache>', 'cache', 'remove', '<approved-absolute-path>' if mode == 'absolute-path' else pattern], 'approvedEntryCount': 1, 'lateMatchingEntries': 0 if mode == 'replaced-entry' else 2, 'sourceIdentityReplaced': mode == 'replaced-entry', 'operation': operation, 'deleted': deleted, 'unapprovedNewEntriesDeleted': unapproved_deleted, 'originalApprovedPathStillExists': approved.exists(), 'protectedOtherWheelAndHTTPUnchanged': True, 'honorsFrozenIdentityManifest': not unapproved_deleted and mode != 'replaced-entry' and deleted == list(selected)})
        assert protected_before == snapshot(protected), 'Protected project/venv/HOME changed'
        assert any(row['unapprovedNewEntriesDeleted'] for row in scenarios), 'No observed widening; revisit conclusion'
        report = {'schema': 1, 'experiment': 'genuine-pip-removal-command-with-owned-seeded-wheels', 'host': {'macOS': platform.mac_ver()[0], 'architecture': platform.machine()}, 'version': version['stdout'].strip(), 'provisioning': 'owned venv + bundled ensurepip; no global install or network command', 'environment': {'PIP_CONFIG_FILE': '/dev/null', 'PIP_NO_INDEX': '1', 'isolatedPython': True, 'bytecodeWritesDisabled': True, 'HOME_TMP_CACHE': 'owned'}, 'scenarios': scenarios, 'protectedProjectVenvHomeEntries': len(protected_before), 'allProtectedSnapshotEntriesUnchanged': True, 'productionMutationQualified': False, 'decision': 'Refuse vendor cache remove/purge for an exact frozen path/resource manifest; patterns re-enumerate current matching entries and do not bind reviewed identities', 'limits': ['Real pip21.2.4 command; wheels/HTTP data seeded, not downloaded or produced by pip build', 'No concurrent pip process or OS permission/timeout/cancellation fixture exercised', 'No arbitrary interpreter/version or modern HTTP-v2 qualification', 'No direct file-unlink alternative or durable product mutation implemented']}
    finally:
        shutil.rmtree(root)
    report['ownedRootRemoved'] = True
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
