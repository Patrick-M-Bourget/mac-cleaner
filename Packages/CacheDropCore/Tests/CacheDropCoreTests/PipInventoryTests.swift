import Foundation
import Testing
@testable import CacheDropCore

@Test func nonPipVersionOutputNeverProducesCleanupAuthority() {
    let inventory = PipInventory.parse(versionOutput: "Python 3.12.4", configuredCache: "/tmp/cache", cacheInfo: "", wheelList: "")
    #expect(!inventory.supported)
    #expect(inventory.wheels.isEmpty)
    #expect(inventory.guidance != nil)
}

@Test func anyPipVersionWithRecognizedCacheOutputIsSupported() {
    let info = "Package index page cache location: /owned/cache/http\nPackage index page cache size: 0 bytes\nNumber of HTTP files: 0\nWheels location: /owned/cache/wheels\nWheels size: 4 kB\nNumber of wheels: 1"
    let inventory = PipInventory.parse(versionOutput: "pip 24.2 from /owned/venv/site-packages/pip (python 3.12)", configuredCache: "/owned/cache", cacheInfo: info, wheelList: "/owned/cache/wheels/a/fixture.whl")
    #expect(inventory.supported)
    #expect(inventory.wheels == ["/owned/cache/wheels/a/fixture.whl"])
}

@Test func supportedPipOutputUsesActualAlternateRootAndKeepsWheelScopeExplicit() {
    let inventory = PipInventory.parse(versionOutput: "pip 21.2.4 from /owned/venv/site-packages/pip (python 3.9)", configuredCache: "/owned/alternate-cache", cacheInfo: "Package index page cache location: /owned/alternate-cache/http\nPackage index page cache size: 0 bytes\nNumber of HTTP files: 0\nWheels location: /owned/alternate-cache/wheels\nWheels size: 29 bytes\nNumber of wheels: 1", wheelList: "/owned/alternate-cache/wheels/a/fixture.whl\n")
    #expect(inventory.supported)
    #expect(inventory.cache == "/owned/alternate-cache")
    #expect(inventory.wheels == ["/owned/alternate-cache/wheels/a/fixture.whl"])
}

@Test func unknownCacheFormatAndEscapedWheelProduceGuidance() {
    let inventory = PipInventory.parse(versionOutput: "pip 21.2.4 from /owned/pip (python 3.9)", configuredCache: "/owned/cache", cacheInfo: "unknown future schema", wheelList: "/outside/secret.whl")
    #expect(!inventory.supported)
    #expect(inventory.wheels.isEmpty)
}

/// The real tools here can take tens of seconds on a busy Mac, so they run off the concurrency pool (#224).
@Test func genuineDisposablePipInventoryPreservesOwnedEnvironment() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("CacheDropPipProbe-" + UUID().uuidString).resolvingSymlinksInPath()
    try manager.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: root) }
    let home = root.appendingPathComponent("home")
    let cache = root.appendingPathComponent("alternate-cache")
    try manager.createDirectory(at: home, withIntermediateDirectories: false)
    try manager.createDirectory(at: cache, withIntermediateDirectories: false)
    let environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home.path, "TMPDIR": root.path, "LANG": "C", "LC_ALL": "C", "PIP_CONFIG_FILE": "/dev/null", "PIP_DISABLE_PIP_VERSION_CHECK": "1", "PYTHONDONTWRITEBYTECODE": "1"]
    let bootstrap = "import sys,venv,subprocess,pathlib; p=pathlib.Path(sys.argv[1]); venv.EnvBuilder(with_pip=False).create(str(p/'venv')); subprocess.run([str(p/'venv/bin/python3'),'-I','-B','-m','ensurepip','--default-pip'],check=True,capture_output=True)"
    let wheel = cache.appendingPathComponent("wheels/ab/cd/ef/disposable/cachedrop_fixture-1.0-py3-none-any.whl")
    let (report, before, after) = try await onOwnThread {
        _ = try BoundedTool.run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-I", "-B", "-c", bootstrap, root.path], timeout: 30, environment: environment)
        try FileManager.default.createDirectory(at: wheel.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("disposable-inventory-sentinel".utf8).write(to: wheel)
        let before = try ownedSnapshot(root)
        let report = try PipInventoryInspector.inspectDisposable(python: root.appendingPathComponent("venv/bin/python3"), cache: cache, home: home)
        return (report, before, try ownedSnapshot(root))
    }
    #expect(report.inventory.supported)
    #expect(URL(fileURLWithPath: report.inventory.cache).resolvingSymlinksInPath().path == cache.resolvingSymlinksInPath().path)
    #expect(report.inventory.wheels.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == [wheel.resolvingSymlinksInPath().path])
    #expect(report.wheels.first?.logicalBytes == 29)
    #expect(after == before)
}

private func ownedSnapshot(_ root: URL) throws -> [String: Data] {
    var snapshot: [String: Data] = [:]
    let rootDate = try root.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    snapshot["$rootmtime"] = Data(String(describing: rootDate?.timeIntervalSince1970).utf8)
    let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .contentModificationDateKey])!
    for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .contentModificationDateKey])
        let relative = String(url.path.dropFirst(root.path.count))
        if values.isSymbolicLink == true { snapshot[relative] = Data((try FileManager.default.destinationOfSymbolicLink(atPath: url.path)).utf8) }
        else if values.isRegularFile == true { snapshot[relative] = try Data(contentsOf: url) }
        else { snapshot[relative] = Data() }
        snapshot[relative + ":mtime"] = Data(String(describing: values.contentModificationDate?.timeIntervalSince1970).utf8)
    }
    return snapshot
}

@Test func unavailableSelectedInterpreterHasGuidanceBoundaryWithoutExecution() {
    #expect(throws: (any Error).self) {
        try PipInventoryInspector.inspectSelected(python: URL(fileURLWithPath: "/missing/python"), cache: URL(fileURLWithPath: "/missing/cache"))
    }
}

@Test func signedBundledPipInspectsExplicitCacheWithoutChangingOwnedFiles() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("CacheDropPipSelected-" + UUID().uuidString).resolvingSymlinksInPath()
    try manager.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: root) }
    let cache = root.appendingPathComponent("alternate-cache")
    let wheel = cache.appendingPathComponent("wheels/a/package-1.0-py3-none-any.whl")
    try manager.createDirectory(at: wheel.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("disposable-inventory-sentinel".utf8).write(to: wheel)
    let before = try ownedSnapshot(root)
    // The real bundled pip starts slowly when the machine is busy; the 5-second production limit made this flaky.
    // It runs off the concurrency pool so its wait never stalls other tests (#224).
    let report = try await onOwnThread {
        try PipInventoryInspector.inspectSelected(python: URL(fileURLWithPath: "/Library/Developer/CommandLineTools/usr/bin/python3"), cache: cache, toolTimeout: 60)
    }
    #expect(report.inventory.supported)
    #expect(URL(fileURLWithPath: report.inventory.cache).resolvingSymlinksInPath() == cache.resolvingSymlinksInPath())
    #expect(report.wheels.count == 1)
    #expect(report.wheels.first?.logicalBytes == 29)
    #expect(try ownedSnapshot(root) == before)
}

@Test func selectedPipRefusesCacheSubdirectoryLinkOutsideExplicitScope() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("CacheDropPipLinks-" + UUID().uuidString)
    try manager.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: root) }
    let cache = root.appendingPathComponent("cache")
    let protected = root.appendingPathComponent("protected")
    try manager.createDirectory(at: cache, withIntermediateDirectories: false)
    try manager.createDirectory(at: protected, withIntermediateDirectories: false)
    try Data("protected".utf8).write(to: protected.appendingPathComponent("response"))
    try manager.createSymbolicLink(at: cache.appendingPathComponent("http"), withDestinationURL: protected)
    let before = try ownedSnapshot(root)
    // The real bundled pip runs off the concurrency pool so its wait never stalls other tests (#224).
    let outcome = try await onOwnThread {
        Result { try PipInventoryInspector.inspectSelected(python: URL(fileURLWithPath: "/Library/Developer/CommandLineTools/usr/bin/python3"), cache: cache) }
    }
    #expect(throws: ToolPreviewError.invalidOutput) { try outcome.get() }
    #expect(try ownedSnapshot(root) == before)
}

@Test func selectedUntrustedExecutableIsNotInvokedEvenToAskVersion() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("CacheDropPipUntrusted-" + UUID().uuidString)
    try manager.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: root) }
    let executable = root.appendingPathComponent("python3")
    let marker = root.appendingPathComponent("executed")
    try Data("#!/bin/sh\ntouch '\(marker.path)'\n".utf8).write(to: executable)
    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let before = try ownedSnapshot(root)
    let report = try PipInventoryInspector.inspectSelected(python: executable, cache: root, toolTimeout: 60)
    #expect(!report.inventory.supported)
    #expect(!manager.fileExists(atPath: marker.path))
    #expect(try ownedSnapshot(root) == before)
}

@Test func pipWheelSubtotalsStayUnknownWhenMeasurementsOverflow() {
    let inventory = PipInventory.parse(versionOutput: "unsupported", configuredCache: "/cache", cacheInfo: "", wheelList: "")
    let report = PipCacheReport(inventory: inventory, wheels: [.init(path: "/cache/a.whl", logicalBytes: Int64.max, allocatedBytes: 8), .init(path: "/cache/b.whl", logicalBytes: 1, allocatedBytes: nil)], observedAt: Date())
    #expect(report.wheelLogicalBytes == nil)
    #expect(report.wheelAllocatedBytes == nil)
}
