import Foundation
import Testing
import StillCore

@MainActor private final class ControlledCapacitySystem: CapacityRefreshSystem {
    var now = Date(timeIntervalSince1970: 1_000)
    var reads: [(@MainActor @Sendable (StartupCapacityReading) -> Void)] = []
    var expirations: [UUID: (Date, @MainActor @Sendable () -> Void)] = [:]
    func readStartupCapacity(_ completed: @escaping @MainActor @Sendable (StartupCapacityReading) -> Void) { reads.append(completed) }
    func deadline(after seconds: TimeInterval, _ expired: @escaping @MainActor @Sendable () -> Void) -> () -> Void {
        let id = UUID(); expirations[id] = (now.addingTimeInterval(seconds), expired)
        return { self.expirations.removeValue(forKey: id) }
    }
    func advance(_ seconds: TimeInterval) {
        now.addTimeInterval(seconds)
        let due = expirations.filter { $0.value.0 <= now }
        for (id, value) in due { expirations.removeValue(forKey: id); value.1() }
    }
    func finish(_ index: Int = 0, available: Int64? = 40, total: Int64? = 512, metric: String = "important") {
        reads[index](StartupCapacityReading(available: available, total: total, volumeID: "startup", metric: metric, observedAt: now))
    }
}

@Test @MainActor func capacityLaunchPublishesCurrentStartupEvidence() {
    let system = ControlledCapacitySystem()
    let capacity = CapacityRefreshController(system: system)
    capacity.request(.launch)
    #expect(capacity.isRefreshing)
    #expect(capacity.reading == nil)
    guard !system.reads.isEmpty else { Issue.record("Launch must request startup capacity"); return }
    system.finish()
    #expect(capacity.reading?.available == 40)
    #expect(capacity.reading?.observedAt == Date(timeIntervalSince1970: 1_000))
    #expect(!capacity.isRefreshing)
    #expect(!capacity.failed)
}

@Test @MainActor func capacityFailureRetainsEvidenceAndPartialMetadataRecovers() {
    let system = ControlledCapacitySystem()
    let capacity = CapacityRefreshController(system: system)
    capacity.request(.launch); system.finish()
    let original = capacity.reading
    system.advance(2); capacity.request(.manual)
    #expect(capacity.reading == original)
    system.finish(1, available: -1)
    #expect(capacity.failed)
    #expect(capacity.reading == original)
    #expect(capacity.attemptedAt == Date(timeIntervalSince1970: 1_002))
    capacity.request(.manual); system.finish(2, available: 0, total: nil, metric: "available")
    #expect(!capacity.failed)
    #expect(capacity.reading?.available == 0)
    #expect(capacity.reading?.total == nil)
    capacity.request(.manual); system.finish(3, available: 513, total: 512)
    #expect(capacity.failed)
    #expect(capacity.reading?.available == 0)
    capacity.request(.manual); system.finish(4, available: 70, total: -1)
    #expect(!capacity.failed)
    #expect(capacity.reading?.available == 70)
    #expect(capacity.reading?.total == nil)
    capacity.request(.manual); system.finish(5, available: nil)
    #expect(capacity.failed)
    #expect(capacity.reading?.available == 70)
}

@Test @MainActor func capacityForegroundCadenceAndExplicitTriggersRemainIndependent() {
    let system = ControlledCapacitySystem()
    let capacity = CapacityRefreshController(system: system)
    capacity.request(.launch); system.finish()
    capacity.request(.launch); capacity.request(.foreground)
    #expect(system.reads.count == 1)
    system.advance(29); capacity.request(.foreground)
    #expect(system.reads.count == 1)
    system.advance(1); capacity.request(.foreground)
    #expect(capacity.isRefreshing)
    #expect(system.reads.count == 2)
    system.finish(1, available: 50)
    for trigger in [CapacityRefreshController.Trigger.manual, .alertOpened, .scanEnded, .cleanupEnded] {
        let index = system.reads.count
        capacity.request(trigger)
        #expect(system.reads.count == index + 1)
        system.finish(index, available: Int64(60 + index))
    }
    let last = capacity.reading
    let failureIndex = system.reads.count
    capacity.request(.manual); system.finish(failureIndex, available: nil)
    capacity.request(.foreground)
    #expect(system.reads.count == failureIndex + 2)
    #expect(capacity.reading == last)
    system.advance(100)
    #expect(system.reads.count == failureIndex + 2) // Time alone never polls/retries.
}

@Test @MainActor func capacityCoalescesOverlapButHonorsPostActionFreshness() {
    let system = ControlledCapacitySystem()
    let capacity = CapacityRefreshController(system: system)
    capacity.request(.launch)
    system.advance(1)
    capacity.request(.foreground); capacity.request(.manual); capacity.request(.alertOpened)
    capacity.request(.scanEnded); capacity.request(.cleanupEnded)
    #expect(system.reads.count == 1)
    system.finish(0, available: 40)
    #expect(capacity.isRefreshing)
    #expect(system.reads.count == 2)
    #expect(capacity.attemptedAt == Date(timeIntervalSince1970: 1_001))
    guard system.reads.count > 1 else { Issue.record("Post-action capacity needs a trailing fresh read"); return }
    system.advance(1); system.finish(1, available: 90)
    #expect(!capacity.isRefreshing)
    #expect(capacity.reading?.available == 90)
    system.finish(0, available: 10) // A duplicated old callback cannot replace current evidence.
    #expect(capacity.reading?.available == 90)
}

@Test @MainActor func capacityTimeoutRetainsEvidenceAndIgnoresLateReplies() {
    let system = ControlledCapacitySystem()
    let capacity = CapacityRefreshController(system: system)
    capacity.request(.launch)
    system.advance(9)
    #expect(capacity.isRefreshing)
    system.advance(1)
    #expect(!capacity.isRefreshing)
    #expect(capacity.failed)
    #expect(capacity.reading == nil)
    system.finish(0, available: 99)
    #expect(capacity.reading == nil)
    capacity.request(.foreground)
    guard system.reads.count > 1 else { Issue.record("Expired read must allow retry"); return }
    system.finish(1, available: 70)
    #expect(!capacity.failed)
    let retained = capacity.reading
    capacity.request(.manual)
    system.advance(10)
    #expect(capacity.failed)
    #expect(!capacity.isRefreshing)
    #expect(capacity.reading == retained)
    capacity.request(.manual)
    system.finish(2, available: 10)
    #expect(capacity.isRefreshing)
    #expect(capacity.reading == retained)
    system.finish(3, available: 80)
    #expect(!capacity.failed)
    #expect(capacity.reading?.available == 80)
    system.advance(100)
    #expect(system.reads.count == 4)
    #expect(!capacity.failed)
}

@Test @MainActor func capacityExpiredPreActionDemandStillReceivesOneFreshRead() {
    let system = ControlledCapacitySystem()
    let capacity = CapacityRefreshController(system: system)
    capacity.request(.launch)
    capacity.request(.cleanupEnded); capacity.request(.scanEnded)
    system.advance(10)
    #expect(capacity.isRefreshing)
    #expect(capacity.failed)
    #expect(system.reads.count == 2)
    system.finish(0, available: 90)
    #expect(capacity.reading == nil)
    system.finish(1, available: 20)
    #expect(!capacity.isRefreshing)
    #expect(!capacity.failed)
    #expect(capacity.reading?.available == 20)
}
