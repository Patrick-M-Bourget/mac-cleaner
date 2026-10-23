import Foundation
import Testing
@testable import StillCore

@Test func unknownPipVersionsNeverProduceCleanupAuthority() {
    let inventory = PipInventory.parse(versionOutput: "pip 999.0 from /unknown (python 3.9)", configuredCache: "/tmp/cache", cacheInfo: "", wheelList: "")
    #expect(!inventory.supported)
    #expect(inventory.wheels.isEmpty)
    #expect(inventory.guidance != nil)
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

@Test func genuineDisposablePipInventoryPreservesOwnedEnvironment() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("StillPipProbe-" + UUID().uuidString).resolvingSymlinksInPath()
    try manager.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: root) }
    let home = root.appendingPathComponent("home")
    let cache = root.appendingPathComponent("alternate-cache")
    try manager.createDirectory(at: home, withIntermediateDirectories: false)
    try manager.createDirectory(at: cache, withIntermediateDirectories: false)
    let environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home.path, "TMPDIR": root.path, "LANG": "C", "LC_ALL": "C", "PIP_CONFIG_FILE": "/dev/null", "PIP_DISABLE_PIP_VERSION_CHECK": "1", "PYTHONDONTWRITEBYTECODE": "1"]
    let bootstrap = "import sys,venv,subprocess,pathlib; p=pathlib.Path(sys.argv[1]); venv.EnvBuilder(with_pip=False).create(str(p/'venv')); subprocess.run([str(p/'venv/bin/python3'),'-I','-B','-m','ensurepip','--default-pip'],check=True,capture_output=True)"
    _ = try BoundedTool.run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-I", "-B", "-c", bootstrap, root.path], timeout: 30, environment: environment)
    let wheel = cache.appendingPathComponent("wheels/ab/cd/ef/disposable/still_fixture-1.0-py3-none-any.whl")
    try manager.createDirectory(at: wheel.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("disposable-inventory-sentinel".utf8).write(to: wheel)
    let before = try ownedSnapshot(root)
    let report = try PipInventoryInspector.inspectDisposable(python: root.appendingPathComponent("venv/bin/python3"), cache: cache, home: home)
    #expect(report.inventory.supported)
    #expect(URL(fileURLWithPath: report.inventory.cache).resolvingSymlinksInPath().path == cache.resolvingSymlinksInPath().path)
    #expect(report.inventory.wheels.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == [wheel.resolvingSymlinksInPath().path])
    #expect(report.wheels.first?.logicalBytes == 29)
    #expect(try ownedSnapshot(root) == before)
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
