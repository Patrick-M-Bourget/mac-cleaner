import Foundation
import Testing
import StorageAlerts

@MainActor private final class ControlledAlertSystem: AlertMonitoringSystem {
    let available = true
    var now = Date(timeIntervalSince1970: 1_000_000)
    var saved = AlertPolicy()
    var reading = AlertCapacityReading(available: 20_000_000_000, total: 512_000_000_000, volumeID: "owned", metric: "important")
    var holdNextAuthorization = false
    var held: CheckedContinuation<AlertPolicy.Authorization, Never>?
    let heldBegan = AsyncStream<Void>.makeStream()
    var pollers: [UUID: @MainActor () -> Void] = [:]
    var notifications = 0
    var reads = 0
    func authorization() async -> AlertPolicy.Authorization {
        if holdNextAuthorization {
            holdNextAuthorization = false
            return await withCheckedContinuation { continuation in
                held = continuation; heldBegan.continuation.yield(())
            }
        }
        return .allowed
    }
    func requestAuthorization() async throws -> Bool { true }
    func capacity() -> AlertCapacityReading { reads += 1; return reading }
    func load() throws -> AlertPolicy { saved }
    func save(_ policy: AlertPolicy) throws { saved = policy }
    func reset() throws { saved = AlertPolicy() }
    func startPolling(_ sample: @escaping @MainActor () -> Void) -> () -> Void {
        let id = UUID(); pollers[id] = sample
        return { self.pollers[id] = nil }
    }
    func removePendingNotification() {}
    func submitLowSpaceNotification(observedAt: Date) async throws { notifications += 1 }
}

@Test @MainActor func reEnablingDuringHeldSampleResumesMonitoringWithoutAnotherActivation() async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    await alerts.setEnabled(true)
    #expect(alerts.effectiveMonitoring)
    #expect(system.notifications == 1)
    system.now.addTimeInterval(900)
    system.holdNextAuthorization = true
    let oldActivation = Task { await alerts.activated() }
    var began = system.heldBegan.stream.makeAsyncIterator(); _ = await began.next()
    await alerts.setEnabled(false)
    #expect(!alerts.effectiveMonitoring)
    #expect(system.pollers.isEmpty)
    await alerts.setEnabled(true)
    #expect(alerts.effectiveMonitoring)
    #expect(system.pollers.count == 1)
    #expect(system.notifications == 1) // Same low episode stays suppressed.
    #expect(system.reads == 3) // Initial capacity, initial enable, renewed enable.
    system.held?.resume(returning: .denied); system.held = nil
    await oldActivation.value
    #expect(alerts.effectiveMonitoring)
    #expect(system.pollers.count == 1)
    #expect(system.notifications == 1)
    await alerts.setEnabled(false)
}

@Test @MainActor func capacityChangeInvalidatingThresholdStopsPolling() async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    await alerts.setEnabled(true)
    system.now.addTimeInterval(900)
    system.reading = AlertCapacityReading(available: 10_000_000_000, total: 30_000_000_000, volumeID: "replacement", metric: "important")
    await alerts.activated()
    #expect(!alerts.effectiveMonitoring)
    #expect(system.pollers.isEmpty)
    #expect(alerts.requested) // Preserve preference; the user can choose a valid threshold.
    #expect(system.notifications == 1)
    #expect(alerts.status == "Threshold no longer fits this volume. Update it to resume alerts.")
}

@Test @MainActor func terminationDuringHeldAuthorizationCannotRestartMonitoring() async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    await alerts.setEnabled(true)
    system.now.addTimeInterval(900)
    system.holdNextAuthorization = true
    let activation = Task { await alerts.activated() }
    var began = system.heldBegan.stream.makeAsyncIterator(); _ = await began.next()
    alerts.stopForTermination()
    system.held?.resume(returning: .allowed); system.held = nil
    await activation.value
    #expect(!alerts.effectiveMonitoring)
    #expect(system.pollers.isEmpty)
    #expect(alerts.requested) // Quit preserves saved preference and independent login intent.
    #expect(system.saved.enabled)
    #expect(system.notifications == 1)
}
