import Foundation
import Testing
import StillCore

@MainActor private final class MaintenanceLifecycleFixture: HistoryMaintenanceLifecycle {
    var operationActive = false
    var quitRequested = false
    var quitReleased = false
    var maintenanceActive = false { didSet { if !maintenanceActive && quitRequested { quitReleased = true } } }
    var mayExecuteCleanup: Bool { !operationActive && !maintenanceActive }
}

@Test @MainActor func automaticHistoryMaintenanceBlocksCleanupAndDefersQuitAcrossAwait() async throws {
    let lifecycle = MaintenanceLifecycleFixture()
    let began = AsyncStream<Bool>.makeStream(), finish = AsyncStream<Bool>.makeStream()
    let loading = Task {
        try await HistoryLoadCoordinator.load(lifecycle: lifecycle) { mayMaintain in
            began.continuation.yield(mayMaintain)
            for await succeeds in finish.stream {
                if !succeeds { throw CocoaError(.fileWriteUnknown) }
                break
            }
            return 7
        }
    }
    var iterator = began.stream.makeAsyncIterator()
    #expect(await iterator.next() == true)
    #expect(!lifecycle.mayExecuteCleanup)
    lifecycle.quitRequested = true
    #expect(!lifecycle.quitReleased)
    finish.continuation.yield(true)
    #expect(try await loading.value == 7)
    #expect(lifecycle.mayExecuteCleanup)
    #expect(lifecycle.quitReleased)
}

@Test @MainActor func historyLoadUsesReadOnlyDuringCleanupAndReleasesLeaseOnFailure() async {
    let lifecycle = MaintenanceLifecycleFixture()
    lifecycle.operationActive = true
    let readOnly = await HistoryLoadCoordinator.load(lifecycle: lifecycle) { $0 }
    #expect(!readOnly)
    #expect(!lifecycle.maintenanceActive)
    lifecycle.operationActive = false
    do {
        _ = try await HistoryLoadCoordinator.load(lifecycle: lifecycle) { mayMaintain in
            #expect(mayMaintain)
            throw CocoaError(.fileReadUnknown)
        } as Int
        Issue.record("Expected controlled repository failure")
    } catch { }
    #expect(!lifecycle.maintenanceActive)
    #expect(lifecycle.mayExecuteCleanup)
    lifecycle.maintenanceActive = true
    let alreadyMaintaining = await HistoryLoadCoordinator.load(lifecycle: lifecycle) { $0 }
    #expect(!alreadyMaintaining)
    #expect(lifecycle.maintenanceActive)
}
