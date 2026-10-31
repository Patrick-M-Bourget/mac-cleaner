import CacheDropCore
import Foundation

#if DEBUG
/// Installed apps for a disposable test run (#173): only the bundle IDs listed in `<home>/.cachedrop-test-installed-apps`, one per
/// line, and the app bundles in `<home>/Applications` (#267), so a UI test never asks Spotlight or Launch Services about this Mac.
/// While `<home>/.cachedrop-test-apps-unreadable` exists the list is unknown, as when Spotlight doesn't answer (#310).
struct FixtureAppPresence: AppPresence {
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

    /// #383: only this opt-in journey's disposable Synth bundle is made launchable outside the sandboxed runner.
    /// The journey verifies the signature and launches it itself; preparation errors fail that test, never skip it.
    @MainActor static func prepareQuitJourney() throws {
        guard LocalStateLocation.isDisposableTest,
              LocalStateLocation.fixtureEnvironment["CACHEDROP_TEST_PREPARE_SYNTH_APP"] == "1",
              let home = CatalogCleanupModel.home else { return }
        _ = try LocalStateLocation.root(create: false)
        let bundle = home.appendingPathComponent("Applications/Synth.app")
        let contents = bundle.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let executable = macOS.appendingPathComponent("main")
        let info = contents.appendingPathComponent("Info.plist")
        let paths = [bundle, contents, macOS, executable, info]
        guard paths.allSatisfy({ $0.path == $0.resolvingSymlinksInPath().path }),
              let identity = NSDictionary(contentsOf: info),
              identity["CFBundleIdentifier"] as? String == "com.maker.synth",
              identity["CFBundleExecutable"] as? String == "main" else { throw CocoaError(.fileReadNoPermission) }
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: executable.path)
        for path in paths { removexattr(path.path, "com.apple.quarantine", 0) }
        for arguments in [["--force", "--sign", "-", bundle.path], ["--verify", "--strict", bundle.path]] {
            let command = Process()
            command.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            command.arguments = arguments
            command.standardOutput = FileHandle.nullDevice
            command.standardError = FileHandle.nullDevice
            try command.run()
            command.waitUntilExit()
            guard command.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        }
    }
}
#endif
