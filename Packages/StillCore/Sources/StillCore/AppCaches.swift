import AppKit
import Foundation

/// Updater downloads, per-app caches and the user's logs (#103).
public enum AppCaches {
    /// Still's own folders are never offered, whatever their name.
    static let stillNames = ["Still", "com.patrickbourget.Still", "com.patrickbourget.StillUITests"]

    /// A folder name that is an app's bundle identifier: reverse-DNS with at least three parts.
    static func isBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 3 && parts.allSatisfy { part in !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") } }
            && parts[0].first?.isLetter == true
    }
    /// macOS's own caches and Still's are never offered, whoever asks.
    static func isExcluded(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return id.hasPrefix("com.apple.") || id.hasPrefix("com.patrickbourget.still")
    }
    /// The installed app a folder named by bundle identifier belongs to, or nil when that can't be determined.
    static func installedOwner(_ folder: String, apps: any AppLookup) -> RuleOwner? {
        guard isBundleID(folder), !isExcluded(folder), let app = apps.app(bundleID: folder) else { return nil }
        return RuleOwner(name: app.name, bundleIDs: [folder], paths: [app.path])
    }

    public static func rules(apps: any AppLookup) -> [CleanupRule] {
        [
            CleanupRule(id: "app-caches", category: .system, title: "App caches",
                        detail: "Files apps keep in your Library to start and work faster, per app.",
                        consequence: "Permanently removed. Each app rebuilds its cache as you use it, so it may be slower at first. An app must be closed first; Still never quits it for you.",
                        regen: .cache, action: .delete, locations: ["Library/Caches/*"], owner: nil,
                        protectedNames: stillNames, itemOwner: { installedOwner($0.lastPathComponent, apps: apps) }, yieldsToOtherRules: true),
            // Crash reports first, so ~/Library/Logs/DiagnosticReports is listed once, as crash reports.
            CleanupRule(id: "crash-reports", category: .logs, title: "Crash reports",
                        detail: "Reports macOS wrote when your apps crashed or stopped responding.",
                        consequence: "Permanently removed. They can no longer be sent to a developer; macOS writes new ones if an app crashes again.",
                        regen: .log, action: .delete, locations: ["Library/Logs/DiagnosticReports"], owner: nil,
                        protectedNames: stillNames),
            CleanupRule(id: "app-logs", category: .logs, title: "App logs",
                        detail: "Logs apps keep in your Library, per app.",
                        consequence: "Permanently removed. Apps write new logs as they run; past logs are no longer available for troubleshooting.",
                        regen: .log, action: .delete, locations: ["Library/Logs/*"], owner: nil,
                        protectedNames: stillNames, yieldsToOtherRules: true),
        ]
    }
}

/// Finds installed apps. Injected so tests never depend on this Mac's apps.
public protocol AppLookup: Sendable {
    func app(bundleID: String) -> InstalledApp?
}

/// The apps LaunchServices knows on this Mac.
public struct SystemAppLookup: AppLookup {
    public init() {}
    public func app(bundleID: String) -> InstalledApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = (Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return InstalledApp(name: name, bundleID: bundleID, path: url.resolvingSymlinksInPath().path)
    }
}

/// An installed app, as LaunchServices reports it.
public struct InstalledApp: Sendable, Hashable {
    public let name: String
    public let bundleID: String
    /// The app bundle's path; a process run from inside it counts as the app.
    public let path: String
    public init(name: String, bundleID: String, path: String) { self.name = name; self.bundleID = bundleID; self.path = path }
}
