import Foundation
import Testing
import StorageAlerts

@MainActor private final class ControlledAlertSystem: AlertMonitoringSystem {
    var available = true
    let allowsNotificationChanges = true
    var now = Date(timeIntervalSince1970: 1_000_000)
    var saved = AlertPolicy()
    var reading = AlertCapacityReading(available: 20_000_000_000, total: 512_000_000_000, volumeID: "owned", metric: "important")
    var holdNextAuthorization = false
    var held: CheckedContinuation<AlertPolicy.Authorization, Never>?
    let heldBegan = AsyncStream<Void>.makeStream()
    var pollers: [UUID: @MainActor () -> Void] = [:]
    var notifications = 0
    var permissionRequests = 0
    var permission: AlertPolicy.Authorization = .allowed
    var stateUnreadable = false
    var saveFails = false
    var resetFails = false
    var submissionFails = false
    var holdNextSubmission = false
    var heldSubmission: CheckedContinuation<Void, Never>?
    let submissionBegan = AsyncStream<Void>.makeStream()
    var pendingNotifications: [String: Date] = [:]
    func authorization() async -> AlertPolicy.Authorization {
        if holdNextAuthorization {
            holdNextAuthorization = false
            return await withCheckedContinuation { continuation in
                held = continuation; heldBegan.continuation.yield(())
            }
        }
        return permission
    }
    func afterAbruptProcessExit() -> ControlledAlertSystem {
        pollers.removeAll()
        let restarted = ControlledAlertSystem()
        restarted.saved = saved; restarted.pendingNotifications = pendingNotifications
        restarted.now = now; restarted.reading = reading; restarted.notifications = notifications
        return restarted
    }
    func requestAuthorization() async throws -> Bool { permissionRequests += 1; return true }
    func capacity() -> AlertCapacityReading { reading }
    func load() throws -> AlertPolicy {
        if stateUnreadable { throw CocoaError(.fileReadCorruptFile) }
        return try JSONDecoder().decode(AlertPolicy.self, from: JSONEncoder().encode(saved))
    }
    func save(_ policy: AlertPolicy) throws { if saveFails { throw CocoaError(.fileWriteUnknown) }; saved = policy }
    func reset() throws { if resetFails { throw CocoaError(.fileWriteUnknown) }; saved = AlertPolicy() }
    func startPolling(_ sample: @escaping @MainActor () -> Void) -> () -> Void {
        let id = UUID(); pollers[id] = sample
        return { self.pollers[id] = nil }
    }
    func removePendingNotifications(identifiers: [String]) {
        for identifier in identifiers { pendingNotifications[identifier] = nil }
    }
    func submitLowSpaceNotification(identifier: String, observedAt: Date) async throws {
        notifications += 1
        if holdNextSubmission {
            holdNextSubmission = false
            await withCheckedContinuation { continuation in
                heldSubmission = continuation; submissionBegan.continuation.yield(())
            }
        }
        if submissionFails { throw CocoaError(.fileWriteUnknown) }
        pendingNotifications[identifier] = observedAt
    }
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
    system.reading = AlertCapacityReading(available: 20_000_000_000, total: 256_000_000_000, volumeID: "owned", metric: "important")
    await alerts.setEnabled(true)
    #expect(alerts.effectiveMonitoring)
    #expect(alerts.total == 256_000_000_000)
    #expect(system.pollers.count == 1)
    #expect(system.notifications == 1) // Same low episode stays suppressed.
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

@Test @MainActor func staleSubmissionCannotRemoveFreshRecoveredEpisodeNotification() async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    system.holdNextSubmission = true
    system.pendingNotifications["Still.lowSpace"] = system.now // Legacy fixed-ID request.
    let oldEnable = Task { await alerts.setEnabled(true) }
    var began = system.submissionBegan.stream.makeAsyncIterator(); _ = await began.next()
    await alerts.setEnabled(false)
    #expect(system.pendingNotifications.isEmpty)
    await alerts.setEnabled(true)
    system.now.addTimeInterval(900)
    system.reading = AlertCapacityReading(available: 60_000_000_000, total: 512_000_000_000, volumeID: "owned", metric: "important")
    await alerts.activated() // Genuine recovery rearms the episode.
    system.now.addTimeInterval(900)
    system.reading = AlertCapacityReading(available: 20_000_000_000, total: 512_000_000_000, volumeID: "owned", metric: "important")
    await alerts.activated()
    let freshObservation = system.now
    #expect(Array(system.pendingNotifications.values) == [freshObservation])
    system.heldSubmission?.resume(); system.heldSubmission = nil
    await oldEnable.value
    #expect(Array(system.pendingNotifications.values) == [freshObservation])
    #expect(alerts.effectiveMonitoring)
    #expect(system.pollers.count == 1)
    system.now.addTimeInterval(900)
    await alerts.activated()
    #expect(system.notifications == 2) // Fresh episode remains accepted, not replayed.
    await alerts.setEnabled(false)
    #expect(system.pendingNotifications.isEmpty)
}

@Test(arguments: [false, true]) @MainActor func restartRetainsOwnershipForOptOutAndReset(reset: Bool) async throws {
    var system = ControlledAlertSystem()
    let original = AlertMonitoringController(system: system)
    original.configure()
    await original.setEnabled(true)
    #expect(system.pendingNotifications.count == 1)
    // Simulate abrupt process exit: the OS stops its timers but retains accepted pending work.
    // Calling graceful stopForTermination here would itself cancel the pending request.
    system = system.afterAbruptProcessExit()
    #expect(system.pendingNotifications.count == 1)
    let restarted = AlertMonitoringController(system: system)
    if reset { try restarted.resetPreferences() }
    else { await restarted.setEnabled(false) }
    #expect(system.pendingNotifications.isEmpty)
    #expect(!restarted.requested)
    #expect(!restarted.effectiveMonitoring)
    #expect(system.pollers.isEmpty)
}

@Test func legacyAlertRecordRetainsSuppressionWithoutNotificationIdentityField() throws {
    // Recorded pre-ownership schema: an accepted, still-low episode must not become a new alert.
    let record = Data(#"{"enabled":true,"thresholdBytes":40000000000,"episodes":{"owned":{"suppressed":true,"reserved":false,"recoveryBytes":45000000000,"reminderPending":false}},"currentVolume":"owned","currentMetric":"important"}"#.utf8)
    var restored = try JSONDecoder().decode(AlertPolicy.self, from: record)
    #expect(restored.enabled)
    let submits = restored.observe(available: 20_000_000_000, total: 512_000_000_000, at: Date(timeIntervalSince1970: 1_000_000), volumeID: "owned", metric: "important")
    #expect(!submits)
}

@Test @MainActor func acceptedQuitCannotBeUndoneByActivationOrPreferenceActionsInSameSession() async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    await alerts.setEnabled(true)
    alerts.stopForTermination()
    await alerts.activated()
    alerts.configure()
    await alerts.setEnabled(true)
    await alerts.applyThreshold()
    await Task.yield()
    #expect(!alerts.effectiveMonitoring)
    #expect(system.pollers.isEmpty)
    #expect(alerts.requested)
    #expect(system.saved.enabled)
    #expect(system.notifications == 1)
}

@Test @MainActor func unappliedThresholdEditingDoesNotChangeEffectiveMonitoring() async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    await alerts.setEnabled(true)
    alerts.thresholdGB = ""
    system.now.addTimeInterval(900)
    await alerts.activated()
    #expect(alerts.effectiveMonitoring)
    #expect(system.pollers.count == 1)
    #expect(system.saved.thresholdBytes == 40_000_000_000)
    #expect(system.notifications == 1)
    alerts.thresholdGB = "80"
    system.now.addTimeInterval(900)
    await alerts.activated()
    #expect(alerts.effectiveMonitoring)
    #expect(system.saved.thresholdBytes == 40_000_000_000)
    #expect(system.notifications == 1)
    await alerts.applyThreshold()
    #expect(system.saved.thresholdBytes == 80_000_000_000)
    #expect(alerts.effectiveMonitoring)
    #expect(system.pollers.count == 1)
    #expect(system.notifications == 1) // Applying an edit cannot bypass ongoing-episode suppression.
    await alerts.setEnabled(false)
}

@Test @MainActor func acceptedQuitCancelsUnfinishedNotificationWithoutReplayingEpisode() async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    system.holdNextSubmission = true
    let enabling = Task { await alerts.setEnabled(true) }
    var began = system.submissionBegan.stream.makeAsyncIterator(); _ = await began.next()
    alerts.stopForTermination()
    system.heldSubmission?.resume(); system.heldSubmission = nil
    await enabling.value
    #expect(system.pendingNotifications.isEmpty)
    #expect(!alerts.effectiveMonitoring)
    #expect(system.pollers.isEmpty)
    #expect(system.saved.enabled)
    let restarted = AlertMonitoringController(system: system)
    restarted.configure()
    system.now.addTimeInterval(900)
    await restarted.activated()
    #expect(system.notifications == 1) // Uncertain/accepted old submission does not replay.
    await restarted.setEnabled(false)
}

@Test @MainActor func resetWhileFeatureHiddenRemovesPriorProcessOwnedRequestWithoutStartingMonitoring() async throws {
    var system = ControlledAlertSystem()
    let original = AlertMonitoringController(system: system)
    original.configure()
    await original.setEnabled(true)
    #expect(system.pendingNotifications.count == 1)
    system = system.afterAbruptProcessExit() // Abrupt exit retains prior-process pending requests.
    system.pendingNotifications["unrelated"] = system.now
    system.available = false
    let restarted = AlertMonitoringController(system: system)
    try restarted.resetPreferences()
    #expect(Set(system.pendingNotifications.keys) == ["unrelated"])
    #expect(!system.saved.enabled)
    #expect(system.saved.notificationRequestIdentifiers == nil)
    #expect(!restarted.requested)
    #expect(!restarted.effectiveMonitoring)
    #expect(system.pollers.isEmpty)
    #expect(system.permissionRequests == 0)
}

@Test @MainActor func hiddenFeatureResetWithUnreadableOwnershipPreservesAuthorityForRetry() async throws {
    var system = ControlledAlertSystem()
    let original = AlertMonitoringController(system: system)
    original.configure()
    await original.setEnabled(true)
    let ownedIdentifiers = system.saved.notificationRequestIdentifiers
    system = system.afterAbruptProcessExit() // Abrupt exit retains prior-process pending requests.
    system.available = false
    system.stateUnreadable = true
    let restarted = AlertMonitoringController(system: system)
    #expect(throws: CocoaError.self) { try restarted.resetPreferences() }
    #expect(system.saved.notificationRequestIdentifiers == ownedIdentifiers)
    #expect(system.saved.enabled)
    #expect(system.pendingNotifications.count == 1)
    #expect(!restarted.effectiveMonitoring)
    #expect(system.pollers.isEmpty)
    #expect(system.permissionRequests == 0)
    system.stateUnreadable = false
    try restarted.resetPreferences()
    #expect(system.pendingNotifications.isEmpty)
    #expect(!system.saved.enabled)
}

@Test @MainActor func shellShowsMonitoringAndSnoozeWithoutChangingUnappliedEditorPolicy() async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    #expect(alerts.shellState == .off)
    alerts.configure()
    await alerts.setEnabled(true)
    #expect(alerts.shellState == .on)
    alerts.thresholdGB = "invalid"
    #expect(alerts.shellState == .on)
    alerts.remindLater()
    #expect(alerts.shellState == .snoozed(until: system.now.addingTimeInterval(86_400)))
    #expect(alerts.effectiveMonitoring)
    await alerts.setEnabled(false)
    #expect(alerts.shellState == .off)
}

@Test @MainActor func shellKeepsCapacityBlockerDuringAuthorizationRecheckThenRecovers() async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    await alerts.setEnabled(true)
    system.now.addTimeInterval(900)
    system.reading = AlertCapacityReading(available: nil, total: nil, volumeID: nil, metric: "unavailable")
    await alerts.activated()
    #expect(alerts.shellState == .attention(.capacityUnavailable))
    #expect(alerts.effectiveMonitoring)
    system.holdNextAuthorization = true
    let activation = Task { await alerts.activated() }
    var began = system.heldBegan.stream.makeAsyncIterator(); _ = await began.next()
    #expect(alerts.shellState == .attention(.capacityUnavailable))
    system.reading = AlertCapacityReading(available: 60_000_000_000, total: 512_000_000_000, volumeID: "owned", metric: "important")
    system.now.addTimeInterval(900)
    system.held?.resume(returning: .allowed); system.held = nil
    await activation.value
    #expect(alerts.shellState == .on)
}

@Test @MainActor func shellTracksInitialCheckingBlockedPermissionAndValidatedRecovery() async {
    let system = ControlledAlertSystem()
    system.saved.enabled = true
    let alerts = AlertMonitoringController(system: system)
    #expect(alerts.shellState == .checking)
    system.holdNextAuthorization = true
    let activation = Task { await alerts.activated() }
    var began = system.heldBegan.stream.makeAsyncIterator(); _ = await began.next()
    #expect(alerts.shellState == .checking)
    system.held?.resume(returning: .denied); system.held = nil
    await activation.value
    #expect(alerts.shellState == .attention(.notificationsUnavailable))
    system.holdNextAuthorization = true
    let recheck = Task { await alerts.activated() }
    _ = await began.next()
    #expect(alerts.shellState == .attention(.notificationsUnavailable))
    system.held?.resume(returning: .allowed); system.held = nil
    await recheck.value
    #expect(alerts.shellState == .on)
}

@Test @MainActor func shellReportsUnreadableAndUnsavablePreferencesEvenWhenIntentIsOff() async {
    let unreadable = ControlledAlertSystem()
    unreadable.stateUnreadable = true
    let restored = AlertMonitoringController(system: unreadable)
    #expect(!restored.requested)
    #expect(restored.shellState == .attention(.savedStateUnavailable))
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    await alerts.setEnabled(true)
    system.saveFails = true
    await alerts.setEnabled(false)
    #expect(!alerts.requested)
    #expect(alerts.shellState == .attention(.saveFailed))
    #expect(!alerts.effectiveMonitoring)
}

@Test @MainActor func shellSubmissionBlockerBeatsSnoozeUntilSuccessfulRevalidation() async {
    let system = ControlledAlertSystem()
    system.submissionFails = true
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    await alerts.setEnabled(true)
    #expect(alerts.shellState == .attention(.submissionFailed))
    alerts.remindLater()
    #expect(alerts.shellState == .attention(.submissionFailed))
    system.holdNextAuthorization = true
    let recheck = Task { await alerts.activated() }
    var began = system.heldBegan.stream.makeAsyncIterator(); _ = await began.next()
    #expect(alerts.shellState == .attention(.submissionFailed))
    system.now.addTimeInterval(86_401)
    system.submissionFails = false
    system.held?.resume(returning: .allowed); system.held = nil
    await recheck.value
    #expect(alerts.shellState == .on)
}

@Test @MainActor func shellInvalidAppliedThresholdRequiresAttentionUntilApplyAndResetClearsIt() async throws {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    await alerts.setEnabled(true)
    system.now.addTimeInterval(900)
    system.reading = AlertCapacityReading(available: 10_000_000_000, total: 30_000_000_000, volumeID: "replacement", metric: "important")
    await alerts.activated()
    #expect(alerts.shellState == .attention(.invalidThreshold))
    alerts.thresholdGB = "5"
    #expect(alerts.shellState == .attention(.invalidThreshold))
    system.now.addTimeInterval(60)
    await alerts.applyThreshold()
    #expect(alerts.shellState == .on)
    try alerts.resetPreferences()
    #expect(alerts.shellState == .off)
    #expect(!alerts.effectiveMonitoring)
    let gated = ControlledAlertSystem()
    gated.available = false; gated.stateUnreadable = true
    let hidden = AlertMonitoringController(system: gated)
    #expect(hidden.shellState == .off)
}

@Test @MainActor func shellPreservesPersistenceBlockerWhenSubmissionAlsoFails() async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    system.holdNextSubmission = true
    let enabling = Task { await alerts.setEnabled(true) }
    var began = system.submissionBegan.stream.makeAsyncIterator(); _ = await began.next()
    system.saveFails = true; system.submissionFails = true
    system.heldSubmission?.resume(); system.heldSubmission = nil
    await enabling.value
    #expect(alerts.shellState == .attention(.saveFailed))
    #expect(!alerts.effectiveMonitoring)
}

@Test @MainActor func shellReportsFailedResetAfterMonitoringHasStopped() async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    await alerts.setEnabled(true)
    system.resetFails = true
    do { try alerts.resetPreferences(); Issue.record("Reset should report the system failure") }
    catch {}
    #expect(!alerts.requested)
    #expect(!alerts.effectiveMonitoring)
    #expect(alerts.shellState == .attention(.saveFailed))
    #expect(alerts.status == "Alert preferences could not be reset. Monitoring is stopped; review local records before trying again.")
}

@Test(arguments: [-1 as Int64, 513_000_000_000]) @MainActor func shellRejectsInvalidCapacityEvidenceWithoutChangingPollerLifecycle(available: Int64) async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    await alerts.setEnabled(true)
    system.now.addTimeInterval(900)
    system.reading = AlertCapacityReading(available: available, total: 512_000_000_000, volumeID: "owned", metric: "important")
    await alerts.activated()
    #expect(alerts.shellState == .attention(.capacityUnavailable))
    #expect(alerts.status == "Capacity unavailable. Alert decisions are paused.")
    #expect(alerts.effectiveMonitoring)
    #expect(system.notifications == 1)
    system.now.addTimeInterval(900)
    system.reading = AlertCapacityReading(available: 60_000_000_000, total: 512_000_000_000, volumeID: "owned", metric: "important")
    await alerts.activated()
    #expect(alerts.shellState == .on)
}

@Test @MainActor func shellReportsUnreadableResetOwnershipAfterMonitoringHasStopped() async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    await alerts.setEnabled(true)
    system.stateUnreadable = true
    do { try alerts.resetPreferences(); Issue.record("Reset should report unreadable ownership") }
    catch {}
    #expect(alerts.requested)
    #expect(!alerts.effectiveMonitoring)
    #expect(alerts.shellState == .attention(.savedStateUnavailable))
    #expect(alerts.status == "Alert state could not be read. Monitoring is stopped to preserve suppression.")
}

@Test @MainActor func pendingThresholdDoesNotBecomeAppliedUntilExplicitApply() async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    alerts.thresholdGB = "60"
    #expect(alerts.thresholdChanged)
    #expect(alerts.appliedThresholdBytes == 40_000_000_000)
    await alerts.setEnabled(true)
    #expect(system.saved.thresholdBytes == 40_000_000_000)
    await alerts.applyThreshold()
    #expect(alerts.appliedThresholdBytes == 60_000_000_000)
    #expect(!alerts.thresholdChanged)
    await alerts.setEnabled(false)
}

@Test @MainActor func unknownDisplayTotalCannotReplaceSavedThreshold() async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    alerts.thresholdGB = "60"
    await alerts.applyThreshold(validatingTotal: nil)
    #expect(alerts.appliedThresholdBytes == 40_000_000_000)
    #expect(system.saved.thresholdBytes == 40_000_000_000)
    #expect(alerts.thresholdChanged)
    #expect(system.notifications == 0)
}

@Test @MainActor func permissionRecoveryRechecksWithoutPromptAndPreservesMonitoringSampleTime() async {
    let system = ControlledAlertSystem()
    system.permission = .denied
    let alerts = AlertMonitoringController(system: system)
    alerts.configure()
    await alerts.activated()
    #expect(alerts.authorizationChecked)
    #expect(alerts.authorization == .denied)
    #expect(alerts.lastMonitoringCheck == nil)
    await alerts.setEnabled(true)
    #expect(!alerts.effectiveMonitoring)
    #expect(system.permissionRequests == 0)
    system.permission = .allowed
    await alerts.activated()
    #expect(alerts.effectiveMonitoring)
    #expect(alerts.lastMonitoringCheck == system.now)
    #expect(system.permissionRequests == 0)
    await alerts.setEnabled(false)
}

@Test @MainActor func stalePermissionReplyCannotOverwriteNewerSettingsEvidence() async {
    let system = ControlledAlertSystem()
    let alerts = AlertMonitoringController(system: system)
    system.holdNextAuthorization = true
    let earlier = Task { await alerts.activated() }
    var began = system.heldBegan.stream.makeAsyncIterator(); _ = await began.next()
    await alerts.activated()
    #expect(alerts.authorization == .allowed)
    system.held?.resume(returning: .denied); system.held = nil
    await earlier.value
    #expect(alerts.authorization == .allowed)
    #expect(!alerts.requested)
    #expect(system.permissionRequests == 0)
}
