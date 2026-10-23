#!/usr/bin/env python3
"""Genuine Swift/local-package experiment. No external project/root is accepted."""
import hashlib, json, os, platform, shutil, signal, stat, subprocess, sys, tempfile, time
from pathlib import Path
from run import PROJECT, SCHEME, fingerprint, hashes

# Owned fixture recipes, never a production DerivedData classifier.
def project_recipe():
    project = PROJECT.replace('sourcecode.c.c', 'sourcecode.swift').replace('main.c', 'main.swift').replace('helper.c', 'helper.swift')
    project = project.replace('targets = (000000000000000000000005);', 'targets = (000000000000000000000005); packageReferences = (000000000000000000000015);')
    project = project.replace('buildPhases = (000000000000000000000011);', 'buildPhases = (000000000000000000000011,000000000000000000000017); packageProductDependencies = (000000000000000000000016);')
    project = project.replace('PRODUCT_NAME = Probe;', 'PRODUCT_NAME = Probe; SWIFT_VERSION = 6.0; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_COMPILATION_MODE = singlefile;')
    return project.replace('}; rootObject', '''000000000000000000000015 = {isa = XCLocalSwiftPackageReference; relativePath = LocalPackage;};
000000000000000000000016 = {isa = XCSwiftPackageProductDependency; package = 000000000000000000000015; productName = OwnedSupport;};
000000000000000000000017 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (000000000000000000000018); runOnlyForDeploymentPostprocessing = 0;};
000000000000000000000018 = {isa = PBXBuildFile; productRef = 000000000000000000000016;};
}; rootObject''')


def child_types(owner_pid):
    """Observe only descendants of a child we launched; do not retain other rows."""
    rows = subprocess.check_output(['/bin/ps', '-axo', 'pid=,ppid=,comm='], text=True, timeout=5).splitlines()
    parsed = [line.strip().split(None, 2) for line in rows]
    owned = {owner_pid}; names = set()
    for _ in range(20):
        previous = len(owned)
        for row in parsed:
            if len(row) == 3 and (int(row[0]) in owned or int(row[1]) in owned):
                owned.add(int(row[0])); names.add(Path(row[2]).name)
        if len(owned) == previous: break
    return names


def build(command, env, log_path, owned_processes):
    observed = set(); started = time.monotonic()
    with log_path.open('w') as log:
        child = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        owned_processes.append(child)
        try:
            while child.poll() is None:
                observed.update(child_types(child.pid))
                if time.monotonic() - started > 120: raise TimeoutError('Owned build deadline exceeded')
                time.sleep(0.03)
        finally:
            if child.poll() is None:
                # Terminate only the exact xcodebuild process we started; never shared build services.
                child.terminate(); child.wait(timeout=10)
    if child.returncode:
        raise RuntimeError('Owned Swift build failed: ' + log_path.read_text()[-5000:])
    return {'seconds': round(time.monotonic() - started, 3), 'observedOwnedDescendantTypes': sorted(observed), 'exit': child.returncode}


def append_record(journal, entry):
    fd = os.open(journal, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
    try:
        payload = json.dumps(entry, sort_keys=True).encode() + b'\n'
        count = os.write(fd, payload)
        if count != len(payload): raise OSError('Incomplete journal record')
        os.fsync(fd)
    finally: os.close(fd)
    fd = os.open(journal.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try: os.fsync(fd)
    finally: os.close(fd)


def remove_exact(root, relative, expected, writers):
    if not writers or any(child.poll() is None or child.returncode != 0 for child in writers):
        return 'owner-active-or-unknown'
    parts = Path(relative).parts
    if parts[:2] != ('Custom', 'Intermediates') or not relative.endswith('.o') or any(p in ('Sources', 'SourcePackages') or p.endswith(('.dSYM', '.xcarchive', '.app')) for p in parts):
        return 'unsupported-artifact'
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for component in parts[:-1]:
            next_fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd); fd = next_fd
        current = os.stat(parts[-1], dir_fd=fd, follow_symlinks=False)
        actual = [current.st_dev, current.st_ino, current.st_size, current.st_mtime_ns, current.st_ctime_ns]
        if not stat.S_ISREG(current.st_mode) or current.st_nlink != 1 or current.st_uid != os.geteuid() or actual != expected:
            return 'changed-target'
        os.unlink(parts[-1], dir_fd=fd)
        return 'removed'
    except OSError: return 'unavailable'
    finally: os.close(fd)


def main():
    if len(sys.argv) != 1: raise ValueError('No external root or project accepted')
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    version = subprocess.check_output(['/usr/bin/xcodebuild', '-version'], env=env, text=True, timeout=15).strip()
    if version != 'Xcode 27.1\nBuild version 27A9275': raise RuntimeError('Only exact observed Xcode 27.1/27A9275 supported by this experiment')
    if shutil.disk_usage(tempfile.gettempdir()).free < 1024**3: raise RuntimeError('At least 1 GiB experiment headroom required')
    root = Path(tempfile.mkdtemp(prefix='StillXcodeSwift-')).resolve(); os.chmod(root, 0o700)
    report = {'schema': 1, 'experiment': 'owned-swift-package-custom-output-session', 'toolchain': version, 'os': platform.platform(), 'productionMutationQualified': False}
    writer = None; owned_processes = []; preserve_root = False
    try:
        sources = root / 'Sources'; project = sources / 'Probe.xcodeproj'
        schemes = project / 'xcshareddata/xcschemes'; schemes.mkdir(parents=True)
        (project / 'project.pbxproj').write_text(project_recipe()); (schemes / 'Probe.xcscheme').write_text(SCHEME)
        (sources / 'main.swift').write_text('import OwnedSupport\nprint(ownedValue() + helper())\n')
        (sources / 'helper.swift').write_text('func helper() -> Int { 1 }\n')
        package = sources / 'LocalPackage'; (package / 'Sources/OwnedSupport').mkdir(parents=True)
        (package / 'Package.swift').write_text('// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: "OwnedSupport", products: [.library(name: "OwnedSupport", targets: ["OwnedSupport"])], targets: [.target(name: "OwnedSupport")])\n')
        (package / 'Sources/OwnedSupport/OwnedSupport.swift').write_text('public func ownedValue() -> Int { 41 }\n')
        command = ['/usr/bin/xcodebuild', '-project', str(project), '-scheme', 'Probe', '-configuration', 'Debug', '-destination', 'platform=macOS', '-derivedDataPath', str(root / 'MetadataOnly'), '-clonedSourcePackagesDirPath', str(root / 'OwnedPackageCheckouts'), '-disableAutomaticPackageResolution', 'CODE_SIGNING_ALLOWED=NO', 'OBJROOT=' + str(root / 'Custom/Intermediates'), 'SYMROOT=' + str(root / 'Custom/Products')]
        first = build(command + ['build'], env, root / 'build.log', owned_processes)
        objects = sorted((root / 'Custom/Intermediates').rglob('*.o'))
        if len(objects) < 3 or not any('OwnedSupport.build' in str(p) for p in objects):
            raise RuntimeError('No actual local-package object in configured custom intermediates')
        settings_result = subprocess.run(command + ['-showBuildSettings', '-json'], env=env, text=True, capture_output=True, timeout=30)
        if settings_result.returncode: raise RuntimeError(settings_result.stderr[-2000:])
        settings = json.loads(settings_result.stdout)
        own_settings = next(item['buildSettings'] for item in settings if item['target'] == 'Probe')
        assert Path(own_settings['OBJROOT']).resolve() == root / 'Custom/Intermediates'
        assert Path(own_settings['SYMROOT']).resolve() == root / 'Custom/Products'
        archive = root / 'Archives/SwiftProbe.xcarchive'
        archive_command = [arg for arg in command if not arg.startswith(('OBJROOT=', 'SYMROOT='))]
        archive_command[archive_command.index('-derivedDataPath') + 1] = str(root / 'ArchiveMetadata')
        archived = build(archive_command + ['archive', '-archivePath', str(archive)], env, root / 'archive.log', owned_processes)
        dsym = root / 'Custom/Products/Debug/Probe.dSYM'
        if not dsym.is_dir() or not list(archive.rglob('*.dSYM')): raise RuntimeError('Genuine Swift symbols/archive missing')
        protected = {'sources': hashes(sources), 'archive': hashes(archive), 'dsym': hashes(dsym)}
        assert all(protected.values())
        objects = sorted((root / 'Custom/Intermediates').rglob('*.o'))
        manifest = {str(p.relative_to(root)): fingerprint(p) for p in objects}
        # A tracked late writer is a real process; it remains active after review.
        late = objects[0].parent / 'new-after-review.o'
        writer = subprocess.Popen([sys.executable, '-I', '-c', 'import pathlib,sys,time; pathlib.Path(sys.argv[1]).write_bytes(b"owned-late-discovery"); print("ready",flush=True); time.sleep(1)', str(late)], stdout=subprocess.PIPE, text=True)
        owned_processes.append(writer)
        assert writer.stdout.readline().strip() == 'ready'
        first_path = sorted(manifest)[0]
        assert remove_exact(root, first_path, manifest[first_path], [writer]) == 'owner-active-or-unknown'
        writer.wait(timeout=10); assert writer.returncode == 0
        assert late.read_bytes() == b'owned-late-discovery'
        # Cancellation authorizes no second operation: only one exact original leaf is attempted.
        journal = root / 'owned-operation.jsonl'
        append_record(journal, {'operation': 'cancel-scenario', 'event': 'intent', 'target': first_path, 'fingerprint': manifest[first_path]})
        outcome = remove_exact(root, first_path, manifest[first_path], [writer])
        assert outcome == 'removed'; append_record(journal, {'operation': 'cancel-scenario', 'event': 'outcome', 'target': first_path, 'status': outcome})
        remaining = [path for path in sorted(manifest) if path != first_path]
        assert all((root / path).is_file() for path in remaining)
        append_record(journal, {'operation': 'cancel-scenario', 'event': 'cancelled', 'unstarted': remaining})
        # Real SIGKILL after persisted intent and unlink, before outcome. No external worker-root API.
        crash_path = remaining[0]
        crash_approval = fingerprint(root / crash_path)
        pid = os.fork()
        if pid == 0:
            append_record(journal, {'operation': 'crash-scenario', 'event': 'intent', 'target': crash_path, 'fingerprint': crash_approval})
            status = remove_exact(root, crash_path, crash_approval, [writer])
            if status != 'removed': os._exit(91)
            os.kill(os.getpid(), signal.SIGKILL)
            os._exit(92)
        _, status = os.waitpid(pid, 0)
        assert os.WIFSIGNALED(status) and os.WTERMSIG(status) == signal.SIGKILL
        snapshot = journal.read_bytes(); records = [json.loads(line) for line in snapshot.splitlines()]
        assert records[-1]['event'] == 'intent' and records[-1]['target'] == crash_path
        assert not (root / crash_path).exists()
        # Read-only recovery cannot infer unlink success from absence or replay cancelled/new entries.
        intents = {(item['operation'], item['target']) for item in records if item['event'] == 'intent'}
        outcomes = {(item['operation'], item['target']) for item in records if item['event'] == 'outcome'}
        unresolved = sorted(intents - outcomes)
        assert unresolved == [('crash-scenario', crash_path)]
        cancelled = next(item['unstarted'] for item in records if item['event'] == 'cancelled')
        assert cancelled == remaining
        assert all((root / path).is_file() for path in cancelled if path != crash_path)
        recovery = {'state': 'unresolved-no-automatic-replay' if unresolved else 'resolved', 'unresolvedTargets': unresolved}
        assert snapshot == journal.read_bytes() and late.read_bytes() == b'owned-late-discovery'
        after = {'sources': hashes(sources), 'archive': hashes(archive), 'dsym': hashes(dsym)}
        assert protected == after
        rebuilt = build(command + ['build'], env, root / 'rebuild.log', owned_processes)
        assert all((root / path).is_file() for path in manifest)
        assert protected['sources'] == hashes(sources) and protected['archive'] == hashes(archive)
        report.update(swiftPackageBuilt=True, customOutputMappingObserved=True, swiftCompilerObserved=any('swift' in name.lower() for name in first['observedOwnedDescendantTypes']), build=first, archive=archived, rebuild=rebuilt, archiveOutputLimit='Custom OBJROOT+SYMROOT archive attempt failed native BuildProductsPath lookup; successful archive uses separate explicit owned DerivedData with default archive layout', actualObjectPaths=sorted(manifest), objectCount=len(manifest), generatedObjectLogicalBytes=sum(v[2] for v in manifest.values()), activeTrackedWriterRejected=True, lateDiscoveryPreserved=True, cancellationLeftUnstartedObjects=True, crashSignal=signal.SIGKILL, recoveryState=recovery['state'], durableRecordEvents=[item['event'] for item in records], durableJournalRecords=records, cancelledUnstartedTargets=cancelled, unresolvedIntentTargets=[list(item) for item in unresolved], journalReadOnlyObservationUnchanged=snapshot == journal.read_bytes(), cancellationScenarioOnly=True, protectedBeforeSHA256=protected, protectedAfterSHA256=after, allProtectedHashesUnchanged=True, protectedFileCounts={key: len(value) for key,value in protected.items()}, removedObjectsRegenerated=True, productionOwnerContract='unsupported: tracked-child completion is not exclusive ownership of GUI Xcode, XCBBuildService, helpers or future writers', raceLimit='descriptor-relative exact-leaf checks do not atomically exclude final name swaps or a new concurrent writer', durableRecoveryIntegrated=False)
    except BaseException:
        # On failed builds/ambiguous helper shutdown, preserve rather than traverse
        # the output tree. Exact child return alone cannot exclude shared helpers.
        preserve_root = True
        raise
    finally:
        for child in owned_processes:
            if child.poll() is None:
                child.terminate()
                try: child.wait(timeout=10)
                except subprocess.TimeoutExpired: preserve_root = True
        if not preserve_root and all(child.poll() is not None for child in owned_processes):
            shutil.rmtree(root)
        else:
            print('Owned experiment root preserved after failure/uncertain writer exit: ' + str(root), file=sys.stderr)
    report['ownedRootRemoved'] = not preserve_root
    print(json.dumps(report, indent=2))

if __name__ == '__main__': main()
