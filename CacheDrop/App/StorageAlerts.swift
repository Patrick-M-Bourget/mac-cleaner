import SwiftUI
import AppKit
import UserNotifications
import Darwin
import CacheDropCore

extension Notification.Name {
    static let cacheDropAlertOpened = Notification.Name("CacheDrop.alertOpened")
}

@MainActor private final class NativeAlertMonitoringSystem: AlertMonitoringSystem {
    /// Wired in the Settings window (#131, RESET Decision 30). Off until you turn them on.
    var available: Bool { true }
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
        content.body = "Open CacheDrop to see what you can clean up."
        content.sound = .default; content.categoryIdentifier = "CacheDrop.capacity"
        content.userInfo = AlertOpenContext(observedAt: observedAt).notificationUserInfo
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}


@MainActor final class StorageAlertsController: AlertMonitoringController, UNUserNotificationCenterDelegate {
    @Published private(set) var openedAlertContext: AlertOpenContext?
    init() {
        super.init(system: NativeAlertMonitoringSystem())
    }
    /// Registers notification handling at launch, so an alert's Open CacheDrop and Remind me later work (#131).
    func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let open = UNNotificationAction(identifier: "CacheDrop.open", title: "Open CacheDrop", options: [.foreground])
        let later = UNNotificationAction(identifier: "CacheDrop.remindLater", title: "Remind me later", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "CacheDrop.capacity", actions: [open, later], intentIdentifiers: [])])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let context = AlertOpenContext(notificationUserInfo: response.notification.request.content.userInfo)
        await MainActor.run {
            if action == "CacheDrop.remindLater" { remindLater(); return }
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
            NotificationCenter.default.post(name: .cacheDropAlertOpened, object: nil)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}

/// The alert threshold, edited as a draft and applied explicitly. The caller supplies current validation evidence;
/// editing never changes the applied preference.
struct AlertThresholdEditor: View {
    @Binding var draft: String
    let canApply: Bool
    var invalidDraft = false
    let apply: () -> Void
    var body: some View {
        LabeledContent("Alert below") {
            HStack(spacing: CacheDropDesign.Space.sm) {
                TextField("Alert below", text: $draft).labelsHidden().frame(width: CacheDropDesign.Size.numberField)
                    .multilineTextAlignment(.trailing).onSubmit { if canApply { apply() } }
                    .accessibilityIdentifier("lowSpaceThreshold")
                Text("GB").foregroundStyle(.secondary)
                Button("Apply", action: apply).disabled(!canApply)
            }
        }
        if invalidDraft {
            StatusRow(text: "Enter at least 1 GB, below this Mac’s capacity.", symbol: "exclamationmark.circle")
        }
    }
}

/// Shown only when notifications for CacheDrop are blocked; permission is asked for only when alerts are turned on.
struct AlertPermissionDetails: View {
    let authorization: AlertPolicy.Authorization
    let checked: Bool
    var settingsFeedback = ""
    let openSettings: () -> Void
    var body: some View {
        if checked && authorization == .denied {
            LabeledContent {
                Button("Open System Settings", action: openSettings)
            } label: {
                Text("Notifications are off for CacheDrop")
                Text("Allow them in System Settings › Notifications.")
            }.accessibilityIdentifier("notificationPermissionStatus")
            if !settingsFeedback.isEmpty { StatusRow(text: settingsFeedback, symbol: "info.circle") }
        }
    }
}

/// Low-space alerts in the Settings window (#131). Off by default. Turning them on asks for notification
/// permission, only then. Capacity checks only: nothing is scanned or cleaned in the background.
struct LowSpaceAlertsSettings: View {
    @ObservedObject var controller: StorageAlertsController
    @State private var capacity = AppLifecycleController.shared.capacity
    @State private var settingsFeedback = ""
    private var currentTotal: Int64? { capacity.failed || capacity.isRefreshing ? nil : capacity.reading?.total }
    var body: some View {
        Section {
            Toggle("Notify me when space is low", isOn: Binding(get: { controller.requested }, set: { enabled in Task { await controller.setEnabled(enabled) } }))
                .disabled(!controller.requested && !AlertPolicy.validThreshold(controller.appliedThresholdBytes, total: controller.total))
                .accessibilityIdentifier("lowSpaceAlertsToggle")
            if controller.requested {
                AlertThresholdEditor(draft: $controller.thresholdGB,
                                     canApply: controller.thresholdChanged && controller.thresholdValid(for: currentTotal),
                                     invalidDraft: controller.thresholdChanged && currentTotal != nil && !controller.thresholdValid(for: currentTotal)) {
                    Task { await controller.applyThreshold(validatingTotal: currentTotal) }
                }
                AlertPermissionDetails(authorization: controller.authorization, checked: controller.authorizationChecked,
                                       settingsFeedback: settingsFeedback) {
                    Task {
                        let opened = await WorkspaceGuidanceOpener().open(.app(bundleID: "com.apple.systempreferences"))
                        settingsFeedback = opened ? "" : "System Settings couldn’t be opened. Open it from the Apple menu, then Notifications › CacheDrop."
                    }
                }
                LabeledContent {
                    Button("Snooze 24 hours") { controller.remindLater() }
                        .disabled(!controller.requested).accessibilityIdentifier("snoozeLowSpaceAlerts")
                } label: {
                    Text(LowSpaceAlertsPresentation.status(controller.shellState)).accessibilityIdentifier("storageAlertStatus")
                }
            }
        } header: {
            Text("Low-space alerts")
        } footer: {
            Text("CacheDrop checks free space about every 15 minutes while it’s open. It never scans or cleans in the background.")
                .font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
        }
        .task {
            controller.configure()
            await controller.activated()
        }
    }
}

/// One short status line per alert state (Decision 25: one line of detail).
enum LowSpaceAlertsPresentation {
    static func status(_ state: AlertShellState) -> String {
        switch state {
        case .off: "Off"
        case .checking: "Checking…"
        case .on: "On"
        case .snoozed(let until): "Snoozed until " + until.formatted(date: .omitted, time: .shortened)
        case .attention(let reason):
            switch reason {
            case .notificationsUnavailable: "Waiting for notification permission"
            case .capacityUnavailable: "Free space couldn’t be read · Paused"
            case .invalidThreshold: "Choose a threshold below this Mac’s capacity"
            case .submissionFailed: "The last alert couldn’t be sent · Will retry"
            case .savedStateUnavailable, .saveFailed: "Alert settings couldn’t be saved · Paused"
            }
        }
    }
}

/// The menu bar item (#131): free space in a short, calm form. Shown by default; Settings can hide it.
struct CacheDropMenuBarLabel: View {
    let capacity: CapacityRefreshController
    var body: some View {
        if let title = MenuBarStatus.freeSpaceTitle(available: capacity.reading?.available) {
            Label(title, image: "BrandMark").labelStyle(.titleAndIcon)
        } else {
            Image("BrandMark").accessibilityLabel("CacheDrop")
        }
    }
}

/// The menu bar item's menu: Open CacheDrop, Scan again, Smart clean… when it has something, Settings… and Quit.
struct CacheDropMenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    let lifecycle: AppLifecycleController
    private var hasRecommendedPlan: Bool {
        let catalog = lifecycle.selection.catalog
        return catalog.hasScanned && catalog.canEdit && !lifecycle.selection.workspaceRunning && !catalog.recommendedCandidates.isEmpty
    }
    var body: some View {
        Button(MenuBarStatus.Item.openCacheDrop.title, action: openCacheDrop)
        Button(MenuBarStatus.Item.scanAgain.title) { openCacheDrop(); lifecycle.scanAgain?() }
        if hasRecommendedPlan {
            Button(MenuBarStatus.Item.smartClean.title) { openCacheDrop(); lifecycle.openSmartClean?() }
        }
        Divider()
        SettingsLink { Text(MenuBarStatus.Item.settings.title) }.keyboardShortcut(",")
        Divider()
        Button(MenuBarStatus.Item.quit.title) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
    private func openCacheDrop() {
        openWindow(id: "workspace")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The Settings toggle for the menu bar item. Stored with the other app preferences; shown unless turned off.
enum MenuBarItemPreference {
    static let key = "CacheDrop.showsMenuBarItem"
}
