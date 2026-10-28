import CacheDropCore
import Foundation

#if DEBUG
/// Installed apps for a disposable test run (#173): only the bundle IDs listed in `<home>/.cachedrop-test-installed-apps`, one per
/// line, and the app bundles in `<home>/Applications` (#267), so a UI test never asks Spotlight or Launch Services about this Mac.
/// No installer receipts. While `<home>/.cachedrop-test-apps-unreadable` exists, the list can't be read (nil), as when
/// Spotlight doesn't answer (#321).
struct FixtureAppPresence: AppPresence, InstallerReceiptReading {
    let installed: [InstalledApp]?
    private let unreadableMarker: URL?
    init(home: URL?) {
        unreadableMarker = home?.appendingPathComponent(".cachedrop-test-apps-unreadable")
        guard let home else { installed = nil; return }
        let listed = (try? String(contentsOf: home.appendingPathComponent(".cachedrop-test-installed-apps"), encoding: .utf8)) ?? ""
        installed = listed.split(separator: "\n").map { InstalledApp(name: String($0), bundleID: String($0), path: "/Applications/\($0).app") }
            + SystemAppPresence.bundles(in: home.appendingPathComponent("Applications")).compactMap(SystemAppPresence.app)
    }
    func installedApps() -> [InstalledApp]? {
        if let unreadableMarker, FileManager.default.fileExists(atPath: unreadableMarker.path) { return nil }
        return installed
    }
    func isRegistered(bundleID: String) -> Bool { false }
    func receipts() -> [InstallerReceipt] { [] }
}
#endif
