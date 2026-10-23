import Foundation

public struct ChromeEnvironment: Sendable {
    public var version: String
    public var ownerIdentified, profileMappingKnown, sharedOwnersKnown: Bool
    public var browserOrHelperRunning, activeWrites, reopened, deniedAccess, symlinkSwap: Bool?
    public init(version: String, ownerIdentified: Bool, profileMappingKnown: Bool, sharedOwnersKnown: Bool, browserOrHelperRunning: Bool?, activeWrites: Bool?, reopened: Bool?, deniedAccess: Bool?, symlinkSwap: Bool?) {
        self.version = version; self.ownerIdentified = ownerIdentified
        self.profileMappingKnown = profileMappingKnown; self.sharedOwnersKnown = sharedOwnersKnown
        self.browserOrHelperRunning = browserOrHelperRunning; self.activeWrites = activeWrites
        self.reopened = reopened; self.deniedAccess = deniedAccess; self.symlinkSwap = symlinkSwap
    }
}
public struct ChromeCapability: Sendable {
    public let supported: Bool
    public let reasons: [String]
    public let ruleVersion: String
}
public enum ChromeProbe {
    /// No real browser version has passed mutation/relaunch qualification.
    public static let qualifiedBrowserVersions: [String] = []
    public static func assess(_ environment: ChromeEnvironment) -> ChromeCapability {
        var reasons = ["version-not-qualified"]
        if !environment.ownerIdentified || !environment.profileMappingKnown || !environment.sharedOwnersKnown || environment.browserOrHelperRunning != false || environment.activeWrites != false || environment.reopened != false || environment.deniedAccess != false || environment.symlinkSwap != false {
            reasons.append("inactivity-or-ownership-unproven")
        }
        return ChromeCapability(supported: false, reasons: reasons, ruleVersion: "chrome-assets-investigation-1")
    }
}

public enum ChromeProbeError: Error { case disposableScopeRequired, unsupportedLayout }
extension ChromeProbe {
    /// Fixture-only positive allowlist. These are NOT qualified production cache roots.
    public static let fixtureRuleVersion = "fixture-only-1"
    public static let fixtureAssetAllowlist = ["Cache/Cache_Data"]

    /// Returns candidate relative groups without opening content or mutating any file.
    /// Profiles come from an explicit fixture manifest, never basename matching or profile inference.
    public static func inspectDisposableFixture(root: URL, profilePaths: [String]) throws -> [String] {
        let root = root.standardizedFileURL
        guard root.isFileURL, root.lastPathComponent.hasPrefix("StillChromeProbe-"),
              root == root.resolvingSymlinksInPath() else { throw ChromeProbeError.disposableScopeRequired }
        var groups = Set<String>()
        for profile in profilePaths {
            guard !profile.isEmpty, !profile.hasPrefix("/"), !profile.split(separator: "/").contains("..") else { throw ChromeProbeError.unsupportedLayout }
            for suffix in fixtureAssetAllowlist {
                let relative = profile + "/" + suffix
                let target = root.appendingPathComponent(relative).standardizedFileURL
                guard target.path.hasPrefix(root.path + "/"), target == target.resolvingSymlinksInPath() else { throw ChromeProbeError.unsupportedLayout }
                let values = try target.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { throw ChromeProbeError.unsupportedLayout }
                groups.insert(relative)
            }
        }
        return groups.sorted()
    }
}
