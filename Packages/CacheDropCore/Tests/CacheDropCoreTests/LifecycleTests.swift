import Foundation
import Testing
@testable import CacheDropCore

@Test func windowCloseOnlyKeepsEffectiveMonitoringAlive() {
    #expect(AppLifecyclePolicy.shouldKeepRunning(effectiveAlerts: true, operationInProgress: false))
    #expect(!AppLifecyclePolicy.shouldKeepRunning(effectiveAlerts: false, operationInProgress: false))
    #expect(AppLifecyclePolicy.shouldKeepRunning(effectiveAlerts: false, operationInProgress: true))
}

@MainActor private final class DisposableLoginService: LoginService {
    var status = LoginStatus.disabled
    var registrations = 0
    var removals = 0
    func register() throws { registrations += 1; status = .requiresApproval }
    func unregister() throws { removals += 1; status = .disabled }
}

@Test @MainActor func registrationRequiresExplicitChoiceAndRefreshShowsOSStatus() throws {
    let service = DisposableLoginService()
    let registration = LoginRegistration(service: service, savedIntent: true)
    registration.refresh()
    #expect(service.registrations == 0)
    #expect(registration.status == .disabled)
    try registration.choose(true)
    #expect(registration.intent)
    #expect(registration.status == .requiresApproval)
    service.status = .enabled
    registration.refresh()
    #expect(registration.status == .enabled)
    try registration.choose(false)
    #expect(!registration.intent)
    #expect(registration.status == .disabled)
    #expect(service.removals == 1)
}

@Test func explicitQuitWaitsOnlyForOperationBoundary() {
    #expect(!AppLifecyclePolicy.mayQuit(operationInProgress: true))
    #expect(AppLifecyclePolicy.mayQuit(operationInProgress: false))
}

@Test @MainActor func unavailableRegistrationDoesNotPreventOnDemandUse() throws {
    let service = DisposableLoginService()
    service.status = .unavailable
    let registration = LoginRegistration(service: service)
    registration.refresh()
    #expect(registration.status == .unavailable)
    #expect(!AppLifecyclePolicy.shouldKeepRunning(effectiveAlerts: false, operationInProgress: false))
    #expect(service.registrations == 0)
}

@Test func pendingPlanSurvivesWindowCloseWithoutAlertPolling() {
    #expect(AppLifecyclePolicy.shouldKeepRunning(effectiveAlerts: false, operationInProgress: false, hasPendingPlan: true))
}

/// #110: saved window state must never stop the main window from opening at launch.
@Test func launchDefaultsIgnoreSavedWindowState() throws {
    let suite = "CacheDropLaunchDefaultsTest-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    AppLaunchPolicy.registerDefaults(in: defaults)
    #expect(defaults.bool(forKey: "ApplePersistenceIgnoreState"))
}

/// #344: tooltips (a storage bar's segments, a truncated note) show after a short hover, not macOS's default second.
@Test func launchDefaultsShortenTheTooltipDelay() throws {
    let suite = "CacheDropLaunchDefaultsTest-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    AppLaunchPolicy.registerDefaults(in: defaults)
    #expect(defaults.integer(forKey: "NSInitialToolTipDelay") == AppLaunchPolicy.tooltipDelayMilliseconds)
    #expect(AppLaunchPolicy.tooltipDelayMilliseconds <= 300)
}

/// #130: ⌘Q during a cleanup asks first; a confirmed stop is not asked again while the current item ends (#186).
@Test func quittingDuringACleanupAsksBeforeStopping() {
    #expect(AppLifecyclePolicy.quitDecision(cleanupRunning: false, maintenanceInProgress: false, stopConfirmed: false) == .quitNow)
    #expect(AppLifecyclePolicy.quitDecision(cleanupRunning: true, maintenanceInProgress: false, stopConfirmed: false) == .askToStopCleanup)
    #expect(AppLifecyclePolicy.quitDecision(cleanupRunning: true, maintenanceInProgress: false, stopConfirmed: true) == .waitForCurrentItem)
    #expect(AppLifecyclePolicy.quitDecision(cleanupRunning: false, maintenanceInProgress: true, stopConfirmed: false) == .waitForCurrentItem)
}

/// #130, #186: the question is "Stop it and quit?", since a stop ends the running tool mid-item, and Cancel (the default) keeps the cleanup running.
@Test @MainActor func cancelIsTheDefaultAndKeepsTheCleanupRunning() {
    #expect(QuitDuringCleanupPrompt.message == "A cleanup is running. Stop it and quit?")
    #expect(QuitDuringCleanupPrompt.buttons == ["Cancel", "Stop and Quit"])
    var stops = 0
    let keep = QuitDuringCleanupPrompt(ask: { .keepRunning })
    #expect(keep.confirm(stopCleanup: { stops += 1 }) == false)
    #expect(stops == 0)
    let stop = QuitDuringCleanupPrompt(ask: { .stopAndQuit })
    #expect(stop.confirm(stopCleanup: { stops += 1 }) == true)
    #expect(stops == 1)
}

/// #131: closing the window keeps CacheDrop running while its menu bar item is shown, so the item stays.
@Test func windowCloseKeepsRunningWhileTheMenuBarItemIsShown() {
    #expect(AppLifecyclePolicy.shouldKeepRunning(effectiveAlerts: false, operationInProgress: false, menuBarItemShown: true))
    #expect(!AppLifecyclePolicy.shouldKeepRunning(effectiveAlerts: false, operationInProgress: false, menuBarItemShown: false))
}
