#!/usr/bin/env python3
"""Build and mutate only a newly owned disposable Xcode project; no external root accepted."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import time

PROJECT = '''// !$*UTF8*$!
{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {
000000000000000000000001 = {isa = PBXProject; buildConfigurationList = 000000000000000000000002; compatibilityVersion = "Xcode 14.0"; mainGroup = 000000000000000000000003; productRefGroup = 000000000000000000000004; projectDirPath = ""; projectRoot = ""; targets = (000000000000000000000005);};
000000000000000000000002 = {isa = XCConfigurationList; buildConfigurations = (000000000000000000000006); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;};
000000000000000000000003 = {isa = PBXGroup; children = (000000000000000000000007,000000000000000000000008,000000000000000000000004); sourceTree = "<group>";};
000000000000000000000004 = {isa = PBXGroup; children = (000000000000000000000009); name = Products; sourceTree = "<group>";};
000000000000000000000005 = {isa = PBXNativeTarget; buildConfigurationList = 000000000000000000000010; buildPhases = (000000000000000000000011); buildRules = (); dependencies = (); name = Probe; productName = Probe; productReference = 000000000000000000000009; productType = "com.apple.product-type.tool";};
000000000000000000000006 = {isa = XCBuildConfiguration; name = Debug; buildSettings = {SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 14.0;};};
000000000000000000000007 = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.c; path = main.c; sourceTree = "<group>";};
000000000000000000000008 = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.c; path = helper.c; sourceTree = "<group>";};
000000000000000000000009 = {isa = PBXFileReference; explicitFileType = "compiled.mach-o.executable"; path = Probe; sourceTree = BUILT_PRODUCTS_DIR;};
000000000000000000000010 = {isa = XCConfigurationList; buildConfigurations = (000000000000000000000012); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;};
000000000000000000000011 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (000000000000000000000013,000000000000000000000014); runOnlyForDeploymentPostprocessing = 0;};
000000000000000000000012 = {isa = XCBuildConfiguration; name = Debug; buildSettings = {PRODUCT_NAME = Probe; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; GCC_GENERATE_DEBUGGING_SYMBOLS = YES; GCC_OPTIMIZATION_LEVEL = 0; CODE_SIGNING_ALLOWED = NO; SKIP_INSTALL = NO; INSTALL_PATH = /usr/local/bin; ONLY_ACTIVE_ARCH = YES;};};
000000000000000000000013 = {isa = PBXBuildFile; fileRef = 000000000000000000000007;};
000000000000000000000014 = {isa = PBXBuildFile; fileRef = 000000000000000000000008;};
}; rootObject = 000000000000000000000001; }
'''
SCHEME = '''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.3"><BuildAction parallelizeBuildables="NO" buildImplicitDependencies="NO"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="000000000000000000000005" BuildableName="Probe" BlueprintName="Probe" ReferencedContainer="container:Probe.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><ArchiveAction buildConfiguration="Debug" revealArchiveInOrganizer="NO"/></Scheme>
'''


def fingerprint(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.geteuid():
        raise ValueError("Nonregular, aliased or unowned target")
    return [info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns]


def hashes(root):
    return {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(root.rglob('*')) if path.is_file() and not path.is_symlink()}


def remove_manifest(root, manifest, builder):
    if builder is None or builder.poll() is None or builder.returncode != 0:
        return {"owner": "active-or-unknown", "removed": [], "skipped": []}
    removed, skipped = [], []
    for relative, expected in sorted(manifest.items()):
        parts = Path(relative).parts
        if parts[:4] != ('DerivedData', 'Probe-native', 'Build', 'Intermediates.noindex') or not relative.endswith('.o') or any(part in ('Sources', 'SourcePackages') or part.endswith(('.dSYM', '.xcarchive', '.app')) for part in parts):
            skipped.append(relative); continue
        fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            for component in parts[:-1]:
                next_fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                os.close(fd); fd = next_fd
            current = os.stat(parts[-1], dir_fd=fd, follow_symlinks=False)
            actual = [current.st_dev, current.st_ino, current.st_size, current.st_mtime_ns, current.st_ctime_ns]
            if not stat.S_ISREG(current.st_mode) or current.st_nlink != 1 or current.st_uid != os.geteuid() or actual != expected:
                skipped.append(relative); continue
            os.unlink(parts[-1], dir_fd=fd)
            removed.append(relative)
        except OSError:
            skipped.append(relative)
        finally:
            os.close(fd)
    return {"owner": "owned-xcodebuild-returned-success", "removed": removed, "skipped": skipped}


def main():
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    version = subprocess.check_output(['/usr/bin/xcodebuild', '-version'], env=env, text=True).strip()
    if version != 'Xcode 27.1\nBuild version 27A9275':
        raise RuntimeError('Only the observed Xcode27.1/27A9275 experiment is allowed')
    if shutil.disk_usage(tempfile.gettempdir()).free < 512_000_000:
        raise RuntimeError('At least512MB disposable experiment headroom required')
    root = Path(tempfile.mkdtemp(prefix='StillXcodeNative-')).resolve()
    os.chmod(root, 0o700)
    builder = None
    archive_process = None
    report = {"schema": 1, "experiment": "genuine-owned-xcode-project", "toolchain": version, "productionMutationQualified": False}
    try:
        project = root / 'Sources/Probe.xcodeproj'
        schemes = project / 'xcshareddata/xcschemes'; schemes.mkdir(parents=True)
        (project / 'project.pbxproj').write_text(PROJECT)
        (schemes / 'Probe.xcscheme').write_text(SCHEME)
        (root / 'Sources/main.c').write_text('int helper(void); int main(void) { return helper(); }\n')
        (root / 'Sources/helper.c').write_text('int helper(void) { return 0; }\n')
        source_before = hashes(root / 'Sources')
        dd = root / 'DerivedData/Probe-native'
        command = ['/usr/bin/xcodebuild', '-project', str(project), '-scheme', 'Probe', '-configuration', 'Debug', '-destination', 'platform=macOS', '-derivedDataPath', str(dd), '-disableAutomaticPackageResolution', 'CODE_SIGNING_ALLOWED=NO']
        started = time.monotonic()
        with (root / 'build.log').open('w') as log:
            builder = subprocess.Popen(command + ['build'], env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            active_rejection = remove_manifest(root, {}, builder)
            builder.wait(timeout=120)
        if builder.returncode != 0:
            raise RuntimeError('Owned build failed: ' + (root / 'build.log').read_text()[-3000:])
        build_seconds = time.monotonic() - started
        objects = sorted((dd / 'Build/Intermediates.noindex').rglob('*.o'))
        manifest = {str(path.relative_to(root)): fingerprint(path) for path in objects}
        if len(manifest) != 2 or not any(path.name == 'main.o' for path in objects):
            raise RuntimeError('Unexpected generated object layout')
        # Generate a genuine isolated archive/dSYM, not a labelled fake directory.
        archive = root / 'Archives/Probe.xcarchive'
        with (root / 'archive.log').open('w') as log:
            archive_process = subprocess.Popen(command + ['archive', '-archivePath', str(archive)], env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            active_objects_rejected = remove_manifest(root, manifest, archive_process)
            assert active_objects_rejected['owner'] == 'active-or-unknown' and not active_objects_rejected['removed']
            assert all(path.exists() for path in objects)
            archive_process.wait(timeout=120)
        if archive_process.returncode != 0:
            raise RuntimeError('Owned archive failed: ' + (root / 'archive.log').read_text()[-3000:])
        dsym = dd / 'Build/Products/Debug/Probe.dSYM'
        if not dsym.is_dir() or not list(archive.rglob('*.dSYM')):
            raise RuntimeError('Expected genuine product/archive dSYMs missing')
        # Freeze after both owned builds finish, since archive may update shared objects.
        manifest = {str(path.relative_to(root)): fingerprint(path) for path in objects}
        protected_before = {"sources": hashes(root / 'Sources'), "archive": hashes(archive), "dsym": hashes(dsym)}
        changed = next(path for path in objects if path.name == 'main.o')
        replacement = changed.with_suffix('.replacement'); replacement.write_bytes(changed.read_bytes()); replacement.replace(changed)
        late = objects[0].parent / 'new-after-review.o'; late.write_bytes(b'owned-new-discovery')
        outcome = remove_manifest(root, manifest, archive_process)
        protected_after = {"sources": hashes(root / 'Sources'), "archive": hashes(archive), "dsym": hashes(dsym)}
        assert active_rejection['owner'] == 'active-or-unknown'
        assert len(outcome['removed']) == 1 and len(outcome['skipped']) == 1
        assert changed.exists() and late.read_bytes() == b'owned-new-discovery'
        assert protected_before == protected_after and source_before == hashes(root / 'Sources')
        rebuild_started = time.monotonic()
        with (root / 'rebuild.log').open('w') as log:
            rebuild = subprocess.run(command + ['build'], env=env, stdout=log, stderr=subprocess.STDOUT, timeout=120)
        rebuild_seconds = time.monotonic() - rebuild_started
        assert rebuild.returncode == 0 and all(path.is_file() for path in objects)
        assert source_before == hashes(root / 'Sources') and protected_before['archive'] == hashes(archive)
        report.update({"buildExit": builder.returncode, "archiveExit": archive_process.returncode, "buildSeconds": round(build_seconds, 3), "rootOwnership": "new-private0700-temporary-root", "activeOwnedBuilderRejected": True, "activeManifestTargetCount": len(manifest), "rebuildExit": rebuild.returncode, "rebuildSeconds": round(rebuild_seconds, 3), "removedObjectRegenerated": True, "objectsObserved": sorted(manifest), "removedExactUnchangedObjects": outcome['removed'], "skippedReplacedObjects": outcome['skipped'], "newDiscoveryPreserved": True, "protectedSourceFiles": len(protected_before['sources']), "protectedArchiveFiles": len(protected_before['archive']), "protectedProductDSYMFiles": len(protected_before['dsym']), "allProtectedHashesUnchanged": True, "generatedObjectBytes": sum(value[2] for value in manifest.values()), "ownerEvidenceLimit": "Only owned child xcodebuild completion is observed; no global Xcode/XCBBuildService/helper inactivity or exclusive ownership is proved", "mutationLimit": "Descriptor-relative no-follow parent walk + fresh fingerprint before unlink; final name swap and new writer concurrency are not atomically excluded", "durableRecoveryIntegrated": False})
    finally:
        for owned_process in (builder, archive_process):
            if owned_process is not None and owned_process.poll() is None:
                owned_process.terminate(); owned_process.wait(timeout=10)
        # No external path is accepted; this removes only this process's freshly owned experiment.
        shutil.rmtree(root)
    report['ownedRootRemoved'] = True
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
