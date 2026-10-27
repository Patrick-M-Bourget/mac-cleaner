import Foundation
import Darwin

public struct PipInventory: Sendable {
    public let version: String
    public let cache: String
    public let wheels: [String]
    public let cacheInfo: String
    public let supported: Bool
    public let guidance: String?
    public static func parse(versionOutput: String, configuredCache: String, cacheInfo: String, wheelList: String) -> PipInventory {
        func unavailable() -> PipInventory {
            .init(version: versionOutput, cache: configuredCache, wheels: [], cacheInfo: cacheInfo, supported: false, guidance: "pip's cache report was not recognized. No cleanup is available.")
        }
        guard versionOutput.hasPrefix("pip "), configuredCache.hasPrefix("/"), configuredCache != "/",
              configuredCache.dropFirst().split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return unavailable() }
        let lines = cacheInfo.split(separator: "\n").map(String.init)
        guard lines.count == 6, lines[0] == "Package index page cache location: " + configuredCache + "/http",
              lines[1].hasPrefix("Package index page cache size: "), lines[2].hasPrefix("Number of HTTP files: "),
              let httpCount = Int(lines[2].dropFirst("Number of HTTP files: ".count)), httpCount >= 0,
              lines[3] == "Wheels location: " + configuredCache + "/wheels", lines[4].hasPrefix("Wheels size: "),
              lines[5].hasPrefix("Number of wheels: "), let count = Int(lines[5].dropFirst("Number of wheels: ".count)), count >= 0 else { return unavailable() }
        let wheels = wheelList.split(separator: "\n").map(String.init)
        guard wheels.count == count, Set(wheels).count == wheels.count,
              wheels.allSatisfy({ path in
                  path.hasPrefix(configuredCache + "/wheels/") && path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) && path.hasSuffix(".whl")
              }) else { return unavailable() }
        return .init(version: versionOutput, cache: configuredCache, wheels: wheels, cacheInfo: cacheInfo, supported: true, guidance: nil)
    }
}

public struct PipWheelMeasurement: Sendable {
    public let path: String
    public let logicalBytes: Int64?
    public let allocatedBytes: Int64?
}
public struct PipCacheReport: Sendable {
    public let inventory: PipInventory
    public let wheels: [PipWheelMeasurement]
    public let observedAt: Date
    public var wheelLogicalBytes: Int64? { subtotal(wheels.map(\.logicalBytes)) }
    public var wheelAllocatedBytes: Int64? { subtotal(wheels.map(\.allocatedBytes)) }
    private func subtotal(_ values: [Int64?]) -> Int64? {
        var result: Int64 = 0
        for value in values {
            guard let value, value >= 0 else { return nil }
            let sum = result.addingReportingOverflow(value)
            guard !sum.overflow else { return nil }
            result = sum.partialValue
        }
        return result
    }
}
public enum PipInventoryInspector {
    /// `toolTimeout` limits each pip command; tests that run the real bundled pip under load raise it.
    public static func inspectSelected(python: URL, cache: URL, toolTimeout: TimeInterval = 5) throws -> PipCacheReport {
        guard python.isFileURL, cache.isFileURL, FileManager.default.isExecutableFile(atPath: python.path),
              (try? cache.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw ToolPreviewError.unavailable }
        let executable = URL(fileURLWithPath: "/Library/Developer/CommandLineTools/usr/bin/python3")
        let framework = URL(fileURLWithPath: "/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework")
        // Never execute selected arbitrary code, even to ask its version. The trusted fixed
        // runtime uses no site initialization; pip comes only from its root-owned bundled wheel.
        guard python.standardizedFileURL.resolvingSymlinksInPath() == executable.resolvingSymlinksInPath() else {
            return unqualified(cache: cache)
        }
        for target in [executable, framework] {
            _ = try BoundedTool.run(executable: URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["--verify", "--deep", "--strict", "--test-requirement==anchor apple", target.path], timeout: 15)
        }
        guard let wheel = bundledPipWheel(in: framework) else { return unqualified(cache: cache) }
        let selectedCache = cache.standardizedFileURL.resolvingSymlinksInPath()
        guard selectedCache.path != "/" else { throw ToolPreviewError.unavailable }
        try preflightCache(selectedCache)
        let environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/empty", "TMPDIR": "/var/empty", "LANG": "C", "LC_ALL": "C", "PIP_CONFIG_FILE": "/dev/null", "PIP_DISABLE_PIP_VERSION_CHECK": "1", "PIP_NO_INDEX": "1", "PYTHONDONTWRITEBYTECODE": "1"]
        let launcher = "import sys,runpy; wheel=sys.argv.pop(1); sys.path.insert(0,wheel); sys.argv[0]='pip'; runpy.run_module('pip',run_name='__main__')"
        func command(_ args: [String]) throws -> String {
            try BoundedTool.run(executable: executable, arguments: ["-I", "-S", "-B", "-c", launcher, wheel.path, "--disable-pip-version-check", "--cache-dir", selectedCache.path] + args, timeout: toolTimeout, environment: environment).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return try collect(cache: selectedCache, command: command)
    }
    /// The CLT framework's bundled pip wheel, whatever its Python or pip version.
    private static func bundledPipWheel(in framework: URL) -> URL? {
        let lib = framework.appendingPathComponent("Versions/Current/lib")
        guard let pythons = try? FileManager.default.contentsOfDirectory(atPath: lib.path) else { return nil }
        let wheels = pythons.filter { $0.hasPrefix("python3.") }.flatMap { python -> [URL] in
            let bundled = lib.appendingPathComponent(python + "/ensurepip/_bundled")
            let names = (try? FileManager.default.contentsOfDirectory(atPath: bundled.path)) ?? []
            return names.filter { $0.hasPrefix("pip-") && $0.hasSuffix(".whl") }.map { bundled.appendingPathComponent($0) }
        }
        guard wheels.count == 1, let wheel = wheels.first else { return nil }
        var info = stat()
        guard lstat(wheel.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == 0,
              info.st_mode & 0o022 == 0, info.st_size < 4_000_000 else { return nil }
        return wheel
    }
    private static func preflightCache(_ cache: URL) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        var before = stat()
        guard lstat(cache.path, &before) == 0, before.st_mode & S_IFMT == S_IFDIR else { throw ToolPreviewError.unavailable }
        var failed = false
        guard let entries = FileManager.default.enumerator(at: cache, includingPropertiesForKeys: [], options: [], errorHandler: { _, _ in failed = true; return false }) else { throw ToolPreviewError.unavailable }
        var count = 0
        for case let entry as URL in entries {
            count += 1
            guard count <= 100_000, entry.pathComponents.count - cache.pathComponents.count <= 64 else { throw ToolPreviewError.outputLimit }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw ToolPreviewError.timeout }
            var metadata = stat()
            guard lstat(entry.path, &metadata) == 0, metadata.st_mode & S_IFMT != S_IFLNK else { throw ToolPreviewError.invalidOutput }
            guard metadata.st_dev == before.st_dev else { entries.skipDescendants(); throw ToolPreviewError.invalidOutput }
        }
        var after = stat()
        guard !failed, lstat(cache.path, &after) == 0,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw ToolPreviewError.invalidOutput }
    }
    private static func unqualified(cache: URL) -> PipCacheReport {
        .init(inventory: PipInventory.parse(versionOutput: "Unqualified interpreter (not executed)", configuredCache: cache.path, cacheInfo: "", wheelList: ""), wheels: [], observedAt: Date())
    }
    static func inspectDisposable(python: URL, cache: URL, home: URL) throws -> PipCacheReport {
        let root = home.deletingLastPathComponent().standardizedFileURL
        guard root.lastPathComponent.hasPrefix("StillPipProbe-"), root.path == root.resolvingSymlinksInPath().path,
              python.path.hasPrefix(root.path + "/venv/bin/"),
              cache.path.hasPrefix(root.path + "/"), cache.path == cache.resolvingSymlinksInPath().path,
              home.path.hasPrefix(root.path + "/"), home.path == home.resolvingSymlinksInPath().path else { throw ToolPreviewError.unavailable }
        let environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home.path, "TMPDIR": root.path, "LANG": "C", "LC_ALL": "C", "PIP_CONFIG_FILE": "/dev/null", "PIP_DISABLE_PIP_VERSION_CHECK": "1", "PYTHONDONTWRITEBYTECODE": "1"]
        func command(_ args: [String]) throws -> String {
            try BoundedTool.run(executable: python, arguments: ["-I", "-B", "-m", "pip", "--disable-pip-version-check", "--cache-dir", cache.path] + args, environment: environment).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return try collect(cache: cache, command: command)
    }
    private static func collect(cache: URL, command: ([String]) throws -> String) throws -> PipCacheReport {
        let version = try command(["--version"])
        guard version.hasPrefix("pip ") else {
            return .init(inventory: PipInventory.parse(versionOutput: version, configuredCache: cache.path, cacheInfo: "", wheelList: ""), wheels: [], observedAt: Date())
        }
        let configuredCache = try command(["cache", "dir"])
        guard URL(fileURLWithPath: configuredCache).resolvingSymlinksInPath().path == cache.resolvingSymlinksInPath().path else { throw ToolPreviewError.invalidOutput }
        let inventory = PipInventory.parse(versionOutput: version, configuredCache: configuredCache, cacheInfo: try command(["cache", "info"]), wheelList: try command(["cache", "list", "--format=abspath"]))
        var wheels: [PipWheelMeasurement] = []
        if inventory.supported {
            for path in inventory.wheels {
                let url = URL(fileURLWithPath: path)
                guard url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(cache.resolvingSymlinksInPath().path + "/") else { throw ToolPreviewError.invalidOutput }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ToolPreviewError.invalidOutput }
                wheels.append(.init(path: path, logicalBytes: values.fileSize.map(Int64.init), allocatedBytes: values.totalFileAllocatedSize.map(Int64.init)))
            }
        }
        return .init(inventory: inventory, wheels: wheels, observedAt: Date())
    }
}
