import Foundation
import Combine

public struct AlertCapacityReading: Sendable {
    public let available: Int64?
    public let total: Int64?
    public let volumeID: String?
    public let metric: String
    public init(available: Int64?, total: Int64?, volumeID: String?, metric: String) {
        self.available = available; self.total = total; self.volumeID = volumeID; self.metric = metric
    }
}

/// System operations only. Monitoring owns preference, suppression and lifecycle decisions.
@MainActor public protocol AlertMonitoringSystem: AnyObject {
    var available: Bool { get }
    var allowsNotificationChanges: Bool { get }
    var now: Date { get }
    func authorization() async -> AlertPolicy.Authorization
    func requestAuthorization() async throws -> Bool
    func capacity() -> AlertCapacityReading
    func load() throws -> AlertPolicy
    func save(_ policy: AlertPolicy) throws
    func reset() throws
    /// Returns cancellation for this one poller. Never wakes the machine.
    func startPolling(_ sample: @escaping @MainActor () -> Void) -> () -> Void
    func removePendingNotifications(identifiers: [String])
    func submitLowSpaceNotification(identifier: String, observedAt: Date) async throws
}

/// Presentation evidence only; lifecycle polling remains represented by effectiveMonitoring.
public enum AlertShellAttention: Equatable, Sendable {
    case savedStateUnavailable, saveFailed, notificationsUnavailable, capacityUnavailable, invalidThreshold, submissionFailed
}
public enum AlertShellState: Equatable, Sendable {
    case off, checking, on
    case snoozed(until: Date)
    case attention(AlertShellAttention)
}

@MainActor public class AlertMonitoringController: NSObject, ObservableObject {
    @Published public private(set) var shellState: AlertShellState = .off
    @Published public private(set) var effectiveMonitoring = false
    @Published public private(set) var requested = false
    @Published public private(set) var status = "Alerts are off."
    @Published public private(set) var total: Int64?
    @Published public var thresholdGB = "40"
    @Published public private(set) var appliedThresholdBytes: Int64 = 40_000_000_000
    @Published public private(set) var authorization: AlertPolicy.Authorization = .unknown
    @Published public private(set) var authorizationChecked = false
    @Published public private(set) var lastMonitoringCheck: Date?
    private var policy = AlertPolicy()
    private var cancelPolling: (() -> Void)?
    private var samplingGeneration: UUID?
    private var monitoringGeneration = UUID()
    private var authorizationGeneration = UUID()
    private let delivery = AlertDeliveryGate()
    private var terminating = false
    private var persistenceHealthy = true
    private var inFlightNotificationIDs = Set<String>()
    private let system: any AlertMonitoringSystem
    public init(system: any AlertMonitoringSystem) {
        self.system = system
        super.init()
        guard system.available, system.allowsNotificationChanges else { return }
        do {
            policy = try system.load()
            requested = policy.enabled
            appliedThresholdBytes = policy.thresholdBytes
            thresholdGB = String(Double(policy.thresholdBytes) / 1_000_000_000)
            if !requested && policy.thresholdBytes == 40_000_000_000 { thresholdGB = "40" }
            if requested { shellState = .checking; status = "Saved alert preference restored; checking authorization and capacity." }
        } catch {
            persistenceHealthy = false
            shellState = .attention(.savedStateUnavailable)
            status = "Alert state could not be read. Monitoring is stopped to preserve suppression."
        }
    }
    public var threshold: Int64? {
        guard let gb = Double(thresholdGB), gb.isFinite, gb >= 1, gb < Double(Int64.max) / 1_000_000_000 else { return nil }
        return Int64(gb * 1_000_000_000)
    }
    /// Editor validity controls Apply/opt-in; polling continues to use the last applied preference.
    public var thresholdValid: Bool { threshold.map { AlertPolicy.validThreshold($0, total: total) } ?? false }
    public var thresholdChanged: Bool { threshold != appliedThresholdBytes }
    public func thresholdValid(for capacity: Int64?) -> Bool {
        threshold.map { AlertPolicy.validThreshold($0, total: capacity) } ?? false
    }
    private var appliedThresholdValid: Bool { AlertPolicy.validThreshold(policy.thresholdBytes, total: total) }

    public func resetPreferences() throws {
        guard !terminating else { throw CocoaError(.userCancelled) }
        monitoringGeneration = UUID()
        authorizationGeneration = UUID()
        delivery.invalidate()
        pauseMonitoring()
        // Explicit global Reset must recover cancellation ownership even when monitoring is gated off.
        // Read before deleting state; an unreadable ownership record must not be silently discarded.
        if system.allowsNotificationChanges {
            do {
                let savedIdentifiers = try system.load().notificationRequestIdentifiers ?? []
                policy.notificationRequestIdentifiers = (policy.notificationRequestIdentifiers ?? []).union(savedIdentifiers)
            } catch {
                shellState = .attention(.savedStateUnavailable)
                status = "Alert state could not be read. Monitoring is stopped to preserve suppression."
                throw error
            }
        }
        removePendingNotifications()
        requested = false; policy = AlertPolicy(); thresholdGB = "40"; appliedThresholdBytes = policy.thresholdBytes; persistenceHealthy = true
        do { try system.reset() }
        catch {
            shellState = .attention(.saveFailed)
            status = "Alert preferences could not be reset. Monitoring is stopped; review local records before trying again."
            throw error
        }
        shellState = .off
        status = "Alerts are off."
    }
    /// Terminal for this app session. A new controller may restore the saved preference.
    public func stopForTermination() {
        terminating = true
        authorizationGeneration = UUID()
        pauseMonitoring()
        delivery.invalidate()
        let savedOwnership = !(policy.notificationRequestIdentifiers ?? []).isEmpty
        if requested || savedOwnership || !inFlightNotificationIDs.isEmpty { removePendingNotifications() }
        // Do not recreate state deleted by Reset merely because an obsolete attempt still awaits the OS.
        if savedOwnership { _ = persist() } // Preserve enabled intent and uncertain episode suppression.
    }
    private func pauseMonitoring() {
        monitoringGeneration = UUID()
        cancelPolling?(); cancelPolling = nil; effectiveMonitoring = false
    }
    public func configure() {
        guard system.available, !terminating else { return }
        total = capacity().total
        if requested { Task { await sample() } }
    }
    public func setEnabled(_ enabled: Bool) async {
        guard system.available, !terminating else { return }
        guard system.allowsNotificationChanges else { status = "Disposable tests do not change notification settings."; return }
        if enabled && !appliedThresholdValid { status = "Enter at least 1 GB and less than startup-volume capacity."; return }
        requested = enabled
        if enabled, shellState == .off { shellState = .checking }
        policy.enabled = enabled
        delivery.setEnabled(enabled)
        if !enabled {
            authorizationGeneration = UUID()
            monitoringGeneration = UUID()
            pauseMonitoring()
            removePendingNotifications()
        }
        guard persist() else { return }
        if !enabled { shellState = .off; status = "Alerts are off."; return }
        let enablingGeneration = monitoringGeneration
        guard let settings = await readAuthorization() else { return }
        guard requested, enablingGeneration == monitoringGeneration else { return }
        if settings == .unknown {
            status = "Allow notifications to receive low-space alerts."
            do { _ = try await system.requestAuthorization() }
            catch {
                guard requested, enablingGeneration == monitoringGeneration else { return }
                status = "Notification permission could not be requested."
            }
        }
        guard requested, enablingGeneration == monitoringGeneration else { return }
        await sample()
    }
    public func applyThreshold() async { await applyThreshold(validatingTotal: total) }
    public func applyThreshold(validatingTotal: Int64?) async {
        guard !terminating else { return }
        guard thresholdValid(for: validatingTotal), let threshold else { status = "Enter at least 1 GB and less than startup-volume capacity."; return }
        let previous = policy.thresholdBytes
        policy.thresholdBytes = threshold
        guard persist() else { policy.thresholdBytes = previous; return }
        appliedThresholdBytes = threshold
        if requested { await sample() }
    }
    public func activated() async {
        guard !terminating else { return }
        if requested { await sample() } else { await refreshAuthorization() }
    }
    private func refreshAuthorization() async {
        guard system.available, !terminating else { return }
        _ = await readAuthorization()
    }
    private func readAuthorization() async -> AlertPolicy.Authorization? {
        let generation = UUID(); authorizationGeneration = generation
        let settings = await system.authorization()
        guard !terminating, authorizationGeneration == generation else { return nil }
        authorization = settings; authorizationChecked = true
        return settings
    }
    private func persist() -> Bool {
        guard persistenceHealthy else { effectiveMonitoring = false; return false }
        do { try system.save(policy); return true }
        catch {
            persistenceHealthy = false; effectiveMonitoring = false
            cancelPolling?(); cancelPolling = nil
            shellState = .attention(.saveFailed)
            status = "Alert state could not be saved. Monitoring is stopped to prevent repeat notifications."
            return false
        }
    }
    public func remindLater() {
        guard !terminating else { return }
        guard requested, policy.canRemind else { status = "A valid capacity reading is required before snoozing."; return }
        policy.remindLater(at: system.now)
        guard persist() else { return }
        if case .attention = shellState {}
        else { shellState = .snoozed(until: system.now.addingTimeInterval(86_400)) }
        status = "Alerts snoozed for 24 hours. A valid low reading after resumption permits one reminder."
    }
    private func removePendingNotifications() {
        var identifiers = inFlightNotificationIDs.union(policy.notificationRequestIdentifiers ?? [])
        identifiers.insert("Still.lowSpace") // Previous versions used this fixed identifier.
        system.removePendingNotifications(identifiers: Array(identifiers))
        policy.notificationRequestIdentifiers = nil
    }
    private func capacity() -> AlertCapacityReading { system.capacity() }
    private func sample() async {
        let generation = monitoringGeneration
        guard system.available, !terminating, persistenceHealthy, requested, samplingGeneration != generation else { return }
        samplingGeneration = generation
        defer { if samplingGeneration == generation { samplingGeneration = nil } }
        guard let settings = await readAuthorization() else { return }
        guard requested, generation == monitoringGeneration else { return }
        guard settings == .allowed else {
            cancelPolling?(); cancelPolling = nil; effectiveMonitoring = false
            shellState = .attention(.notificationsUnavailable)
            status = "Notifications are unavailable. Enable Still alerts in System Settings > Notifications. Capacity polling is stopped."
            return
        }
        effectiveMonitoring = appliedThresholdValid
        if cancelPolling == nil {
            cancelPolling = system.startPolling { [weak self] in
                Task { @MainActor [weak self] in await self?.sample() }
            }
        }
        guard policy.shouldSample(at: system.now, authorization: .allowed) else { return }
        let reading = capacity(); total = reading.total; lastMonitoringCheck = system.now
        guard let available = reading.available, let total = reading.total, let volumeID = reading.volumeID else { shellState = .attention(.capacityUnavailable); status = "Capacity unavailable. Alert decisions are paused."; return }
        let validCapacity = available >= 0 && total > 0 && available <= total && !volumeID.isEmpty && !reading.metric.isEmpty
        guard appliedThresholdValid else {
            cancelPolling?(); cancelPolling = nil; effectiveMonitoring = false
            shellState = .attention(validCapacity ? .invalidThreshold : .capacityUnavailable)
            status = validCapacity ? "Threshold no longer fits this volume. Update it to resume alerts." : "Capacity unavailable. Alert decisions are paused."
            return
        }
        effectiveMonitoring = true
        if !validCapacity { shellState = .attention(.capacityUnavailable) }
        else if shellState != .attention(.submissionFailed) || available >= policy.thresholdBytes {
            shellState = policy.snoozedUntil.flatMap { $0 > system.now ? .snoozed(until: $0) : nil } ?? .on
        }
        status = validCapacity ? "Monitoring startup-volume capacity while Still runs. Last available: \(String(format: "%.1f", Double(available) / 1_000_000_000)) GB." : "Capacity unavailable. Alert decisions are paused."
        let submit = policy.observe(available: available, total: total, at: system.now, volumeID: volumeID, metric: reading.metric)
        let notificationID = submit ? "Still.lowSpace." + UUID().uuidString : nil
        if let notificationID {
            var identifiers = policy.notificationRequestIdentifiers ?? []
            identifiers.insert(notificationID)
            policy.notificationRequestIdentifiers = identifiers
        }
        // Persist the exact cancellation identity with intent before handing the request to the OS.
        guard persist() else { return }
        if let until = policy.snoozedUntil, until > system.now { status += " Snoozed until \(until.formatted())." }
        guard submit, let reservation = policy.pendingSubmission, let notificationID else { return }
        inFlightNotificationIDs.insert(notificationID)
        let deliveryResult = await delivery.submit {
            try await self.system.submitLowSpaceNotification(identifier: notificationID, observedAt: self.system.now)
        }
        inFlightNotificationIDs.remove(notificationID)
        let changed = policy.reconcileSubmission(deliveryResult, reservation: reservation, at: system.now)
        let previouslyOwned = policy.notificationRequestIdentifiers
        switch deliveryResult {
        case .staleSuccess:
            system.removePendingNotifications(identifiers: [notificationID])
            policy.notificationRequestIdentifiers?.remove(notificationID)
        case .accepted:
            if generation == monitoringGeneration, requested {
                shellState = policy.snoozedUntil.flatMap { $0 > system.now ? .snoozed(until: $0) : nil } ?? .on
            }
            let retained = inFlightNotificationIDs.union([notificationID])
            let retired = (policy.notificationRequestIdentifiers ?? []).subtracting(retained)
            if !retired.isEmpty { system.removePendingNotifications(identifiers: Array(retired)) }
            policy.notificationRequestIdentifiers = retained
        case .failed, .staleFailure:
            policy.notificationRequestIdentifiers?.remove(notificationID)
        }
        if changed || previouslyOwned != policy.notificationRequestIdentifiers { _ = persist() }
        if deliveryResult == .failed && changed {
            if persistenceHealthy { shellState = .attention(.submissionFailed) }
            status = "Notification could not be submitted. A later capacity check will retry."
        }
    }
}
