import SwiftUI
import AppKit
import UserNotifications

extension Notification.Name {
    static let stillAlertOpened = Notification.Name("Still.alertOpened")
}

@MainActor final class StorageAlertsController: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var effectiveMonitoring = false
    @Published private(set) var requested = false
    @Published private(set) var status = "Alerts are off."
    @Published private(set) var total: Int64?
    @Published var thresholdGB = "40"
    private var policy = AlertPolicy()
    private var timer: Timer?
    private var sampling = false
    private var monitoringGeneration = UUID()
    private let delivery = AlertDeliveryGate()
    private var persistenceHealthy = true
    private var store: AlertStateStore { get throws { AlertStateStore(url: try LocalStateLocation.root(create: true).appendingPathComponent("StorageAlerts/episode-state.json")) } }
    private let center = UNUserNotificationCenter.current()
    static var futureEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--future-milestones") }

    override init() {
        super.init()
        if Self.futureEnabled && !LocalStateLocation.isDisposableTest {
            center.delegate = self
            let open = UNNotificationAction(identifier: "Still.open", title: "Open Still", options: [.foreground])
            let later = UNNotificationAction(identifier: "Still.remindLater", title: "Remind me later", options: [])
            center.setNotificationCategories([UNNotificationCategory(identifier: "Still.capacity", actions: [open, later], intentIdentifiers: [])])
            do {
                policy = try store.load()
                requested = policy.enabled
                thresholdGB = String(Double(policy.thresholdBytes) / 1_000_000_000)
                if !requested && policy.thresholdBytes == 40_000_000_000 { thresholdGB = "40" }
                if requested { status = "Saved alert preference restored; checking authorization and capacity." }
            } catch {
                persistenceHealthy = false
                status = "Alert state could not be read. Monitoring is stopped to preserve suppression."
            }
        }
    }
    var threshold: Int64? {
        guard let gb = Double(thresholdGB), gb.isFinite, gb >= 1, gb < Double(Int64.max) / 1_000_000_000 else { return nil }
        return Int64(gb * 1_000_000_000)
    }
    var thresholdValid: Bool { threshold.map { AlertPolicy.validThreshold($0, total: total) } ?? false }

    func resetPreferences() throws {
        monitoringGeneration = UUID()
        delivery.invalidate()
        stopForTermination()
        requested = false; policy = AlertPolicy(); thresholdGB = "40"; persistenceHealthy = true
        try LocalStateLocation.removeKnownFile("StorageAlerts/episode-state.json")
        if !LocalStateLocation.isDisposableTest { center.removePendingNotificationRequests(withIdentifiers: ["Still.lowSpace"]) }
        status = "Alerts are off."
    }
    func stopForTermination() {
        timer?.invalidate(); timer = nil; effectiveMonitoring = false
    }
    func configure() {
        guard Self.futureEnabled else { return }
        total = capacity().total
        if requested { Task { await sample() } }
    }
    func setEnabled(_ enabled: Bool) async {
        guard Self.futureEnabled else { return }
        if LocalStateLocation.isDisposableTest { status = "Disposable tests do not change notification settings."; return }
        if enabled && !thresholdValid { status = "Enter at least 1 GB and less than startup-volume capacity."; return }
        requested = enabled
        policy.enabled = enabled
        if !enabled { effectiveMonitoring = false }
        guard persist() else { return }
        if !enabled {
            effectiveMonitoring = false
            timer?.invalidate(); timer = nil
            center.removePendingNotificationRequests(withIdentifiers: ["Still.lowSpace"])
            status = "Alerts are off."; return
        }
        guard thresholdValid, let threshold else { requested = false; policy.enabled = false; status = "Enter at least 1 GB and less than startup-volume capacity."; return }
        policy.thresholdBytes = threshold
        guard persist() else { return }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            status = "Allow notifications to receive low-space alerts."
            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
            catch { status = "Notification permission could not be requested." }
        }
        guard requested else { return }
        await sample()
    }
    func applyThreshold() async {
        guard thresholdValid, let threshold else { status = "Enter at least 1 GB and less than startup-volume capacity."; return }
        policy.thresholdBytes = threshold
        guard persist() else { return }
        if requested { await sample() }
    }
    func activated() async {
        guard requested else { return }
        await sample()
    }
    private func persist() -> Bool {
        guard persistenceHealthy else { effectiveMonitoring = false; return false }
        do { try store.save(policy); return true }
        catch {
            persistenceHealthy = false; effectiveMonitoring = false
            timer?.invalidate(); timer = nil
            status = "Alert state could not be saved. Monitoring is stopped to prevent repeat notifications."
            return false
        }
    }
    func remindLater() {
        guard requested, policy.canRemind else { status = "A valid capacity reading is required before snoozing."; return }
        policy.remindLater(at: Date())
        guard persist() else { return }
        status = "Alerts snoozed for 24 hours. A valid low reading after resumption permits one reminder."
    }
    private func capacity() -> (available: Int64?, total: Int64?, volumeID: String?, metric: String) {
        let reading = StartupVolumeCapacity.read()
        return (reading.available, reading.total, reading.volumeID, reading.metric)
    }
    private func sample() async {
        guard Self.futureEnabled, persistenceHealthy, requested, !sampling else { return }
        sampling = true
        let generation = monitoringGeneration
        defer { sampling = false }
        let settings = await center.notificationSettings()
        guard requested, generation == monitoringGeneration else { return }
        guard settings.authorizationStatus == .authorized, settings.alertSetting == .enabled else {
            timer?.invalidate(); timer = nil; effectiveMonitoring = false
            status = "Notifications are unavailable. Enable Still alerts in System Settings > Notifications. Capacity polling is stopped."
            return
        }
        effectiveMonitoring = thresholdValid
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.sample() }
            }
            timer?.tolerance = 60
        }
        guard policy.shouldSample(at: Date(), authorization: .allowed) else { return }
        let reading = capacity(); total = reading.total
        guard let available = reading.available, let total = reading.total, let volumeID = reading.volumeID else { status = "Capacity unavailable. Alert decisions are paused."; return }
        guard thresholdValid else { effectiveMonitoring = false; status = "Threshold no longer fits this volume. Update it to resume alerts."; return }
        effectiveMonitoring = true
        status = "Monitoring startup-volume capacity while Still runs. Last available: \(String(format: "%.1f", Double(available) / 1_000_000_000)) GB."
        let submit = policy.observe(available: available, total: total, at: Date(), volumeID: volumeID, metric: reading.metric)
        guard persist() else { return }
        if let until = policy.snoozedUntil, until > Date() { status += " Snoozed until \(until.formatted())." }
        guard submit else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your Mac is running low on space"
        content.body = "Capacity checked at \(Date().formatted(date: .omitted, time: .shortened)). Open Still to review storage and choose whether to scan."
        content.sound = .default
        content.categoryIdentifier = "Still.capacity"
        let deliveryResult = await delivery.submit {
            try await self.center.add(UNNotificationRequest(identifier: "Still.lowSpace", content: content, trigger: nil))
        }
        switch deliveryResult {
        case .accepted:
            policy.submissionAccepted(at: Date()); _ = persist()
        case .failed:
            policy.submissionFailed(); _ = persist(); status = "Notification could not be submitted. A later capacity check will retry."
        case .staleSuccess:
            center.removePendingNotificationRequests(withIdentifiers: ["Still.lowSpace"])
        case .staleFailure:
            break
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        await MainActor.run {
            if action == "Still.remindLater" { remindLater(); return }
            AppLifecycleController.shared.openWorkspace?()
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .stillAlertOpened, object: nil)
        }
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
