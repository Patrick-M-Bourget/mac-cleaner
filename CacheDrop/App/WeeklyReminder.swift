import SwiftUI
import UserNotifications
import CacheDropCore
import StorageAlerts

/// The weekly cleanup reminder's notification (#599, Decision 143): one pending request the OS delivers, replaced after
/// each catalog scan. Its category has no buttons; clicking it opens Smart clean.
enum WeeklyReminderNotification {
    static let identifier = "CacheDrop.weeklyReminder"
    static let category = "CacheDrop.weeklyReminder"
    static let title = "Smart clean"
    /// "About 12 GB was ready to clean at your last scan"
    static func body(readyBytes: Int64) -> String {
        SizeFormatter.text(readyBytes, estimate: true) + " was ready to clean at your last scan"
    }
}

@MainActor final class NativeWeeklyReminderSystem: WeeklyReminderSystem {
    private static let file = "StorageAlerts/weekly-reminder.json"
    var allowsNotificationChanges: Bool { !LocalStateLocation.isDisposableTest }
    var now: Date { Date() }
    var calendar: Calendar { .current }
    private let center = UNUserNotificationCenter.current()
    private var url: URL { get throws { try LocalStateLocation.root(create: true).appendingPathComponent(Self.file) } }
    // The same permission as low-space alerts (Decision 30): one ask, whichever is turned on first.
    func authorization() async -> AlertPolicy.Authorization {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined { return .unknown }
        return settings.authorizationStatus == .authorized && settings.alertSetting == .enabled ? .allowed : .denied
    }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func load() throws -> WeeklyReminderState {
        let url = try url
        guard FileManager.default.fileExists(atPath: url.path) else { return WeeklyReminderState() }
        return try JSONDecoder().decode(WeeklyReminderState.self, from: Data(contentsOf: url))
    }
    func save(_ state: WeeklyReminderState) throws {
        let url = try url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
    func reset() throws { try LocalStateLocation.removeKnownFile(Self.file) }
    func schedule(readyBytes: Int64, at date: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = WeeklyReminderNotification.title
        content.body = WeeklyReminderNotification.body(readyBytes: readyBytes)
        content.sound = .default; content.categoryIdentifier = WeeklyReminderNotification.category
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: WeeklyReminderNotification.identifier, content: content, trigger: trigger))
    }
    func removePendingReminder() {
        guard allowsNotificationChanges else { return }
        center.removePendingNotificationRequests(withIdentifiers: [WeeklyReminderNotification.identifier])
    }
}

/// The weekly reminder in Settings' Notifications group, under low-space alerts (#778). Off by default; turning it on asks
/// for notification permission if it hasn't been answered.
struct WeeklyReminderSettings: View {
    @ObservedObject var controller: WeeklyReminderController
    @State private var settingsFeedback = ""
    var body: some View {
        Group {
            Toggle(isOn: Binding(get: { controller.enabled }, set: { on in Task { await controller.setEnabled(on) } })) {
                Text("Remind me weekly to clean up")
                Text("Sent when your last scan that week found at least 1 GB ready to clean").font(CacheDropDesign.TypeStyle.caption)
            }
                .disabled(controller.stateUnavailable).accessibilityIdentifier("weeklyReminderToggle")
            if controller.enabled {
                AlertPermissionDetails(authorization: controller.authorization, checked: controller.authorizationChecked,
                                       settingsFeedback: settingsFeedback) {
                    Task {
                        let opened = await WorkspaceGuidanceOpener().open(.app(bundleID: "com.apple.systempreferences"))
                        settingsFeedback = opened ? "" : "System Settings couldn’t be opened. Open it from the Apple menu, then Notifications › CacheDrop."
                    }
                }
            }
            if controller.enabled || controller.stateUnavailable {
                Text(WeeklyReminderPresentation.status(controller)).accessibilityIdentifier("weeklyReminderStatus")
            }
        }
        .task { await controller.activated() }
    }
}

/// One short status line (Decision 25).
@MainActor enum WeeklyReminderPresentation {
    static func status(_ controller: WeeklyReminderController) -> String {
        if controller.stateUnavailable { return "Reminder settings couldn’t be saved · Off" }
        if let next = controller.nextReminder { return "Next reminder " + next.formatted(.dateTime.weekday(.wide).hour().minute()) }
        if controller.authorizationChecked && controller.authorization != .allowed { return "Waiting for notification permission" }
        if let bytes = controller.lastReadyBytes, bytes < WeeklyReminderSchedule.thresholdBytes { return "None planned · Less than 1 GB ready to clean" }
        return "None planned until your next scan"
    }
}
