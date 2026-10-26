#if DEBUG
import Foundation
import Darwin
import StillCore

/// Explicit DEBUG-only public-boundary fixture. Never discovers or contacts installed Chrome.
enum ChromeCleanupFixture {
    @MainActor static func makeModel() -> ChromeCleanupModel? {
        guard ProcessInfo.processInfo.arguments.contains("--chrome-cleanup-fixture"), LocalStateLocation.isDisposableTest,
              let state = try? LocalStateLocation.root(create: false) else { return nil }
        let root = state.appendingPathComponent("ChromeFixture", isDirectory: true)
        guard (try? validate(root, state: state)) != nil else { return nil }
        let environment = Environment(state: state, root: root)
        let access = ChromeCacheAccess(applicationURL: root.appendingPathComponent("Google Chrome.app"),
            dataRootURL: root, cacheRootURL: root, customLocation: true)
        return ChromeCleanupModel(service: ChromeCacheService(environment: environment,
            journalURL: state.appendingPathComponent("chrome-cleanup.json")), access: access)
    }

    private static func validate(_ root: URL, state: URL) throws {
        guard try LocalStateLocation.root(create: false) == state,
              root == state.appendingPathComponent("ChromeFixture", isDirectory: true),
              root.path == root.resolvingSymlinksInPath().path else { throw CocoaError(.fileReadNoPermission) }
        var info = stat()
        guard lstat(root.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == geteuid(), info.st_mode & 0o022 == 0 else { throw CocoaError(.fileReadNoPermission) }
    }

    private struct Environment: ChromeCacheEnvironment {
        let state: URL
        let root: URL
        func now() -> Date { Date() }
        func validateInstallation(at url: URL) throws {
            try ChromeCleanupFixture.validate(root, state: state)
            guard url == root.appendingPathComponent("Google Chrome.app") else { throw CocoaError(.fileReadNoPermission) }
            switch try observation() {
            case "unsupported": throw ChromeCacheFailure("This Chrome or macOS version has not been qualified.", .unsupported)
            case "denied": throw ChromeCacheFailure("Chrome access was denied.", .denied)
            default: break
            }
        }
        func browserIsRunning(bundleURL: URL) throws -> Bool {
            try ChromeCleanupFixture.validate(root, state: state)
            guard bundleURL == root.appendingPathComponent("Google Chrome.app") else { throw CocoaError(.fileReadNoPermission) }
            let state = try observation()
            guard state != "unknown" else { throw ChromeCacheFailure("Browser activity could not be checked.", .unknown) }
            return state == "running"
        }
        private func observation() throws -> String {
            let file = root.appendingPathComponent("environment.txt")
            var info = stat()
            guard lstat(file.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                  info.st_uid == geteuid(), info.st_nlink == 1, info.st_size <= 32,
                  file.path == file.resolvingSymlinksInPath().path else { throw CocoaError(.fileReadNoPermission) }
            let value = try String(contentsOf: file, encoding: .utf8)
            guard ["closed", "running", "unsupported", "denied", "unknown"].contains(value) else { throw CocoaError(.fileReadCorruptFile) }
            return value
        }
    }
}
#endif
