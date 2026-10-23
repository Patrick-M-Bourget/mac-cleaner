import Foundation

public struct HomebrewPreview: Sendable {
    public let version: String
    public let prefix: String
    public let cache: String
    public let targets: [String]
    public let estimate: String?
    public let qualified: Bool
    public let guidance: String?
    public static func parse(version: String, prefix: String, cache: String, output: String, qualifiedVersion: String?) -> HomebrewPreview {
        func unavailable() -> HomebrewPreview {
            .init(version: version, prefix: prefix, cache: cache, targets: [], estimate: nil, qualified: false, guidance: "This Homebrew version/layout has not passed disposable qualification. No cleanup is enabled.")
        }
        guard let qualifiedVersion, version == qualifiedVersion, prefix.hasPrefix("/"), cache.hasPrefix("/"), prefix != "/", cache != "/" else { return unavailable() }
        var targets: [String] = []
        var estimate: String?
        for line in output.split(separator: "\n").map(String.init) {
            if line.hasPrefix("Would remove: ") {
                let target = String(line.dropFirst("Would remove: ".count))
                guard let boundary = target.range(of: " (", options: .backwards) else { return unavailable() }
                let path = String(target[..<boundary.lowerBound])
                let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
                guard path == normalized, path.hasPrefix(prefix + "/") || path.hasPrefix(cache + "/") else { return unavailable() }
                targets.append(target)
            } else if line.hasPrefix("Would free: ") {
                guard estimate == nil else { return unavailable() }
                estimate = String(line.dropFirst("Would free: ".count))
            } else { return unavailable() }
        }
        return .init(version: version, prefix: prefix, cache: cache, targets: targets, estimate: estimate, qualified: true, guidance: nil)
    }
}

public enum HomebrewInspector {
    /// No released installation has passed unchanged-state qualification yet.
    public static let qualifiedVersions: [String] = []
    public static func inspect(executable: URL) throws -> HomebrewPreview {
        guard executable.isFileURL, executable.lastPathComponent == "brew",
              FileManager.default.isExecutableFile(atPath: executable.path) else { throw ToolPreviewError.unavailable }
        // A directory/script name is not evidence of trusted runtime or dry-run semantics.
        // Fail closed before invoking an unqualified real installation, including --version.
        return HomebrewPreview.parse(version: "Unqualified installation (not executed)", prefix: "Unknown", cache: "Unknown", output: "", qualifiedVersion: nil)
    }
    /// Test-only integration seam restricted to explicitly disposable installation roots.
    static func inspectDisposable(executable: URL, qualifiedVersion: String) throws -> HomebrewPreview {
        guard executable.deletingLastPathComponent().lastPathComponent.hasPrefix("StillHomebrewProbe-") else { throw ToolPreviewError.unavailable }
        func command(_ args: [String]) throws -> String {
            try BoundedTool.run(executable: executable, arguments: args).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let version = try command(["--version"])
        guard version == qualifiedVersion else { return HomebrewPreview.parse(version: version, prefix: "Unknown", cache: "Unknown", output: "", qualifiedVersion: nil) }
        let prefix = try command(["--prefix"])
        let cache = try command(["--cache"])
        let output = try command(["cleanup", "--dry-run"])
        return HomebrewPreview.parse(version: version, prefix: prefix, cache: cache, output: output, qualifiedVersion: qualifiedVersion)
    }
}
