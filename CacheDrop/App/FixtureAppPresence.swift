import CacheDropCore
import Foundation

#if DEBUG
/// Installed apps for a disposable test run (#173): only the bundle IDs listed in `<home>/.cachedrop-test-installed-apps`, one per
/// line, and the app bundles in `<home>/Applications` (#267), so a UI test never asks Spotlight or Launch Services about this Mac.
/// Installer receipts only from `<home>/.cachedrop-test-receipts` (#319): one per line, tab-separated, as package ID, the app
/// it installed, then the paths it lists.
struct FixtureAppPresence: AppPresence, InstallerReceiptReading {
    let installed: [InstalledApp]?
    private let listedReceipts: [InstallerReceipt]
    init(home: URL?) {
        guard let home else { installed = nil; listedReceipts = []; return }
        let receipts = (try? String(contentsOf: home.appendingPathComponent(".cachedrop-test-receipts"), encoding: .utf8)) ?? ""
        listedReceipts = receipts.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t").map(String.init)
            return fields.count >= 3 ? InstallerReceipt(id: fields[0], apps: [fields[1]], paths: Set(fields.dropFirst(2))) : nil
        }
        let listed = (try? String(contentsOf: home.appendingPathComponent(".cachedrop-test-installed-apps"), encoding: .utf8)) ?? ""
        installed = listed.split(separator: "\n").map { InstalledApp(name: String($0), bundleID: String($0), path: "/Applications/\($0).app") }
            + SystemAppPresence.bundles(in: home.appendingPathComponent("Applications")).compactMap(SystemAppPresence.app)
    }
    func installedApps() -> [InstalledApp]? { installed }
    func isRegistered(bundleID: String) -> Bool { false }
    func receipts() -> [InstallerReceipt] { listedReceipts }
}
#endif
