import Testing
import CacheDropCore

/// #310: a scan asked for while History holds the maintenance lease runs once the lease is released, never never.
@Test @MainActor func workAskedForDuringMaintenanceRunsOnceWhenItIsReleased() {
    let waiting = WorkAfterMaintenance()
    var ran: [String] = []
    waiting.waitFor("catalog") { ran.append("catalog") }
    waiting.waitFor("folder") { ran.append("folder") }
    waiting.waitFor("catalog") { ran.append("catalog again") } // Asked twice: runs once, as last asked.
    #expect(ran.isEmpty)
    waiting.released()
    waiting.released()
    #expect(ran == ["folder", "catalog again"])
}

@Test @MainActor func workAskedForAfterAReleaseWaitsForTheNextOne() {
    let waiting = WorkAfterMaintenance()
    var ran = 0
    waiting.released()
    waiting.waitFor("catalog") { ran += 1 }
    #expect(ran == 0)
    waiting.released()
    #expect(ran == 1)
}
