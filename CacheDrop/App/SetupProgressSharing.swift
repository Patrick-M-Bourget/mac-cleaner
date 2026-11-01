import Darwin
import Foundation
import Observation
import SwiftUI
import CacheDropCore

/// Share setup progress (Decision 127): the toggle on Welcome and in Settings, and the hooks that record the three events.
@MainActor @Observable final class SetupProgressSharing {
    static let shared = SetupProgressSharing()
    static let title = "Share setup progress"
    static let explanation = "CacheDrop shares when you first open, scan and clean up, never what’s on this Mac."
    var binding: Binding<Bool> { Binding(get: { self.isSharing }, set: { self.setSharing($0) }) }
    private(set) var isSharing = false
    private let reporter: SetupProgressReporter

    private init() {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        let store = SetupProgressFileStore()
        isSharing = SetupProgressReporter.savedSharing(in: store) // No flash of "off" for someone who opted in.
        reporter = SetupProgressReporter(store: store, transport: Self.transport, appVersion: appVersion,
                                         macosVersion: SetupProgressPayload.macosVersion(ProcessInfo.processInfo.operatingSystemVersion))
    }

    /// Release sends to the site; Debug builds and test runs send nothing, so they never count as installs.
    private static var transport: SetupProgressTransport {
        #if DEBUG
        return OfflineSetupProgressTransport()
        #else
        return HTTPSetupProgressTransport(endpoint: URL(string: "https://cachedrop.io/api/telemetry")!)
        #endif
    }

    func setSharing(_ on: Bool) {
        isSharing = on
        Task { await reporter.setSharing(on); isSharing = await reporter.isSharing }
    }
    func record(_ event: SetupProgressEvent) { Task { await reporter.record(event) } }
    /// Sends what an earlier launch couldn't.
    func sendPending() { Task { await reporter.flush() } }
    /// Saved data's Reset.
    func reset() async throws {
        try await reporter.reset()
        isSharing = false
    }
}

/// `setup-progress.json` in CacheDrop's state folder, so Reset and test runs' isolated state cover it.
struct SetupProgressFileStore: SetupProgressStore {
    static let filename = "setup-progress.json"
    private func file(createRoot: Bool) throws -> URL {
        let url = try LocalStateLocation.root(create: createRoot).appendingPathComponent(Self.filename)
        var information = stat()
        if lstat(url.path, &information) == 0 {
            guard information.st_mode & S_IFMT == S_IFREG, information.st_uid == geteuid(),
                  information.st_size <= 4096, url.path == url.resolvingSymlinksInPath().path else { throw CocoaError(.fileReadNoPermission) }
        } else if errno != ENOENT { throw CocoaError(.fileReadUnknown) }
        return url
    }
    func load() throws -> SetupProgressState? {
        let url = try file(createRoot: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(SetupProgressState.self, from: Data(contentsOf: url))
    }
    func save(_ state: SetupProgressState) throws {
        try JSONEncoder().encode(state).write(to: file(createRoot: true), options: .atomic)
    }
    func remove() throws { try LocalStateLocation.removeKnownFile(Self.filename) }
}

/// One POST per event, with no cookies, cache or stored credentials.
struct HTTPSetupProgressTransport: SetupProgressTransport {
    let endpoint: URL
    func send(_ payload: SetupProgressPayload) async -> SetupProgressDelivery {
        guard let body = try? JSONEncoder().encode(payload) else { return .refused }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (_, response) = try? await session.data(for: request), let status = (response as? HTTPURLResponse)?.statusCode else { return .retryLater }
        return SetupProgressDelivery(status: status)
    }
}

#if DEBUG
/// Debug builds and test runs: nothing leaves the Mac, and events stay pending.
struct OfflineSetupProgressTransport: SetupProgressTransport {
    func send(_ payload: SetupProgressPayload) async -> SetupProgressDelivery { .retryLater }
}
#endif
