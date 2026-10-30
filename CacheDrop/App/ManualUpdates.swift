import AppKit
import CacheDropCore
import Sparkle
import SwiftUI

/// Sparkle owns every normal update dialog. Only its final user approval waits for CacheDrop's work.
@MainActor final class ManualUpdater: NSObject, SPUUpdaterDelegate {
    private let lifecycle: AppLifecycleController
    private var updater: SPUUpdater!
    private var driver: InstallationUserDriver!
    private var waitingWindow: NSWindowController?
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
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        updater.sendsSystemProfile = false
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
        configureIfNeeded()
        do {
            try updater.start()
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
        guard updateCheck == .updates, !lifecycle.updateInstallation.blocksNewWork else {
            throw NSError(domain: "CacheDrop.Updates", code: 1, userInfo: [NSLocalizedDescriptionKey: "Updates are checked only when you choose Check for Updates…."])
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
        lifecycle.updateInstallation.failed(); closeWaiting()
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
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
