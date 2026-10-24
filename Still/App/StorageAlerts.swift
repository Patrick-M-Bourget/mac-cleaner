import SwiftUI
import AppKit
import UserNotifications
import Darwin

extension Notification.Name {
    static let stillAlertOpened = Notification.Name("Still.alertOpened")
}

@MainActor private final class NativeAlertMonitoringSystem: AlertMonitoringSystem {
    var available: Bool { StorageAlertsController.futureEnabled }
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

#if DEBUG
/// Controlled service boundary for one owned read-failure journey. No operation
/// reaches notification APIs, creates a timer, or rewrites the fixture record.
@MainActor private final class DisposableAlertMonitoringSystem: AlertMonitoringSystem {
    let root: URL
    init(root: URL) { self.root = root }
    static func requested() -> DisposableAlertMonitoringSystem? {
        guard StorageAlertsController.futureEnabled, LocalStateLocation.isDisposableTest,
              ProcessInfo.processInfo.arguments.contains("--ui-test-alert-service"),
              let root = try? LocalStateLocation.root(create: false) else { return nil }
        return Self(root: root)
    }
    var available: Bool { true }
    var allowsNotificationChanges: Bool { true }
    var now: Date { Date() }
    func authorization() async -> AlertPolicy.Authorization { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func capacity() -> AlertCapacityReading { AlertCapacityReading(available: nil, total: nil, volumeID: nil, metric: "important") }
    func load() throws -> AlertPolicy {
        let folder = root.appendingPathComponent("StorageAlerts")
        let file = folder.appendingPathComponent("episode-state.json")
        var directory = stat(), item = stat()
        guard lstat(folder.path, &directory) == 0, directory.st_mode & S_IFMT == S_IFDIR,
              directory.st_uid == geteuid(), folder.path == folder.resolvingSymlinksInPath().path,
              lstat(file.path, &item) == 0, item.st_mode & S_IFMT == S_IFREG,
              item.st_uid == geteuid(), item.st_size <= 16_384,
              file.path == file.resolvingSymlinksInPath().path else { throw CocoaError(.fileReadNoPermission) }
        return try AlertStateStore(url: file).load()
    }
    func save(_ policy: AlertPolicy) throws { throw CocoaError(.fileWriteNoPermission) }
    func reset() throws { throw CocoaError(.fileWriteNoPermission) }
    func startPolling(_ sample: @escaping @MainActor () -> Void) -> () -> Void { {} }
    func removePendingNotifications(identifiers: [String]) {}
    func submitLowSpaceNotification(identifier: String, observedAt: Date) async throws { throw CocoaError(.featureUnsupported) }
}
#endif

@MainActor final class StorageAlertsController: AlertMonitoringController, UNUserNotificationCenterDelegate {
    @Published private(set) var openedAlertContext: AlertOpenContext?
    static var futureEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--future-milestones") }
    init() {
        #if DEBUG
        let system: any AlertMonitoringSystem
        if let fixture = DisposableAlertMonitoringSystem.requested() { system = fixture }
        else { system = NativeAlertMonitoringSystem() }
        super.init(system: system)
        #else
        super.init(system: NativeAlertMonitoringSystem())
        #endif
        if Self.futureEnabled && !LocalStateLocation.isDisposableTest {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            let open = UNNotificationAction(identifier: "Still.open", title: "Open Still", options: [.foreground])
            let later = UNNotificationAction(identifier: "Still.remindLater", title: "Remind me later", options: [])
            center.setNotificationCategories([UNNotificationCategory(identifier: "Still.capacity", actions: [open, later], intentIdentifiers: [])])
        }
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

struct StorageAlertsView: View {
    @ObservedObject var controller: StorageAlertsController
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            PageHeader(title: "Storage alerts")
            Text("Choose a minimum available-space threshold. Alerts check capacity only, about every 15 minutes while awake. Opening an alert offers a scan; it never starts one.").foregroundStyle(.secondary)
            SettingsRow(title: "Minimum available space", detail: "Capacity checks run while Still is open. Alerts are off by default.") {
            HStack {
                TextField("Minimum available space (GB)", text: $controller.thresholdGB).frame(width: 180)
                Text("GB · decimal units").foregroundStyle(.secondary)
                Button("Apply threshold") { Task { await controller.applyThreshold() } }.disabled(!controller.thresholdValid)
            }
            Text("Valid range: at least 1 GB and below startup-volume capacity. Suggested: 40 GB.").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Toggle("Notify me when space is low", isOn: Binding(get: { controller.requested }, set: { enabled in Task { await controller.setEnabled(enabled) } }))
                .disabled(!controller.requested && !controller.thresholdValid)
            StatusRow(text: controller.status, symbol: controller.effectiveMonitoring ? "bell.badge" : "bell.slash", identifier: "storageAlertStatus")
            Divider()
            LoginSettingsView()
            Button("Remind me later · 24 hours") { controller.remindLater() }.disabled(!controller.requested)
            Button("Open System Settings") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
            Text("This development capability checks capacity only; it does not scan folders or clean files.").font(.caption).foregroundStyle(.secondary)
        }.task { controller.configure() }
    }
}
