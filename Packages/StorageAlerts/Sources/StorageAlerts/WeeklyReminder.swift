import Foundation
import Combine

/// The weekly cleanup reminder's saved state (#599, Decision 143): whether it's on, since when, and what the last catalog
/// scan found ready to clean. A separate file from low-space alerts, so either can be read or reset alone.
public struct WeeklyReminderState: Sendable, Codable, Equatable {
    public var enabled = false
    /// When the reminder was turned on: its weekday is the reminder's day.
    public var enabledAt: Date?
    /// When the last catalog scan finished, and Smart clean's ticked total it found.
    public var lastScanAt: Date?
    public var readyBytes: Int64?
    private enum CodingKeys: String, CodingKey {
        case enabled = "enabled", enabledAt = "enabledAt", lastScanAt = "lastScanAt", readyBytes = "readyBytes"
    }
    public init() {}
}

/// When the one reminder is due. Pure, so the rule is tested without notifications.
public enum WeeklyReminderSchedule {
    /// Below this, Smart clean has nothing worth a reminder.
    public static let thresholdBytes: Int64 = 1_000_000_000
    /// The reminder's local hour, on the weekday it was turned on.
    public static let hour = 10

    /// The next reminder after `now`, or nil when none is due: off, nothing scanned, under the threshold, or no scan in
    /// the seven days before the day it would arrive. The first one comes at least a day after turning it on.
    public static func next(_ state: WeeklyReminderState, now: Date, calendar: Calendar) -> Date? {
        guard state.enabled, let enabledAt = state.enabledAt, let scan = state.lastScanAt, let bytes = state.readyBytes,
              bytes >= thresholdBytes, scan <= now else { return nil }
        let weekday = calendar.component(.weekday, from: enabledAt)
        let start = max(now, enabledAt.addingTimeInterval(86_400))
        guard let due = calendar.nextDate(after: start, matching: DateComponents(hour: hour, minute: 0, second: 0, weekday: weekday),
                                          matchingPolicy: .nextTime),
              let weekBefore = calendar.date(byAdding: .day, value: -7, to: due) else { return nil }
        // The reminder speaks for the week before it, counted in days, so Monday's scan counts for next Monday's reminder;
        // a scan older than that sends none.
        return scan >= calendar.startOfDay(for: weekBefore) ? due : nil
    }
}

/// System operations only. The controller owns the preference and what is scheduled.
@MainActor public protocol WeeklyReminderSystem: AnyObject {
    var allowsNotificationChanges: Bool { get }
    var now: Date { get }
    var calendar: Calendar { get }
    func authorization() async -> AlertPolicy.Authorization
    func requestAuthorization() async throws -> Bool
    func load() throws -> WeeklyReminderState
    func save(_ state: WeeklyReminderState) throws
    func reset() throws
    /// Replaces the one pending reminder with one due at `date`.
    func schedule(readyBytes: Int64, at date: Date) async throws
    func removePendingReminder()
}

/// The weekly cleanup reminder (#599): off by default; turning it on is the only time it asks for notification
/// permission. It never scans or cleans: each catalog scan says what Smart clean has, and the OS delivers the one
/// pending reminder, so it arrives even while CacheDrop is closed.
@MainActor public final class WeeklyReminderController: ObservableObject {
    @Published public private(set) var enabled = false
    @Published public private(set) var authorization: AlertPolicy.Authorization = .unknown
    @Published public private(set) var authorizationChecked = false
    /// The saved state couldn't be read or written: the toggle says so and stays off.
    @Published public private(set) var stateUnavailable = false
    /// When the pending reminder arrives; nil when none is planned.
    @Published public private(set) var nextReminder: Date?
    private var state = WeeklyReminderState()
    /// Smart clean's ticked total at the last scan, for the status line.
    public var lastReadyBytes: Int64? { state.readyBytes }
    private let system: any WeeklyReminderSystem
    /// Schedule changes run one after another, so a slower earlier one never lands after a later one.
    private var scheduling: Task<Void, Never>?

    public init(system: any WeeklyReminderSystem) {
        self.system = system
        guard system.allowsNotificationChanges else { return }
        do { state = try system.load(); enabled = state.enabled }
        catch { stateUnavailable = true }
    }

    public func setEnabled(_ on: Bool) async {
        guard system.allowsNotificationChanges, !stateUnavailable, on != enabled else { return }
        state.enabled = on
        state.enabledAt = on ? system.now : nil
        enabled = on
        guard persist() else { return }
        if on {
            if await readAuthorization() == .unknown { _ = try? await system.requestAuthorization() }
            _ = await readAuthorization()
        }
        await reschedule()
    }

    /// Every catalog scan ends here with Smart clean's ticked total. Kept in memory while off, so turning the reminder on
    /// uses the scan already shown.
    public func scanFinished(readyBytes: Int64) async {
        state.lastScanAt = system.now
        state.readyBytes = readyBytes
        guard enabled, persist() else { return }
        await reschedule()
    }

    /// The app became active: notification permission may have changed in System Settings.
    public func activated() async {
        guard system.allowsNotificationChanges else { return }
        if enabled { await reschedule() } else { _ = await readAuthorization() }
    }

    /// Reset (Saved data): the pending reminder goes, then the saved state.
    public func resetPreferences() throws {
        scheduling?.cancel()
        system.removePendingReminder()
        state = WeeklyReminderState(); enabled = false; nextReminder = nil; stateUnavailable = false
        try system.reset()
    }

    private func readAuthorization() async -> AlertPolicy.Authorization {
        let settings = await system.authorization()
        authorization = settings; authorizationChecked = true
        return settings
    }

    private func persist() -> Bool {
        do { try system.save(state); return true }
        catch {
            stateUnavailable = true; enabled = false; nextReminder = nil
            system.removePendingReminder()
            return false
        }
    }

    private func reschedule() async {
        let previous = scheduling
        let task = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            // Read every time: at a login launch CacheDrop may scan without ever becoming active.
            let allowed = enabled ? await readAuthorization() == .allowed : false
            guard !Task.isCancelled else { return }
            let due = enabled && allowed ? WeeklyReminderSchedule.next(state, now: system.now, calendar: system.calendar) : nil
            guard let due, let bytes = state.readyBytes else {
                system.removePendingReminder(); nextReminder = nil; return
            }
            do { try await system.schedule(readyBytes: bytes, at: due); nextReminder = due }
            catch { system.removePendingReminder(); nextReminder = nil }
        }
        scheduling = task
        await task.value
    }
}
