import Foundation
import Observation

public struct StartupCapacityReading: Sendable, Equatable {
    public let available: Int64?
    public let total: Int64?
    public let volumeID: String?
    public let metric: String
    public let observedAt: Date
    public init(available: Int64?, total: Int64?, volumeID: String?, metric: String, observedAt: Date) {
        self.available = available; self.total = total; self.volumeID = volumeID; self.metric = metric; self.observedAt = observedAt
    }
}

/// Only startup-volume metadata and time. It never scans or changes alert preferences.
@MainActor public protocol CapacityRefreshSystem: AnyObject {
    var now: Date { get }
    func readStartupCapacity(_ completed: @escaping @MainActor @Sendable (StartupCapacityReading) -> Void)
    func deadline(after seconds: TimeInterval, _ expired: @escaping @MainActor @Sendable () -> Void) -> () -> Void
}

@MainActor @Observable public final class CapacityRefreshController {
    public enum Trigger: Sendable { case launch, foreground, manual, alertOpened, scanEnded, cleanupEnded }
    public private(set) var reading: StartupCapacityReading?
    public private(set) var isRefreshing = false
    public private(set) var failed = false
    public private(set) var attemptedAt: Date?
    @ObservationIgnored private var cancelDeadline: (() -> Void)?
    @ObservationIgnored private var current: UUID?
    @ObservationIgnored private var trailing = false
    @ObservationIgnored private var launched = false
    @ObservationIgnored private let system: any CapacityRefreshSystem
    public init(system: any CapacityRefreshSystem) { self.system = system }
    public func request(_ trigger: Trigger) {
        if trigger == .launch { guard !launched else { return }; launched = true }
        if trigger == .foreground, !failed, let reading, system.now.timeIntervalSince(reading.observedAt) < 30 { return }
        if isRefreshing {
            if trigger == .scanEnded || trigger == .cleanupEnded { trailing = true }
            return
        }
        begin()
    }
    private func begin() {
        let token = UUID(); current = token
        isRefreshing = true; attemptedAt = system.now
        cancelDeadline = system.deadline(after: 10) { [weak self] in
            guard let self, self.current == token else { return }
            self.current = nil; self.cancelDeadline = nil
            self.isRefreshing = false; self.failed = true
            if self.trailing { self.trailing = false; self.begin() }
        }
        system.readStartupCapacity { [weak self] reading in
            guard let self, self.current == token else { return }
            self.current = nil; self.cancelDeadline?(); self.cancelDeadline = nil; self.isRefreshing = false
            defer { if self.trailing { self.trailing = false; self.begin() } }
            let total = reading.total.flatMap { $0 > 0 ? $0 : nil }
            guard let available = reading.available, available >= 0, total.map({ available <= $0 }) ?? true else {
                self.failed = true; return
            }
            self.reading = StartupCapacityReading(available: available, total: total, volumeID: reading.volumeID, metric: reading.metric, observedAt: reading.observedAt)
            self.failed = false
        }
    }
}
