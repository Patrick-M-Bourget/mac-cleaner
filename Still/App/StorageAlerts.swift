import SwiftUI
import AppKit
import UserNotifications
import Darwin
import StillCore

extension Notification.Name {
    static let stillAlertOpened = Notification.Name("Still.alertOpened")
}

@MainActor private final class NativeAlertMonitoringSystem: AlertMonitoringSystem {
    /// Alerts stay unwired until after M1 (docs/RESET.md, Decision 12).
    var available: Bool { false }
    var allowsNotificationChanges: Bool { !LocalStateLocation.isDisposableTest }
    var now: Date { Date() }
    private var store: AlertStateStore { get throws { AlertStateStore(url: try LocalStateLocation.root(create: true).appendingPathComponent("StorageAlerts/episode-state.json")) } }
    private let center = UNUserNotificationCenter.current()
    func authorization() async -> AlertPolicy.Authorization {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined { return .unknown }
        return settings.authorizationStatus == .authorized && settings.alertSetting == .enabled ? .allowed : .denied
    }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func capacity() -> AlertCapacityReading {
        let reading = StartupVolumeCapacity.read()
        return AlertCapacityReading(available: reading.available, total: reading.total, volumeID: reading.volumeID, metric: reading.metric)
    }
    func load() throws -> AlertPolicy { try store.load() }
    func save(_ policy: AlertPolicy) throws { try store.save(policy) }
    func reset() throws { try LocalStateLocation.removeKnownFile("StorageAlerts/episode-state.json") }
    func startPolling(_ sample: @escaping @MainActor () -> Void) -> () -> Void {
        let timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { _ in Task { @MainActor in sample() } }
        timer.tolerance = 60
        return { timer.invalidate() }
    }
    func removePendingNotifications(identifiers: [String]) {
        guard allowsNotificationChanges else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    func submitLowSpaceNotification(identifier: String, observedAt: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Your Mac is running low on space"
        content.body = "Capacity checked at \(observedAt.formatted(date: .omitted, time: .shortened)). Open Still to review storage and choose whether to scan."
        content.sound = .default; content.categoryIdentifier = "Still.capacity"
        content.userInfo = AlertOpenContext(observedAt: observedAt).notificationUserInfo
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}


@MainActor final class StorageAlertsController: AlertMonitoringController, UNUserNotificationCenterDelegate {
    @Published private(set) var openedAlertContext: AlertOpenContext?
    init() {
        super.init(system: NativeAlertMonitoringSystem())
    }
    /// Registers notification handling. Not called while alerts are unwired (Decision 12).
    func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let open = UNNotificationAction(identifier: "Still.open", title: "Open Still", options: [.foreground])
        let later = UNNotificationAction(identifier: "Still.remindLater", title: "Remind me later", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "Still.capacity", actions: [open, later], intentIdentifiers: [])])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let context = AlertOpenContext(notificationUserInfo: response.notification.request.content.userInfo)
        await MainActor.run {
            if action == "Still.remindLater" { remindLater(); return }
            openAlert(context: context)
        }
    }
    func dismissOpenedAlert() { openedAlertContext = nil }
    func openAlert(context: AlertOpenContext) {
            openedAlertContext = context
            AppLifecycleController.shared.capacity.request(.alertOpened)
            AppLifecycleController.shared.openWorkspace?()
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .stillAlertOpened, object: nil)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}

/// Pure shared threshold presentation. The caller supplies current validation evidence;
/// editing never changes the applied monitoring preference.
struct AlertThresholdEditor: View {
    @Binding var draft: String
    let appliedBytes: Int64
    let hasCurrentTotal: Bool
    let canApply: Bool
    var invalidDraft = false
    let apply: () -> Void
    var body: some View {
        SettingsRow(title: "Minimum available space", detail: "Applied threshold: " + ByteCountFormatter.string(fromByteCount: appliedBytes, countStyle: .decimal)) {
            HStack(spacing: StillDesign.Space.sm) {
                TextField("Minimum available space (GB)", text: $draft).frame(width: 120)
                Text("GB · decimal units").foregroundStyle(.secondary)
                Spacer(minLength: StillDesign.Space.sm)
                Button("Apply threshold", action: apply).disabled(!canApply)
            }
            if invalidDraft && hasCurrentTotal {
                StatusRow(text: "Enter a number of at least 1 GB and below startup-volume capacity. Your applied threshold is unchanged.", symbol: "exclamationmark.circle")
            }
            Text(hasCurrentTotal ? "At least 1 GB and below startup-volume capacity. Suggested: 40 GB. Edits take effect only after Apply." : "Refresh capacity to validate changes. Your applied threshold is preserved.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Read-only authorization evidence with an explicit native Settings action.
struct AlertPermissionDetails: View {
    let authorization: AlertPolicy.Authorization
    let checked: Bool
    var settingsFeedback = ""
    let openSettings: () -> Void
    private var title: String {
        guard checked else { return "Checking notification permission…" }
        switch authorization {
        case .allowed: return "Notifications allowed"
        case .denied: return "Notifications blocked"
        case .unknown: return "Notification permission not requested"
        }
    }
    var body: some View {
        SettingsRow(title: "Notification permission", detail: "Permission is requested only when you turn alerts on.") {
            Text(title).accessibilityIdentifier("notificationPermissionStatus")
            if checked && authorization == .denied {
                Text("Monitoring is stopped. In System Settings → Notifications → Still, allow notifications. Returning here checks permission again.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open System Settings", action: openSettings)
            }
            if !settingsFeedback.isEmpty { StatusRow(text: settingsFeedback, symbol: "info.circle") }
        }
    }
}

struct QuietAlertExplanation: View {
    @Binding var expanded: Bool
    var body: some View {
        DisclosureGroup("How reminders stay quiet", isExpanded: $expanded) {
            Text("One alert is sent per low-space episode. Alerts rearm after available space reaches the applied threshold plus 5 GB, capped at startup-volume capacity. Remind me later snoozes for 24 hours. macOS notification and Focus settings can silence delivery.")
            Text("Capacity-only checks need no folder access and run about every 15 minutes while awake. Closing the window keeps Still running only while monitoring or other active work needs it; Quit stops checks. Start at Login is independent. Opening an alert offers a scan; it never starts one.")
        }.font(.caption).foregroundStyle(.secondary)
    }
}

struct StorageAlertsView: View {
    @ObservedObject var controller: StorageAlertsController
    let capacity: CapacityRefreshController
    var configureOnEntry = true
    @State private var quietExpanded = false
    @State private var settingsFeedback = ""
    private var currentTotal: Int64? { capacity.failed || capacity.isRefreshing ? nil : capacity.reading?.total }
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            PageHeader(title: "Storage alerts", subtitle: "Choose when Still reminds you to review storage.")
            VolumeSummary(available: capacity.reading?.available, total: capacity.reading?.total,
                          observation: capacity.observationText, status: capacity.statusText,
                          refreshTitle: capacity.failed ? "Retry capacity refresh" : "Refresh capacity",
                          refreshing: capacity.isRefreshing, refresh: { capacity.request(.manual) })
            Text("Current display only · Refreshing capacity does not run an alert check.").font(.caption).foregroundStyle(.secondary)
            AlertPermissionDetails(authorization: controller.authorization, checked: controller.authorizationChecked,
                                   settingsFeedback: settingsFeedback) {
                Task {
                    let opened = await WorkspaceGuidanceOpener().open(.app(bundleID: "com.apple.systempreferences"))
                    settingsFeedback = opened ? "System Settings opened. Permission has not been confirmed; return to Still to check again." : "System Settings could not be opened. Open it from the Apple menu, then Notifications → Still."
                }
            }
            AlertThresholdEditor(draft: $controller.thresholdGB, appliedBytes: controller.appliedThresholdBytes,
                                 hasCurrentTotal: currentTotal != nil,
                                 canApply: controller.thresholdChanged && controller.thresholdValid(for: currentTotal),
                                 invalidDraft: controller.thresholdChanged && !controller.thresholdValid(for: currentTotal)) {
                Task { await controller.applyThreshold(validatingTotal: currentTotal) }
            }
            Toggle("Notify me when space is low", isOn: Binding(get: { controller.requested }, set: { enabled in Task { await controller.setEnabled(enabled) } }))
                .disabled(!controller.requested && !AlertPolicy.validThreshold(controller.appliedThresholdBytes, total: controller.total))
            MonitoringDetails(state: controller.shellState, effective: controller.effectiveMonitoring)
            Text(controller.lastMonitoringCheck.map { "Last monitoring check: " + $0.formatted() } ?? "No monitoring capacity check this session.")
                .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("lastMonitoringCheck")
            StatusRow(text: controller.status, symbol: controller.effectiveMonitoring ? "bell.badge" : "bell.slash", identifier: "storageAlertStatus")
            Button("Remind me later · 24 hours") { controller.remindLater() }.disabled(!controller.requested)
            Divider()
            LoginSettingsView()
            QuietAlertExplanation(expanded: $quietExpanded)
            Text("Development capability · Capacity checks never scan folders or clean files.").font(.caption).foregroundStyle(.secondary)
        }.task {
            if configureOnEntry { controller.configure() }
            if !controller.requested { await controller.activated() }
        }
    }
}
