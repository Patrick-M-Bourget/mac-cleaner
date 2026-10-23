import SwiftUI
import AppKit
import ServiceManagement
import Combine

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
    let selection = SessionPlan()
    lazy var inspection = FolderInspection(selection: selection)
    var openWorkspace: (() -> Void)?
    @Published private(set) var loginIntent: Bool
    @Published private(set) var loginStatus: LoginStatus
    @Published private(set) var loginError: String?
    @Published var operationInProgress = false {
        didSet { if !operationInProgress, quitPending { NSApp.terminate(nil) } }
    }
    @Published var hasPendingPlan = false
    var quitPending = false
    var isTerminating = false
    private var monitoringSubscription: AnyCancellable?
    private let registration: LoginRegistration
    private init() {
        let registration = LoginRegistration(service: NativeLoginService(), savedIntent: UserDefaults.standard.bool(forKey: "Still.startAtLogin"))
        self.registration = registration
        loginIntent = registration.intent; loginStatus = registration.status
        monitoringSubscription = alerts.$effectiveMonitoring.dropFirst().sink { [weak self] effective in
            self?.monitoringChanged(effective)
        }
    }
    func refreshLogin() {
        guard StorageAlertsController.futureEnabled else { return }
        registration.refresh(); loginStatus = registration.status
    }
    func chooseLogin(_ enabled: Bool) {
        guard StorageAlertsController.futureEnabled else { return }
        do { try registration.choose(enabled); loginError = nil }
        catch { loginError = "Login registration could not be changed. You can continue using Still on demand." }
        loginIntent = registration.intent; loginStatus = registration.status
        UserDefaults.standard.set(loginIntent, forKey: "Still.startAtLogin")
    }
    func monitoringChanged(_ effective: Bool) {
        guard !quitPending, !isTerminating else { return }
        guard !effective else { return }
        // Finish the current preference/journal update before an off transition terminates.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.quitPending, !self.isTerminating,
                  !self.alerts.effectiveMonitoring, !self.operationInProgress, !self.hasPendingPlan,
                  !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            NSApp.terminate(nil)
        }
    }
}

@MainActor final class StillApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let lifecycle = AppLifecycleController.shared
        return !AppLifecyclePolicy.shouldKeepRunning(effectiveAlerts: lifecycle.alerts.effectiveMonitoring, operationInProgress: lifecycle.operationInProgress, hasPendingPlan: lifecycle.hasPendingPlan)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Future executor must report its safe-operation boundary before requesting termination again.
        guard AppLifecyclePolicy.mayQuit(operationInProgress: AppLifecycleController.shared.operationInProgress) else {
            AppLifecycleController.shared.quitPending = true
            AppLifecycleController.shared.alerts.stopForTermination()
            return .terminateCancel
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
    func applicationDidBecomeActive(_ notification: Notification) { AppLifecycleController.shared.refreshLogin() }
}

struct LoginSettingsView: View {
    @ObservedObject var lifecycle = AppLifecycleController.shared
    var body: some View {
        SettingsRow(title: "Start at Login", detail: "Separate from storage alerts") {
            Toggle("Start Still at Login", isOn: Binding(get: { lifecycle.loginIntent }, set: { lifecycle.chooseLogin($0) }))
            StatusRow(text: statusText, symbol: "power", identifier: "loginRegistrationStatus")
            if let error = lifecycle.loginError { Text(error).foregroundStyle(.secondary) }
            if lifecycle.loginStatus == .requiresApproval {
                Button("Review Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
            Text("Login launch is independent of alerts. Closing the window keeps effective alerts in the menu bar; Quit stops checks and preserves your login choice.").font(.caption).foregroundStyle(.secondary)
        }.task { lifecycle.refreshLogin() }
    }
    private var statusText: String {
        switch lifecycle.loginStatus {
        case .enabled: "Login launch enabled by macOS."
        case .requiresApproval: "Approval required in System Settings > Login Items."
        case .disabled: "Login launch is disabled in macOS."
        case .unavailable: "Login registration unavailable. Still works on demand."
        }
    }
}
