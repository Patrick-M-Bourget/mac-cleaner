import SwiftUI
import AppKit
import ServiceManagement
import Combine
import CacheDropCore

@MainActor private final class NativeLoginService: LoginService {
    var status: LoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .disabled
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor final class AppLifecycleController: ObservableObject {
    static let shared = AppLifecycleController()
    let alerts = StorageAlertsController()
    let capacity = CapacityRefreshController(system: NativeCapacityRefreshSystem())
    let appearance = AppearancePreferenceController(store: NativeAppearancePreferenceStore())
    let selection = SessionPlan()
    let recovery = CleanupRecoveryModel()
    let workspaceNavigation = WorkspaceNavigation()
    let locations = RememberedLocations()
    let planPresentation = CleanupPlanPresentation()
    let smartCleanPresentation = SmartCleanPresentation()
    let locationsExplorer = StorageExplorerContext()
    lazy var inspection = FolderInspection(selection: selection)
    var openWorkspace: (() -> Void)?
    /// The workspace's Scan again, for the ⌘R menu command (#127).
    var scanAgain: (() -> Void)?
    /// Opens the Smart clean page, for the menu bar item (#131, #141).
    var openSmartClean: (() -> Void)?
    /// The menu bar item is shown unless turned off in Settings (#131).
    var menuBarItemShown: Bool { UserDefaults.standard.object(forKey: PreferenceKeys.showsMenuBarItem) as? Bool ?? true }
    private var capacityTimer: Timer?
    @Published private(set) var loginIntent: Bool
    @Published private(set) var loginStatus: LoginStatus
    @Published private(set) var loginError: String?
    @Published var operationInProgress = false {
        didSet { if !operationInProgress, quitPending { NSApp.terminate(nil) } }
    }
    @Published var hasPendingPlan = false
    @Published var maintenanceInProgress = false {
        didSet {
            if !maintenanceInProgress, quitPending, !operationInProgress { NSApp.terminate(nil); return }
            // Scans asked for while the lease was held run now (#310).
            if oldValue, !maintenanceInProgress { afterMaintenance.released() }
        }
    }
    /// Scans asked for while the maintenance lease is held, run once it is released (#310).
    let afterMaintenance = WorkAfterMaintenance()
    var quitPending = false
    /// #130: asked before quitting stops a running cleanup.
    let quitDuringCleanup = QuitDuringCleanupPrompt(ask: QuitDuringCleanupAlert.ask)
    var isTerminating = false
    private var monitoringSubscription: AnyCancellable?
    private let registration: LoginRegistration
    private init() {
        let registration = LoginRegistration(service: NativeLoginService(), savedIntent: LocalStateLocation.isDisposableTest ? false : UserDefaults.standard.bool(forKey: PreferenceKeys.startAtLogin))
        self.registration = registration
        loginIntent = registration.intent; loginStatus = registration.status
        capacity.request(.launch)
        // Keeps the menu bar item's free space current. Capacity metadata only; never a folder scan (#131).
        capacityTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [capacity] _ in Task { @MainActor in capacity.request(.foreground) } }
        capacityTimer?.tolerance = 60
        monitoringSubscription = alerts.$effectiveMonitoring.dropFirst().sink { [weak self] effective in
            self?.monitoringChanged(effective)
        }
    }
    // A single native owner keeps SwiftUI content and auxiliary panels in the same
    // appearance. A competing view-level override can outlive a reset to Automatic.
    func applyAppearance() {
        switch appearance.choice {
        case .automatic: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }
    func chooseAppearance(_ choice: AppearanceChoice) { appearance.choose(choice); applyAppearance() }
    func resetAppearancePreference() throws { try appearance.reset(); applyAppearance() }
    func resetPreferences() throws {
        guard !operationInProgress, !selection.workspaceRunning else { throw CleanupJournalError.unavailable }
        if !LocalStateLocation.isDisposableTest {
            registration.refresh()
            if registration.status == .enabled || registration.status == .requiresApproval { try registration.choose(false) }
            else if registration.status == .unavailable && loginIntent { throw CleanupJournalError.unavailable }
            UserDefaults.standard.removeObject(forKey: PreferenceKeys.startAtLogin)
        }
        loginIntent = false; loginStatus = LocalStateLocation.isDisposableTest ? .disabled : registration.status
        try alerts.resetPreferences()
    }
    func refreshLogin() {
        registration.refresh(); loginStatus = registration.status
    }
    func chooseLogin(_ enabled: Bool) {
        do { try registration.choose(enabled); loginError = nil }
        catch { loginError = "Login registration could not be changed. You can continue using CacheDrop on demand." }
        loginIntent = registration.intent; loginStatus = registration.status
        UserDefaults.standard.set(loginIntent, forKey: PreferenceKeys.startAtLogin)
    }
    func monitoringChanged(_ effective: Bool) {
        guard !quitPending, !isTerminating else { return }
        guard !effective else { return }
        // Finish the current preference/journal update before an off transition terminates.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.quitPending, !self.isTerminating,
                  !self.alerts.effectiveMonitoring, !self.operationInProgress, !self.maintenanceInProgress, !self.hasPendingPlan, !self.menuBarItemShown,
                  !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            NSApp.terminate(nil)
        }
    }
}

/// The standard alert for #130, with Cancel as the default button.
@MainActor enum QuitDuringCleanupAlert {
    static func ask() -> QuitDuringCleanupPrompt.Answer {
        let alert = NSAlert()
        alert.messageText = QuitDuringCleanupPrompt.message
        for title in QuitDuringCleanupPrompt.buttons { alert.addButton(withTitle: title) }
        alert.buttons.last?.hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn ? .stopAndQuit : .keepRunning
    }
}

@MainActor final class CacheDropApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let lifecycle = AppLifecycleController.shared
        return !AppLifecyclePolicy.shouldKeepRunning(effectiveAlerts: lifecycle.alerts.effectiveMonitoring, operationInProgress: lifecycle.operationInProgress || lifecycle.maintenanceInProgress, hasPendingPlan: lifecycle.hasPendingPlan, menuBarItemShown: lifecycle.menuBarItemShown)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let lifecycle = AppLifecycleController.shared
        switch AppLifecyclePolicy.quitDecision(cleanupRunning: lifecycle.operationInProgress, maintenanceInProgress: lifecycle.maintenanceInProgress, stopConfirmed: lifecycle.quitPending) {
        case .quitNow: break
        case .waitForCurrentItem:
            // Quit completes on its own once the current item ends (operationInProgress/maintenanceInProgress didSet).
            lifecycle.quitPending = true
            return .terminateCancel
        case .askToStopCleanup:
            let confirmed = lifecycle.quitDuringCleanup.confirm {
                lifecycle.quitPending = true
                lifecycle.selection.cancelWorkspace()
                lifecycle.alerts.stopForTermination()
            }
            // The cleanup can finish while the alert is open; a confirmed quit then completes now.
            guard confirmed, !lifecycle.operationInProgress, !lifecycle.maintenanceInProgress else { return .terminateCancel }
        }
        AppLifecycleController.shared.selection.endSession()
        AppLifecycleController.shared.isTerminating = true
        AppLifecycleController.shared.alerts.stopForTermination()
        return .terminateNow
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppLifecycleController.shared.openWorkspace?() }
        return true
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let lifecycle = AppLifecycleController.shared
        lifecycle.applyAppearance()
        // Low-space alerts (#131): restore a saved choice. Nothing is asked for until you turn alerts on.
        if !LocalStateLocation.isDisposableTest { lifecycle.alerts.configureNotifications() }
        lifecycle.alerts.configure()
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        AppLifecycleController.shared.capacity.request(.foreground)
    }
}

/// Start at Login, a separate choice from alerts and the menu bar item.
struct LoginSettingsView: View {
    @ObservedObject var lifecycle = AppLifecycleController.shared
    var body: some View {
        Toggle("Start CacheDrop at Login", isOn: Binding(get: { lifecycle.loginIntent }, set: { lifecycle.chooseLogin($0) }))
            .accessibilityIdentifier("startAtLoginToggle")
            .task { lifecycle.refreshLogin() }
        if let error = lifecycle.loginError { StatusRow(text: error, symbol: "exclamationmark.circle") }
        if lifecycle.loginStatus == .requiresApproval {
            LabeledContent("Needs approval in System Settings") {
                Button("Review Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
        } else if lifecycle.loginStatus == .unavailable {
            StatusRow(text: "Start at Login isn’t available for this copy of CacheDrop.", symbol: "info.circle", identifier: "loginRegistrationStatus")
        }
    }
}
