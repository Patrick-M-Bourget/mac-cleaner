import AppKit
import CacheDropCore
import Sparkle
import SwiftUI

/// Sparkle owns every normal update dialog. Only its final user approval waits for CacheDrop's work. Checks are requested
/// (Check for Updates…) or scheduled once a week while Check for updates automatically is on (#600, Decision 145).
@MainActor final class ManualUpdater: NSObject, SPUUpdaterDelegate {
    private let lifecycle: AppLifecycleController
    private var updater: SPUUpdater!
    private var driver: InstallationUserDriver!
    private var started = false
    /// A scheduled check this updater refused aborts its cycle; that abort must not touch a pending installation.
    private var refusedScheduledCheck = false
    private var waitingWindow: NSWindowController?
    private var automaticChecks: Bool {
        AutomaticUpdateChecks.isOn(saved: UserDefaults.standard.object(forKey: PreferenceKeys.checksForUpdatesAutomatically),
                                   disposableTest: LocalStateLocation.isDisposableTest)
    }
    init(lifecycle: AppLifecycleController) {
        self.lifecycle = lifecycle
        super.init()
    }
    private func configureIfNeeded() {
        guard updater == nil else { return }
        driver = InstallationUserDriver(hostBundle: .main, delegate: nil)
        driver.approve = { [weak self] reply in self?.approve(reply) }
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        // Set these before starting, overriding preferences from older or experimental copies.
        updater.automaticallyChecksForUpdates = automaticChecks
        updater.updateCheckInterval = AutomaticUpdateChecks.interval
        updater.automaticallyDownloadsUpdates = false
        updater.sendsSystemProfile = false
    }
    private func startIfNeeded() throws {
        configureIfNeeded()
        guard !started else { return }
        try updater.start()
        started = true
    }
    /// At launch: Sparkle keeps the weekly schedule only while it runs, so it starts when automatic checks are on.
    func startScheduledChecks() {
        guard automaticChecks else { return }
        try? startIfNeeded()
    }
    /// The Settings toggle changed: Sparkle reschedules or stops; nothing is checked right away.
    func automaticChecksChanged() {
        if automaticChecks { try? startIfNeeded() }
        updater?.automaticallyChecksForUpdates = automaticChecks
    }
    func checkForUpdates() {
        guard !lifecycle.updateInstallation.blocksNewWork else { waitingWindow?.showWindow(nil); return }
        #if DEBUG
        // Exercises the app's waiting dialog without a network update or any real cleanup tool.
        if LocalStateLocation.isDisposableTest, let work = LocalStateLocation.fixtureEnvironment["CACHEDROP_TEST_UPDATE_WORK"] {
            if work == "cleanup" { lifecycle.operationInProgress = true }
            if work == "maintenance" { lifecycle.maintenanceInProgress = true }
            approve { _ in }
            return
        }
        #endif
        do {
            try startIfNeeded()
            updater.checkForUpdates()
        } catch {
            lifecycle.updateInstallation.failed()
            NSAlert(error: error).runModal()
        }
    }
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
    func feedURLString(for updater: SPUUpdater) -> String? {
        // An acceptance feed is an explicit build configuration, never a runtime override of production users.
        Bundle.main.object(forInfoDictionaryKey: "CacheDropAcceptanceFeedURL") as? String
            ?? "https://cachedrop.io/updates/appcast.xml"
    }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        let check: AutomaticUpdateChecks.Check? = switch updateCheck {
        case .updates: .requested
        case .updatesInBackground: .scheduled
        default: nil
        }
        guard let check, AutomaticUpdateChecks.allows(check, automaticChecksOn: automaticChecks,
                                                      installationPending: lifecycle.updateInstallation.blocksNewWork) else {
            if updateCheck == .updatesInBackground { refusedScheduledCheck = true }
            throw NSError(domain: "CacheDrop.Updates", code: 1, userInfo: [NSLocalizedDescriptionKey: "Wait for the update to finish"])
        }
    }
    private func approve(_ reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let installation = lifecycle.updateInstallation
        var maintenanceRunning = lifecycle.maintenanceInProgress
        #if DEBUG
        if LocalStateLocation.isDisposableTest, LocalStateLocation.fixtureEnvironment["CACHEDROP_TEST_UPDATE_WORK"] == "admission" {
            maintenanceRunning = true
        }
        #endif
        guard installation.request(cleanupRunning: lifecycle.operationInProgress,
                                   maintenanceRunning: maintenanceRunning,
                                   install: { [weak self] in self?.closeWaiting(); reply(.install) },
                                   cancel: { [weak self] in self?.closeWaiting(); reply(.skip) }) else { reply(.skip); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: CacheDropDesign.Size.sheetNarrow, height: 180),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "CacheDrop Update"
        panel.contentView = NSHostingView(rootView: UpdateWaitingView(installation: installation))
        panel.center()
        waitingWindow = NSWindowController(window: panel)
        waitingWindow?.showWindow(nil)
    }
    private func closeWaiting() { waitingWindow?.close(); waitingWindow = nil }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        if refusedScheduledCheck { refusedScheduledCheck = false; return }
        lifecycle.updateInstallation.failed(); closeWaiting()
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        // A scheduled check that finds nothing or can't reach the feed leaves any pending installation alone.
        if updateCheck == .updatesInBackground { refusedScheduledCheck = false; return }
        if error != nil { lifecycle.updateInstallation.failed(); closeWaiting() }
    }
}

/// A cancelable ready-to-install reply is required: postponing relaunch alone has no public cancellation handle.
@MainActor private final class InstallationUserDriver: SPUStandardUserDriver {
    var approve: ((@escaping (SPUUserUpdateChoice) -> Void) -> Void)?
    override func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        let choice = await super.showReadyToInstallAndRelaunch()
        return choice == .install ? await approvedChoice() : choice
    }
    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState) async -> SPUUserUpdateChoice {
        let choice = await super.showUpdateFound(with: appcastItem, state: state)
        return choice == .install && state.stage == .installing ? await approvedChoice() : choice
    }
    private func approvedChoice() async -> SPUUserUpdateChoice {
        guard let approve else { return .skip }
        return await withCheckedContinuation { continuation in approve { continuation.resume(returning: $0) } }
    }
}

struct UpdateWaitingView: View {
    let installation: UpdateInstallation
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            Text(installation.state == .waitingForCleanup ? "Waiting for cleanup to finish" : "Finishing current work")
                .font(CacheDropDesign.TypeStyle.sheet).accessibilityIdentifier("updateWaitingText")
            ProgressView().controlSize(.small)
            SheetFooter {
                Button("Cancel update") { installation.cancel() }.disabled(!installation.canCancel)
                    .accessibilityIdentifier("cancelUpdate")
            }
        }.padding(CacheDropDesign.Space.xl).frame(width: CacheDropDesign.Size.sheetNarrow)
            .cacheDropButtonRule()
    }
}
