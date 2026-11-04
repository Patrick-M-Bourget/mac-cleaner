import Foundation

/// Opt-in setup progress (Decision 127): what CacheDrop sends, only after the user ticks Share setup progress.
public enum SetupProgressEvent: String, Codable, CaseIterable, Sendable {
    case firstLaunch = "first_launch"
    case firstScanCompleted = "first_scan_completed"
    case firstCleanupCompleted = "first_cleanup_completed"
}

/// Everything one request carries. Nothing found on disk can be part of it: there is no field for it.
public struct SetupProgressPayload: Encodable, Equatable, Sendable {
    public let event: SetupProgressEvent
    public let installID: UUID
    public let appVersion: String
    public let macosVersion: String
    public init(event: SetupProgressEvent, installID: UUID, appVersion: String, macosVersion: String) {
        self.event = event; self.installID = installID; self.appVersion = appVersion; self.macosVersion = macosVersion
    }
    private enum CodingKeys: String, CodingKey { case event, installID = "installId", appVersion, macosVersion }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(event, forKey: .event)
        try container.encode(installID.uuidString.lowercased(), forKey: .installID)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(macosVersion, forKey: .macosVersion)
    }
    /// "26.1", or "26.1.2" when there is a patch version.
    public static func macosVersion(_ version: OperatingSystemVersion) -> String {
        let base = "\(version.majorVersion).\(version.minorVersion)"
        return version.patchVersion == 0 ? base : "\(base).\(version.patchVersion)"
    }
}

/// What the app remembers about setup progress. No install ID until the user first opts in; Reset removes it all.
public struct SetupProgressState: Codable, Equatable, Sendable {
    public var sharing = false
    public var installID: UUID?
    /// Recorded while sharing, oldest first, still to be sent.
    public var pending: [SetupProgressEvent] = []
    /// Sent, or refused by the endpoint: never sent again for this install ID.
    public var done: [SetupProgressEvent] = []
    public init() {}
    /// Pinned: `setup-progress.json` keeps these names across renames (#448).
    private enum CodingKeys: String, CodingKey { case sharing = "sharing", installID = "installID", pending = "pending", done = "done" }
}

public protocol SetupProgressStore: Sendable {
    func load() throws -> SetupProgressState?
    func save(_ state: SetupProgressState) throws
    func remove() throws
}

/// How one send ended.
public enum SetupProgressDelivery: Equatable, Sendable {
    /// Stored, or a repeat the endpoint already had.
    case accepted
    /// The endpoint refused it as invalid; sending it again can't help.
    case refused
    /// Offline, rate-limited or unavailable: try again on a later launch or event.
    case retryLater
    /// The endpoint's answer: 2xx is stored (a repeat too); 400 and 413 can't succeed by retrying; anything else waits.
    public init(status: Int) {
        switch status {
        case 200..<300: self = .accepted
        case 400, 413: self = .refused
        default: self = .retryLater
        }
    }
}

public protocol SetupProgressTransport: Sendable {
    func send(_ payload: SetupProgressPayload) async -> SetupProgressDelivery
}

/// Records and sends setup progress (Decision 127). Nothing is recorded or sent unless sharing is on. Each event is sent at
/// most once per install ID; failures stay pending and go quietly on a later call, never as an error.
public actor SetupProgressReporter {
    private let store: SetupProgressStore
    private let transport: SetupProgressTransport
    private let appVersion: String
    private let macosVersion: String
    private let makeInstallID: () -> UUID
    private var state: SetupProgressState
    private var sending = false

    public init(store: SetupProgressStore, transport: SetupProgressTransport, appVersion: String, macosVersion: String,
                makeInstallID: @escaping () -> UUID = UUID.init) {
        self.store = store; self.transport = transport; self.appVersion = appVersion; self.macosVersion = macosVersion
        self.makeInstallID = makeInstallID
        state = (try? store.load()) ?? SetupProgressState()
    }

    public var isSharing: Bool { state.sharing }
    /// The saved choice, read without waiting on the actor, for the toggles' first draw.
    public nonisolated static func savedSharing(in store: SetupProgressStore) -> Bool { (try? store.load())?.sharing ?? false }

    /// Ticking it records first launch for this launch; unticking it drops anything not yet sent.
    public func setSharing(_ on: Bool) async {
        guard on != state.sharing else { return }
        state.sharing = on
        if on {
            if state.installID == nil { state.installID = makeInstallID() }
            add(.firstLaunch)
        } else {
            state.pending = []
        }
        persist()
        if on { await flush() }
    }

    /// A milestone reached now. Ignored unless sharing is on, and once the event is pending or done.
    public func record(_ event: SetupProgressEvent) async {
        guard state.sharing, add(event) else { return }
        persist()
        await flush()
    }

    /// Sends what's pending, in order, stopping at the first that has to wait.
    public func flush() async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        while state.sharing, let installID = state.installID, let event = state.pending.first {
            let delivery = await transport.send(SetupProgressPayload(event: event, installID: installID, appVersion: appVersion, macosVersion: macosVersion))
            if case .retryLater = delivery { return }
            // Unticked, reset or ticked again while the request was out: that answer belongs to a state that's gone, so
            // carry on with whatever is pending now (a new first launch, say), which a call during the send couldn't start.
            guard state.sharing, state.installID == installID, state.pending.first == event else { continue }
            state.pending.removeFirst()
            state.done.append(event)
            persist()
        }
    }

    /// Saved data's Reset: forgets the choice, the install ID and every pending or sent event.
    public func reset() throws {
        try store.remove()
        state = SetupProgressState()
    }

    @discardableResult private func add(_ event: SetupProgressEvent) -> Bool {
        guard !state.pending.contains(event), !state.done.contains(event) else { return false }
        state.pending.append(event)
        return true
    }
    /// A failed save keeps the state in memory; the next change tries again.
    private func persist() { try? store.save(state) }
}
