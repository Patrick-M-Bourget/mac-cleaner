import Foundation

/// Updater downloads, per-app caches and the user's logs (#103).
public enum AppCaches {
    /// Still's own folders are never offered, whatever their name.
    static let stillNames = ["Still", "com.patrickbourget.Still", "com.patrickbourget.StillUITests"]

    public static func rules(apps: any AppLookup) -> [CleanupRule] {
        [
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
                        protectedNames: stillNames),
        ]
    }
}

/// Finds installed apps. Injected so tests never depend on this Mac's apps.
public protocol AppLookup: Sendable {}

/// The apps LaunchServices knows on this Mac.
public struct SystemAppLookup: AppLookup {
    public init() {}
}
