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
    private let center = UNUserNotificationCenter.current()
    static var futureEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--future-milestones") }

    override init() {
        super.init()
        if Self.futureEnabled { center.delegate = self }
    }
    var threshold: Int64? {
        guard let gb = Double(thresholdGB), gb.isFinite, gb >= 1, gb < Double(Int64.max) / 1_000_000_000 else { return nil }
        return Int64(gb * 1_000_000_000)
    }
    var thresholdValid: Bool { threshold.map { AlertPolicy.validThreshold($0, total: total) } ?? false }

    func stopForTermination() {
        timer?.invalidate(); timer = nil; effectiveMonitoring = false
    }
    func configure() {
        guard Self.futureEnabled else { return }
        total = capacity().total
    }
    func setEnabled(_ enabled: Bool) async {
        guard Self.futureEnabled else { return }
        requested = enabled
        policy.enabled = enabled
        if !enabled {
            effectiveMonitoring = false
            timer?.invalidate(); timer = nil
            center.removePendingNotificationRequests(withIdentifiers: ["Still.lowSpace"])
            status = "Alerts are off."; return
        }
        guard thresholdValid, let threshold else { requested = false; policy.enabled = false; status = "Enter at least 1 GB and less than startup-volume capacity."; return }
        policy.thresholdBytes = threshold
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
        if requested { await sample() }
    }
    func activated() async {
        guard requested else { return }
        await sample()
    }
    private func capacity() -> (available: Int64?, total: Int64?) {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (values?.volumeAvailableCapacityForImportantUsage, values?.volumeTotalCapacity.map(Int64.init))
    }
    private func sample() async {
        guard Self.futureEnabled, requested, !sampling else { return }
        sampling = true
        defer { sampling = false }
        let settings = await center.notificationSettings()
        guard requested else { return }
        guard settings.authorizationStatus == .authorized, settings.alertSetting == .enabled else {
            effectiveMonitoring = false
            timer?.invalidate(); timer = nil
            status = "Notifications are unavailable. Enable Still alerts in System Settings > Notifications. Capacity polling is stopped."
            return
        }
        effectiveMonitoring = true
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.sample() }
            }
            timer?.tolerance = 60
        }
        guard policy.shouldSample(at: Date(), authorization: .allowed) else { return }
        let reading = capacity(); total = reading.total
        guard let available = reading.available, let total = reading.total else { status = "Capacity unavailable. Alert decisions are paused."; return }
        guard thresholdValid else { effectiveMonitoring = false; status = "Threshold no longer fits this volume. Update it to resume alerts."; return }
        status = "Monitoring startup-volume capacity while Still runs. Last available: \(String(format: "%.1f", Double(available) / 1_000_000_000)) GB."
        guard policy.observe(available: available, total: total) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your Mac is running low on space"
        content.body = "Capacity checked at \(Date().formatted(date: .omitted, time: .shortened)). Open Still to review storage and choose whether to scan."
        content.sound = .default
        do { try await center.add(UNNotificationRequest(identifier: "Still.lowSpace", content: content, trigger: nil)) }
        catch { policy.submissionFailed(); status = "Notification could not be submitted. A later capacity check will retry." }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run {
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
        VStack(alignment: .leading, spacing: 20) {
            Text("Storage alerts").font(.largeTitle.weight(.semibold))
            Text("Choose a minimum available-space threshold. Alerts check capacity only, about every 15 minutes while awake. Opening an alert offers a scan; it never starts one.").foregroundStyle(.secondary)
            HStack {
                TextField("Minimum available space (GB)", text: $controller.thresholdGB).frame(width: 180)
                Text("GB · decimal units").foregroundStyle(.secondary)
                Button("Apply threshold") { Task { await controller.applyThreshold() } }.disabled(!controller.thresholdValid)
            }
            Text("Valid range: at least 1 GB and below startup-volume capacity. Suggested: 40 GB.").font(.caption).foregroundStyle(.secondary)
            Toggle("Notify me when space is low", isOn: Binding(get: { controller.requested }, set: { enabled in Task { await controller.setEnabled(enabled) } }))
                .disabled(!controller.requested && !controller.thresholdValid)
            Text(controller.status).accessibilityIdentifier("storageAlertStatus")
            LoginSettingsView()
            Button("Open System Settings") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
            Text("This development capability checks capacity only; it does not scan folders or clean files.").font(.caption).foregroundStyle(.secondary)
        }.task { controller.configure() }
    }
}
