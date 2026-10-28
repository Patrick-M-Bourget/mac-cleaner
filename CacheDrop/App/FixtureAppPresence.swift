import CacheDropCore
import Foundation

#if DEBUG
/// Installed apps for a disposable test run (#173): only the bundle IDs listed in `<home>/.cachedrop-test-installed-apps`, one per
/// line, and the app bundles in `<home>/Applications` (#267), so a UI test never asks Spotlight or Launch Services about this Mac.
/// No installer receipts. While `<home>/.cachedrop-test-apps-unreadable` exists the list is unknown, as when Spotlight doesn't answer (#310).
struct FixtureAppPresence: AppPresence, InstallerReceiptReading {
    let home: URL?
    /// Set in a snapshot, which reads once for checking many items together.
    private var frozen: [InstalledApp]?? = nil
    init(home: URL?) { self.home = home }
    func snapshot() -> any AppPresence { var copy = self; copy.frozen = .some(installedApps()); return copy }
    /// Read on each call, so a model made once (the Applications page's) sees the fixture change, as it would see Spotlight answer again.
    func installedApps() -> [InstalledApp]? {
        if let frozen { return frozen }
        guard let home, !FileManager.default.fileExists(atPath: home.appendingPathComponent(".cachedrop-test-apps-unreadable").path) else { return nil }
        let listed = (try? String(contentsOf: home.appendingPathComponent(".cachedrop-test-installed-apps"), encoding: .utf8)) ?? ""
        return listed.split(separator: "\n").map { InstalledApp(name: String($0), bundleID: String($0), path: "/Applications/\($0).app") }
            + SystemAppPresence.bundles(in: home.appendingPathComponent("Applications")).compactMap(SystemAppPresence.app)
    }
    func isRegistered(bundleID: String) -> Bool { false }
    func receipts() -> [InstallerReceipt] { [] }
}
#endif
