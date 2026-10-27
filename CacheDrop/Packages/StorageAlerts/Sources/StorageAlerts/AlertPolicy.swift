import Foundation

public struct AlertSubmissionReservation: Sendable, Equatable {
    fileprivate let id: UUID
    fileprivate let volumeID: String
}

public struct AlertPolicy: Sendable, Codable {
    public enum Authorization: Sendable { case allowed, denied, unknown }
    public var enabled = false {
        didSet {
            if !enabled {
                for key in episodes.keys { episodes[key]?.snoozeUntil = nil; episodes[key]?.reminderPending = false }
            }
        }
    }
    /// Optional so records from before per-submission ownership decode without resetting suppression.
    public var notificationRequestIdentifiers: Set<String>?
    public var thresholdBytes: Int64 = 40_000_000_000
    private struct Episode: Sendable, Codable {
        var suppressed = false
        var reserved = false
        var reservationID: UUID?
        var recoveryBytes: Int64 = 0
        var snoozeUntil: Date?
        var reminderPending = false
        var lastAttempt: Date?
        var acceptedAt: Date?
    }
    private var episodes: [String: Episode] = [:]
    private var currentVolume: String?
    private var currentMetric: String?
    private var lastSample: Date?
    public init() {}
    public var pendingSubmission: AlertSubmissionReservation? {
        guard let volume = currentVolume, let episode = episodes[volume], episode.reserved, let id = episode.reservationID else { return nil }
        return AlertSubmissionReservation(id: id, volumeID: volume)
    }
    public var canRemind: Bool { currentVolume != nil }
    public var snoozedUntil: Date? { currentVolume.flatMap { episodes[$0]?.snoozeUntil } }
    public mutating func shouldSample(at date: Date, authorization: Authorization) -> Bool {
        guard enabled, authorization == .allowed else { return false }
        if let lastSample, date.timeIntervalSince(lastSample) < 60 { return false }
        lastSample = date; return true
    }
    public static func validThreshold(_ value: Int64, total: Int64?) -> Bool {
        guard let total else { return false }
        return value >= 1_000_000_000 && value < total
    }
    public mutating func observe(available: Int64?, total: Int64?, at date: Date = Date(), volumeID: String = "startup", metric: String = "important") -> Bool {
        guard enabled, let available, let total, available >= 0, available <= total,
              !volumeID.isEmpty, !metric.isEmpty, Self.validThreshold(thresholdBytes, total: total) else { return false }
        let changedVolume = currentVolume != nil && currentVolume != volumeID
        let changedMetric = currentMetric != nil && currentMetric != metric
        currentVolume = volumeID; currentMetric = metric
        if changedVolume || changedMetric { return false }
        var episode = episodes[volumeID] ?? Episode()
        let recovery = thresholdBytes + min(total - thresholdBytes, 5_000_000_000)
        episode.recoveryBytes = max(episode.recoveryBytes, recovery)
        if available >= min(total, episode.recoveryBytes) {
            episodes[volumeID] = Episode()
            return false
        }
        guard available < thresholdBytes else { episodes[volumeID] = episode; return false }
        if let until = episode.snoozeUntil, date < until { episodes[volumeID] = episode; return false }
        guard !episode.reserved, (!episode.suppressed || episode.reminderPending) else { episodes[volumeID] = episode; return false }
        if let last = episode.lastAttempt, date.timeIntervalSince(last) < 900 { episodes[volumeID] = episode; return false }
        episode.reserved = true; episode.reservationID = UUID(); episode.lastAttempt = date
        episodes[volumeID] = episode
        return true
    }
    /// Completes only the exact still-owned reservation; reset/recovery/new attempts cannot be modified.
    @discardableResult public mutating func reconcileSubmission(_ result: AlertDeliveryResult, reservation: AlertSubmissionReservation, at date: Date = Date()) -> Bool {
        guard var episode = episodes[reservation.volumeID], episode.reserved, episode.reservationID == reservation.id else { return false }
        switch result {
        case .accepted, .staleSuccess:
            episode.suppressed = true; episode.acceptedAt = date
            episode.snoozeUntil = nil; episode.reminderPending = false
        case .failed, .staleFailure: break
        }
        episode.reserved = false; episode.reservationID = nil
        episodes[reservation.volumeID] = episode
        return true
    }
    public mutating func submissionAccepted(at date: Date = Date()) {
        guard let key = currentVolume, var episode = episodes[key] else { return }
        episode.reserved = false; episode.reservationID = nil; episode.suppressed = true; episode.acceptedAt = date
        episode.snoozeUntil = nil; episode.reminderPending = false
        episodes[key] = episode
    }
    public mutating func submissionFailed() {
        guard let key = currentVolume else { return }
        episodes[key]?.reserved = false
        episodes[key]?.reservationID = nil
    }
    /// A reservation found after a restart is uncertain, so suppress rather than replay.
    public mutating func reconcileAfterRestart() {
        for key in episodes.keys where episodes[key]?.reserved == true {
            episodes[key]?.reserved = false; episodes[key]?.reservationID = nil; episodes[key]?.suppressed = true
            episodes[key]?.reminderPending = false
        }
    }
    public mutating func remindLater(at date: Date) {
        guard enabled, let key = currentVolume else { return }
        var episode = episodes[key] ?? Episode()
        episode.snoozeUntil = date.addingTimeInterval(86_400)
        episode.reminderPending = true; episode.suppressed = true; episode.reserved = false; episode.reservationID = nil
        episodes[key] = episode
    }
}

/// A separate durable record: history clearing cannot remove alert suppression.
public struct AlertStateStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> AlertPolicy {
        guard FileManager.default.fileExists(atPath: url.path) else { return AlertPolicy() }
        var state = try JSONDecoder().decode(AlertPolicy.self, from: Data(contentsOf: url))
        state.reconcileAfterRestart()
        return state
    }
    public func save(_ state: AlertPolicy) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}

/// The observation attached to an opened alert, independent of current capacity.
public struct AlertOpenContext: Sendable, Equatable {
    public let observedAt: Date?
    /// The user-info key the observation is delivered under, and the one alerts delivered before #150 used.
    static let observedAtKey = "CacheDrop.observedAt", legacyObservedAtKey = "Still.observedAt"
    public init(observedAt: Date) { self.init(notificationUserInfo: [Self.observedAtKey: observedAt.timeIntervalSince1970]) }
    public init(notificationUserInfo: [AnyHashable: Any]) {
        // An alert delivered before #150 carries it under Still's key.
        guard let seconds = (notificationUserInfo[Self.observedAtKey] ?? notificationUserInfo[Self.legacyObservedAtKey]) as? Double, seconds.isFinite, seconds >= 0, seconds < 253_402_300_800 else { observedAt = nil; return }
        observedAt = Date(timeIntervalSince1970: seconds)
    }
    public var notificationUserInfo: [AnyHashable: Any] {
        observedAt.map { [Self.observedAtKey: $0.timeIntervalSince1970] } ?? [:]
    }
}
