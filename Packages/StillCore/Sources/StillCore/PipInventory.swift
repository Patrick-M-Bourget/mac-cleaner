import Foundation

public struct PipInventory: Sendable {
    public let version: String
    public let cache: String
    public let wheels: [String]
    public let cacheInfo: String
    public let supported: Bool
    public let guidance: String?
    public static func parse(versionOutput: String, configuredCache: String, cacheInfo: String, wheelList: String) -> PipInventory {
        func unavailable() -> PipInventory {
            .init(version: versionOutput, cache: configuredCache, wheels: [], cacheInfo: cacheInfo, supported: false, guidance: "This interpreter/version has not passed disposable cache-inventory qualification. No cleanup is available.")
        }
        guard versionOutput.hasPrefix("pip 21.2.4 from "), versionOutput.hasSuffix("(python 3.9)"), configuredCache.hasPrefix("/"), configuredCache != "/",
              configuredCache.dropFirst().split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return unavailable() }
        let lines = cacheInfo.split(separator: "\n").map(String.init)
        guard lines.count == 6, lines[0] == "Package index page cache location: " + configuredCache + "/http",
              lines[1].hasPrefix("Package index page cache size: "), lines[2].hasPrefix("Number of HTTP files: "),
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
}
public enum PipInventoryInspector {
    public static func inspectSelected(python: URL, cache: URL) throws -> PipCacheReport {
        guard FileManager.default.isExecutableFile(atPath: python.path),
              (try? cache.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw ToolPreviewError.unavailable }
        // A selected Python path does not establish its site initialization or pip provenance.
        return .init(inventory: PipInventory.parse(versionOutput: "Unqualified interpreter (not executed)", configuredCache: cache.path, cacheInfo: "", wheelList: ""), wheels: [], observedAt: Date())
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
        let version = try command(["--version"])
        guard version.hasPrefix("pip 21.2.4 from "), version.hasSuffix("(python 3.9)") else {
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
