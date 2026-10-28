import Testing
import CacheDropCore

/// #310: a scan asked for while History holds the maintenance lease runs once the lease is released, never never.
@Test @MainActor func workAskedForDuringMaintenanceRunsOnceWhenItIsReleased() {
    let waiting = WorkAfterMaintenance()
    var ran: [String] = []
    waiting.waitFor(.catalogScan) { ran.append("catalog") }
    waiting.waitFor(.folderScan) { ran.append("folder") }
    waiting.waitFor(.catalogScan) { ran.append("catalog again") } // Asked twice: runs once, as last asked.
    #expect(ran.isEmpty)
    waiting.released()
    waiting.released()
    #expect(ran == ["folder", "catalog again"])
}

@Test @MainActor func workAskedForAfterAReleaseWaitsForTheNextOne() {
    let waiting = WorkAfterMaintenance()
    var ran = 0
    waiting.released()
    waiting.waitFor(.catalogScan) { ran += 1 }
    #expect(ran == 0)
    waiting.released()
    #expect(ran == 1)
}

/// #332: a rescan deferred by the lease still rechecks the remembered folders once when it runs, even when a plain scan
/// of the same kind is asked for after it. A plain scan alone never does.
@Test @MainActor func aRescanDeferredByTheLeaseStillRechecksRememberedFolders() {
    let waiting = WorkAfterMaintenance()
    var runs: [Bool] = []
    waiting.waitFor(.catalogScan, rescan: true) { runs.append($0) }
    waiting.waitFor(.catalogScan, rescan: false) { runs.append($0) }
    waiting.released()
    waiting.released()
    #expect(runs == [true])

    waiting.waitFor(.catalogScan, rescan: false) { runs.append($0) }
    waiting.released()
    #expect(runs == [true, false])
}
