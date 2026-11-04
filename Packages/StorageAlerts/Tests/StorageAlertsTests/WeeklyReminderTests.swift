import Foundation
import Testing
import StorageAlerts

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()
/// Monday 2 November 2026, 09:00 UTC.
private let monday9 = utc.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))!
private func day(_ n: Int, hour: Int = 9) -> Date { utc.date(byAdding: DateComponents(day: n, hour: hour - 9), to: monday9)! }
private let gb: Int64 = 1_000_000_000

private func state(enabledAt: Date = monday9, scan: Date?, bytes: Int64? = 12 * gb) -> WeeklyReminderState {
    var state = WeeklyReminderState()
    state.enabled = true; state.enabledAt = enabledAt; state.lastScanAt = scan; state.readyBytes = bytes
    return state
}

@Suite struct WeeklyReminderScheduleTests {
    @Test func comesAWeekLaterAtTenOnTheDayItWasTurnedOn() {
        // Turned on Monday 09:00, scanned the same day: next Monday 10:00, not an hour later.
        #expect(WeeklyReminderSchedule.next(state(scan: monday9), now: monday9, calendar: utc) == day(7, hour: 10))
    }
    @Test func noReminderInAWeekWithoutAScan() {
        // The scan was Monday; by Tuesday of the next week the coming reminder (Monday after) has no scan in its week.
        #expect(WeeklyReminderSchedule.next(state(scan: monday9), now: day(8), calendar: utc) == nil)
        // A scan during that week brings it back.
        #expect(WeeklyReminderSchedule.next(state(scan: day(10)), now: day(10), calendar: utc) == day(14, hour: 10))
    }
    @Test func onlyAboveTheThreshold() {
        #expect(WeeklyReminderSchedule.next(state(scan: monday9, bytes: gb - 1), now: monday9, calendar: utc) == nil)
        #expect(WeeklyReminderSchedule.next(state(scan: monday9, bytes: gb), now: monday9, calendar: utc) != nil)
        #expect(WeeklyReminderSchedule.next(state(scan: monday9, bytes: nil), now: monday9, calendar: utc) == nil)
    }
    @Test func offOrNeverScannedSendsNothing() {
        var off = state(scan: monday9); off.enabled = false
        #expect(WeeklyReminderSchedule.next(off, now: monday9, calendar: utc) == nil)
        #expect(WeeklyReminderSchedule.next(state(scan: nil), now: monday9, calendar: utc) == nil)
    }
    @Test func atMostOncePerWeek() {
        // Each reminder is the next 10:00 slot on the same weekday after now, so any two are a week apart.
        let reminders = (0..<60).compactMap { hour -> Date? in
            let now = monday9.addingTimeInterval(Double(hour) * 3 * 3_600 + 7 * 86_400)
            return WeeklyReminderSchedule.next(state(scan: now), now: now, calendar: utc)
        }
        let distinct = Set(reminders).sorted()
        #expect(distinct.count >= 2)
        for (a, b) in zip(distinct, distinct.dropFirst()) { #expect(b.timeIntervalSince(a) == 7 * 86_400) }
    }
    @Test func savedKeysArePinned() throws {
        let stored = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state(scan: monday9))) as? [String: Any]
        #expect(Set(stored?.keys ?? [:].keys) == ["enabled", "enabledAt", "lastScanAt", "readyBytes"])
    }
}

@MainActor private final class FakeReminderSystem: WeeklyReminderSystem {
    var allowsNotificationChanges = true
    var now = monday9
    var calendar = utc
    var settings: AlertPolicy.Authorization = .unknown
    var grant = true
    var requests = 0
    var saved: WeeklyReminderState?
    var pending: (bytes: Int64, date: Date)?
    var scheduled = 0
    func authorization() async -> AlertPolicy.Authorization { settings }
    func requestAuthorization() async throws -> Bool { requests += 1; settings = grant ? .allowed : .denied; return grant }
    func load() throws -> WeeklyReminderState { saved ?? WeeklyReminderState() }
    func save(_ state: WeeklyReminderState) throws { saved = state }
    func reset() throws { saved = nil }
    func schedule(readyBytes: Int64, at date: Date) async throws { pending = (readyBytes, date); scheduled += 1 }
    func removePendingReminder() { pending = nil }
}

@MainActor @Suite struct WeeklyReminderControllerTests {
    @Test func offByDefaultAndScansNeverAskOrSchedule() async {
        let system = FakeReminderSystem()
        let controller = WeeklyReminderController(system: system)
        #expect(!controller.enabled)
        await controller.scanFinished(readyBytes: 12 * gb)
        await controller.activated()
        #expect(system.requests == 0, "Only turning it on asks for permission")
        #expect(system.pending == nil && system.saved == nil)
    }
    @Test func turningOnAsksOnceAndUsesTheScanAlreadyShown() async {
        let system = FakeReminderSystem()
        let controller = WeeklyReminderController(system: system)
        await controller.scanFinished(readyBytes: 12 * gb)
        await controller.setEnabled(true)
        #expect(system.requests == 1)
        #expect(system.pending?.bytes == 12 * gb)
        #expect(system.pending?.date == day(7, hour: 10))
        #expect(controller.nextReminder == day(7, hour: 10))
        await controller.setEnabled(false)
        await controller.setEnabled(true)
        #expect(system.requests == 1, "Permission already answered is not asked again")
    }
    @Test func aScanBelowTheThresholdOrACleanupRemovesIt() async {
        let system = FakeReminderSystem(); system.settings = .allowed
        let controller = WeeklyReminderController(system: system)
        await controller.setEnabled(true)
        #expect(system.pending == nil, "Nothing scanned yet")
        await controller.scanFinished(readyBytes: 12 * gb)
        #expect(system.pending != nil)
        await controller.scanFinished(readyBytes: 200_000_000) // the rescan after a cleanup
        #expect(system.pending == nil && controller.nextReminder == nil)
    }
    @Test func deniedPermissionSchedulesNothing() async {
        let system = FakeReminderSystem(); system.grant = false
        let controller = WeeklyReminderController(system: system)
        await controller.scanFinished(readyBytes: 12 * gb)
        await controller.setEnabled(true)
        #expect(controller.authorization == .denied)
        #expect(system.pending == nil)
        // Allowed later in System Settings: picked up when CacheDrop is active again.
        system.settings = .allowed
        await controller.activated()
        #expect(system.pending != nil)
    }
    @Test func turningOffAndResetRemoveThePendingReminder() async throws {
        let system = FakeReminderSystem(); system.settings = .allowed
        let controller = WeeklyReminderController(system: system)
        await controller.setEnabled(true)
        await controller.scanFinished(readyBytes: 12 * gb)
        await controller.setEnabled(false)
        #expect(system.pending == nil && system.saved?.enabled == false)
        await controller.setEnabled(true)
        await controller.scanFinished(readyBytes: 12 * gb)
        try controller.resetPreferences()
        #expect(system.pending == nil && system.saved == nil && !controller.enabled)
    }
    @Test func aLaunchScanKeepsTheReminderWithoutTheAppBecomingActive() async {
        let system = FakeReminderSystem(); system.settings = .allowed
        await WeeklyReminderController(system: system).setEnabled(true)
        // Start at Login: a new controller, no activation, and the launch scan ends.
        let relaunched = WeeklyReminderController(system: system)
        await relaunched.scanFinished(readyBytes: 12 * gb)
        #expect(system.pending?.bytes == 12 * gb)
    }
    @Test func theSavedChoiceComesBackAtLaunch() async {
        let system = FakeReminderSystem(); system.settings = .allowed
        await WeeklyReminderController(system: system).setEnabled(true)
        let relaunched = WeeklyReminderController(system: system)
        #expect(relaunched.enabled)
        // Disposable test runs never read or change it.
        system.allowsNotificationChanges = false
        #expect(!WeeklyReminderController(system: system).enabled)
    }
}
