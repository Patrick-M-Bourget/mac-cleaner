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

    /// The fixture apps a journey may open, each behind its own opt-in switch: its bundle's name, identifier and executable.
    /// Synth holds its own uninstall (#377); the Google Chrome stand-in holds Chrome's per-profile caches (#566).
    private static let quitJourneyApps: [(env: String, name: String, bundleID: String, executable: String)] = [
        ("CACHEDROP_TEST_PREPARE_SYNTH_APP", "Synth", "com.maker.synth", "main"),
        ("CACHEDROP_TEST_PREPARE_CHROME_APP", "Google Chrome", "com.google.Chrome", "Google Chrome"),
    ]

    /// #383: only an opt-in journey's disposable fixture bundle (`quitJourneyApps`) is made launchable outside the sandboxed
    /// runner. The journey verifies the signature and launches it itself; preparation errors fail that test, never skip it.
    @MainActor static func prepareQuitJourney() throws {
        guard LocalStateLocation.isDisposableTest, let home = CatalogCleanupModel.home else { return }
        for fixture in quitJourneyApps where LocalStateLocation.fixtureEnvironment[fixture.env] == "1" {
            try prepare(fixture.name, bundleID: fixture.bundleID, executable: fixture.executable, in: home)
        }
    }

    /// Replaces the fixture bundle's executable with a copy of `sleep`, clears its quarantine and signs it, after checking that
    /// the bundle in the fixture home is exactly the one named, with no symlink on the way.
    @MainActor private static func prepare(_ name: String, bundleID: String, executable executableName: String, in home: URL) throws {
        _ = try LocalStateLocation.root(create: false)
        let bundle = home.appendingPathComponent("Applications/\(name).app")
        let contents = bundle.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let executable = macOS.appendingPathComponent(executableName)
        let info = contents.appendingPathComponent("Info.plist")
        let paths = [bundle, contents, macOS, executable, info]
        guard paths.allSatisfy({ $0.path == $0.resolvingSymlinksInPath().path }),
              let identity = NSDictionary(contentsOf: info),
              identity["CFBundleIdentifier"] as? String == bundleID,
              identity["CFBundleExecutable"] as? String == executableName else { throw CocoaError(.fileReadNoPermission) }
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
