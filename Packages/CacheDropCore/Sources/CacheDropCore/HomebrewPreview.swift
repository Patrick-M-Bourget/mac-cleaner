import Foundation

public struct HomebrewPreview: Sendable {
    public let version: String
    public let prefix: String
    public let cache: String
    public let targets: [String]
    public let estimate: String?
    public let qualified: Bool
    public let guidance: String?
    public static func parse(version: String, prefix: String, cache: String, output: String) -> HomebrewPreview {
        func unavailable() -> HomebrewPreview {
            .init(version: version, prefix: prefix, cache: cache, targets: [], estimate: nil, qualified: false, guidance: "Homebrew's dry-run output was not recognized. No cleanup is enabled.")
        }
        guard version.hasPrefix("Homebrew "), prefix.hasPrefix("/"), cache.hasPrefix("/"), prefix != "/", cache != "/" else { return unavailable() }
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
    /// Test-only integration seam restricted to explicitly disposable installation roots.
    static func inspectDisposable(executable: URL) throws -> HomebrewPreview {
        guard executable.deletingLastPathComponent().lastPathComponent.hasPrefix("StillHomebrewProbe-") else { throw ToolPreviewError.unavailable }
        func command(_ args: [String]) throws -> String {
            try BoundedTool.run(executable: executable, arguments: args).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let version = try command(["--version"])
        let prefix = try command(["--prefix"])
        let cache = try command(["--cache"])
        let output = try command(["cleanup", "--dry-run"])
        return HomebrewPreview.parse(version: version, prefix: prefix, cache: cache, output: output)
    }
}
