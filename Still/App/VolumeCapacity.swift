import Darwin
import Foundation
import StillCore

/// Capacity-only metadata shared by presentation and optional alerts; never enumerates files.
struct StartupVolumeCapacity: Sendable {
    let available: Int64?
    let total: Int64?
    let volumeID: String?
    let metric: String
    let observedAt: Date
    static func read() -> Self {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeUUIDStringKey])
        let important = values?.volumeAvailableCapacityForImportantUsage
        return Self(available: important ?? values?.volumeAvailableCapacity.map(Int64.init), total: values?.volumeTotalCapacity.map(Int64.init), volumeID: values?.volumeUUIDString, metric: important == nil ? "available" : "important", observedAt: Date())
    }
}

@MainActor final class NativeCapacityRefreshSystem: CapacityRefreshSystem {
    var now: Date { Date() }
    func readStartupCapacity(_ completed: @escaping @MainActor @Sendable (StartupCapacityReading) -> Void) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-capacity-reading"), LocalStateLocation.isDisposableTest {
            let fixture = fixtureReading()
            Task {
                if let delay = fixture?.delayMilliseconds, delay > 0 {
                    try? await Task.sleep(for: .milliseconds(min(delay, 15_000)))
                }
                completed(StartupCapacityReading(available: fixture?.available, total: fixture?.total, volumeID: "owned-startup-fixture", metric: fixture?.metric ?? "important", observedAt: Date()))
            }
            return
        }
        #endif
        Task {
            let sample = await Task.detached(priority: .utility) { StartupVolumeCapacity.read() }.value
            completed(StartupCapacityReading(available: sample.available, total: sample.total, volumeID: sample.volumeID, metric: sample.metric, observedAt: sample.observedAt))
        }
    }
    #if DEBUG
    private struct Fixture: Decodable {
        let available: Int64?
        let total: Int64?
        let metric: String?
        let delayMilliseconds: Int?
    }
    private func fixtureReading() -> Fixture? {
        guard let root = try? LocalStateLocation.root(create: false) else { return nil }
        let file = root.appendingPathComponent("capacity-reading.json")
        var info = stat()
        guard lstat(file.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid(), info.st_size <= 4_096,
              file.path == file.resolvingSymlinksInPath().path,
              let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Fixture.self, from: data)
    }
    #endif
    func deadline(after seconds: TimeInterval, _ expired: @escaping @MainActor @Sendable () -> Void) -> () -> Void {
        let task = Task {
            do { try await Task.sleep(for: .seconds(seconds)); expired() }
            catch { /* Completed metadata reads cancel their one-shot deadline. */ }
        }
        return { task.cancel() }
    }
}

extension CapacityRefreshController {
    var observationText: String {
        guard let reading else { return isRefreshing ? "Checking capacity…" : "Capacity unavailable" }
        let prefix = failed ? "Last observed " : "Observed "
        let metric = reading.metric == "important" ? "Available for important usage" : "Available capacity fallback"
        return prefix + reading.observedAt.formatted() + " · " + metric
    }
    var statusText: String {
        if isRefreshing { return reading == nil ? "Checking capacity…" : "Refreshing…" }
        return failed ? "Couldn’t refresh capacity" : ""
    }
}
