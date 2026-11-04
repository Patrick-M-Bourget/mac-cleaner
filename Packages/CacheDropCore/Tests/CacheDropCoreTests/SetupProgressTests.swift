import Foundation
import Testing
import CacheDropCore

// Decision 127: opt-in setup progress. Three events, each sent at most once per install ID, only after the user ticks
// Share setup progress; nothing read from disk is ever part of one.

private let install = UUID(uuidString: "3F0C6B1E-8A2D-4C7E-9B1A-2D4E6F8A0B1C")!

@Test func setupProgressPayloadCarriesOnlyItsFourFields() throws {
    let payload = SetupProgressPayload(event: .firstScanCompleted, installID: install, appVersion: "0.9.6", macosVersion: "26.1")
    let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: String])
    #expect(json == ["event": "first_scan_completed", "installId": "3f0c6b1e-8a2d-4c7e-9b1a-2d4e6f8a0b1c",
                     "appVersion": "0.9.6", "macosVersion": "26.1"])
}

@Test func setupProgressMacOSVersionLeavesOutAZeroPatch() {
    #expect(SetupProgressPayload.macosVersion(OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)) == "26.1")
    #expect(SetupProgressPayload.macosVersion(OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 2)) == "26.1.2")
}

/// Keeps the saved state in memory, like the app's file in the state folder.
private final class MemorySetupProgressStore: SetupProgressStore, @unchecked Sendable {
    var saved: SetupProgressState?
    func load() throws -> SetupProgressState? { saved }
    func save(_ state: SetupProgressState) throws { saved = state }
    func remove() throws { saved = nil }
}

/// The endpoint as the reporter sees it: records each payload and answers with `next`.
private actor RecordingTransport: SetupProgressTransport {
    private(set) var sent: [SetupProgressPayload] = []
    var next = SetupProgressDelivery.accepted
    func answer(_ delivery: SetupProgressDelivery) { next = delivery }
    func send(_ payload: SetupProgressPayload) async -> SetupProgressDelivery { sent.append(payload); return next }
    var events: [SetupProgressEvent] { sent.map(\.event) }
}

private func reporter(_ store: MemorySetupProgressStore, _ transport: RecordingTransport, ids: [UUID] = [install]) -> SetupProgressReporter {
    var remaining = ids
    return SetupProgressReporter(store: store, transport: transport, appVersion: "0.9.6", macosVersion: "26.1",
                                 makeInstallID: { remaining.isEmpty ? UUID() : remaining.removeFirst() })
}

@Test func setupProgressSendsNothingAndKeepsNothingBeforeOptIn() async {
    let store = MemorySetupProgressStore(), transport = RecordingTransport()
    let progress = reporter(store, transport)
    await progress.record(.firstScanCompleted)
    await progress.record(.firstCleanupCompleted)
    #expect(await transport.sent.isEmpty)
    #expect(store.saved == nil)
    #expect(await progress.isSharing == false)
}

@Test func setupProgressOptInSendsFirstLaunchAndEachEventOnce() async {
    let store = MemorySetupProgressStore(), transport = RecordingTransport()
    let progress = reporter(store, transport)
    await progress.record(.firstScanCompleted) // Before the opt-in: never reported.
    await progress.setSharing(true)
    await progress.record(.firstCleanupCompleted)
    await progress.record(.firstCleanupCompleted)
    await progress.setSharing(true)
    #expect(await transport.events == [.firstLaunch, .firstCleanupCompleted])
    #expect(await transport.sent.allSatisfy { $0.installID == install && $0.appVersion == "0.9.6" && $0.macosVersion == "26.1" })
    #expect(await progress.isSharing)
}

@Test func setupProgressKeepsAnEventThatCouldNotGoAndSendsItLater() async {
    let store = MemorySetupProgressStore(), transport = RecordingTransport()
    await transport.answer(.retryLater)
    let progress = reporter(store, transport)
    await progress.setSharing(true)
    await progress.record(.firstScanCompleted) // Waits behind first launch, in order.
    #expect(store.saved?.pending == [.firstLaunch, .firstScanCompleted])
    await transport.answer(.accepted)
    // A later launch: a new reporter reads the saved state and sends both.
    let relaunched = reporter(store, transport)
    await relaunched.flush()
    #expect(await transport.events == [.firstLaunch, .firstLaunch, .firstLaunch, .firstScanCompleted])
    #expect(store.saved?.pending == [])
    #expect(store.saved?.done == [.firstLaunch, .firstScanCompleted])
}

@Test func setupProgressDropsAnEventTheEndpointRefuses() async {
    let store = MemorySetupProgressStore(), transport = RecordingTransport()
    await transport.answer(.refused)
    let progress = reporter(store, transport)
    await progress.setSharing(true)
    await progress.flush()
    #expect(await transport.events == [.firstLaunch])
    #expect(store.saved?.pending == [])
}

@Test func setupProgressUntickingDropsWhatIsPendingAndStopsSending() async {
    let store = MemorySetupProgressStore(), transport = RecordingTransport()
    await transport.answer(.retryLater)
    let progress = reporter(store, transport)
    await progress.setSharing(true)
    await progress.setSharing(false)
    await progress.record(.firstScanCompleted)
    await transport.answer(.accepted)
    await progress.flush()
    #expect(await transport.events == [.firstLaunch])
    #expect(store.saved?.sharing == false)
    #expect(store.saved?.pending == [])
}

@Test func setupProgressTickingAgainKeepsTheInstallIDAndNeverResendsAnEvent() async {
    let store = MemorySetupProgressStore(), transport = RecordingTransport()
    let other = UUID()
    let progress = reporter(store, transport, ids: [install, other])
    await progress.setSharing(true)
    await progress.setSharing(false)
    await progress.setSharing(true)
    #expect(await transport.events == [.firstLaunch])
    #expect(store.saved?.installID == install)
}

@Test func setupProgressResetStartsAgainAsANewInstallID() async throws {
    let store = MemorySetupProgressStore(), transport = RecordingTransport()
    let other = UUID()
    let progress = reporter(store, transport, ids: [install, other])
    await progress.setSharing(true)
    try await progress.reset()
    #expect(store.saved == nil)
    #expect(await progress.isSharing == false)
    await progress.setSharing(true)
    #expect(await transport.sent.map(\.installID) == [install, other])
}

@Test func setupProgressDeliveryFollowsTheEndpointsAnswer() {
    #expect(SetupProgressDelivery(status: 204) == .accepted)
    #expect(SetupProgressDelivery(status: 400) == .refused)
    #expect(SetupProgressDelivery(status: 413) == .refused)
    #expect(SetupProgressDelivery(status: 429) == .retryLater)
    #expect(SetupProgressDelivery(status: 503) == .retryLater)
    #expect(SetupProgressDelivery(status: 301) == .retryLater)
}

/// Holds each send until the test releases it, to change the choice while a request is out.
private actor GatedTransport: SetupProgressTransport {
    private(set) var sent: [SetupProgressPayload] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func send(_ payload: SetupProgressPayload) async -> SetupProgressDelivery {
        sent.append(payload)
        await withCheckedContinuation { waiting.append($0) }
        return .accepted
    }
    func releaseAll() { let held = waiting; waiting = []; held.forEach { $0.resume() } }
    var holding: Int { waiting.count }
}

@Test func setupProgressResetAndTickAgainWhileASendIsOutSendsTheNewFirstLaunch() async throws {
    let store = MemorySetupProgressStore(), transport = GatedTransport()
    let other = UUID()
    var ids = [install, other]
    let progress = SetupProgressReporter(store: store, transport: transport, appVersion: "0.9.6", macosVersion: "26.1",
                                         makeInstallID: { ids.removeFirst() })
    let first = Task { await progress.setSharing(true) }
    while await transport.holding == 0 { await Task.yield() }
    try await progress.reset()
    await progress.setSharing(true) // Returns at once: the first send is still out.
    let releaser = Task { while !Task.isCancelled { await transport.releaseAll(); await Task.yield() } }
    await first.value
    releaser.cancel()
    #expect(await transport.sent.map(\.installID) == [install, other])
    #expect(store.saved?.done == [.firstLaunch])
    #expect(store.saved?.installID == other)
}
