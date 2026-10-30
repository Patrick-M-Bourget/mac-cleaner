import Foundation
import Testing
@testable import CacheDropCore

@Test @MainActor func approvedUpdateWaitsForCleanupAndSavedWorkWithoutStoppingCleanup() async {
    let entered = AsyncStream<Void>.makeStream(), release = AsyncStream<Void>.makeStream()
    var handoffs = 0, resumed = 0
    let update = UpdateInstallation(finishWork: {
        entered.continuation.yield(())
        for await _ in release.stream { break }
    }, resumeWork: { resumed += 1 })
    let accepted = update.request(cleanupRunning: true, maintenanceRunning: false, install: { handoffs += 1 }, cancel: {})
    #expect(accepted)
    #expect(update.state == .waitingForCleanup)
    #expect(update.blocksNewWork && update.canCancel)
    #expect(handoffs == 0)
    update.workChanged(cleanupRunning: false, maintenanceRunning: false)
    var finishing = entered.stream.makeAsyncIterator()
    _ = await finishing.next()
    #expect(update.state == .finishingCurrentWork)
    #expect(handoffs == 0)
    release.continuation.yield(())
    await update.waitForPreparation()
    #expect(update.state == .installing)
    #expect(handoffs == 1 && resumed == 0)
    #expect(!update.canCancel)
    update.cancel()
    #expect(handoffs == 1 && update.blocksNewWork)
}

@Test @MainActor func cancelingPendingMaintenanceReleasesQueuedScansAndNeverInstallsLater() async {
    let queued = WorkAfterMaintenance()
    var scans = 0, installations = 0, canceled = 0
    queued.waitFor(.catalogScan) { scans += 1 }
    let update = UpdateInstallation(finishWork: {}, resumeWork: { queued.released() })
    update.request(cleanupRunning: false, maintenanceRunning: true, install: { installations += 1 }, cancel: { canceled += 1 })
    queued.released(allowingWork: !update.blocksNewWork)
    #expect(update.state == .finishingCurrentWork && scans == 0)
    update.cancel()
    #expect(!update.blocksNewWork && scans == 1 && canceled == 1)
    update.workChanged(cleanupRunning: false, maintenanceRunning: false)
    await update.waitForPreparation()
    #expect(installations == 0)
    update.request(cleanupRunning: false, maintenanceRunning: false, install: { installations += 1 }, cancel: {})
    await update.waitForPreparation()
    #expect(installations == 1)
    update.failed()
    #expect(!update.blocksNewWork)
}

@Test @MainActor func cancelingAtHeldScanWriteKeepsTimersResumedAndObsoleteInstallCannotRun() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropUpdate-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StorageTrendsHistoryStore(directory: root)
    let epoch = try await store.recordingEpoch()
    let now = Date()
    let activity = ScanActivity(startedAt: now, completedAt: now, outcome: .stopped, locations: [.init(path: "/Example")])
    let scans = ScanLifecycle(), measurements = LaterMeasurements()
    let scanBegan = AsyncStream<Void>.makeStream(), releaseScan = AsyncStream<Void>.makeStream()
    let draining = AsyncStream<Void>.makeStream(), waiting = AsyncStream<Void>.makeStream()
    let measured = AsyncStream<Bool>.makeStream()
    var installations = 0, cancellations = 0
    scans.start {
        scanBegan.continuation.yield(())
        for await _ in releaseScan.stream { break }
        _ = try? await store.recordActivity(activity, expectedEpoch: epoch)
    }
    var began = scanBegan.stream.makeAsyncIterator()
    _ = await began.next()
    let update = UpdateInstallation(finishWork: {
        scans.requestStop()
        // This ordering is the app lifecycle's: timers enter handoff before waiting on any scan write.
        await measurements.finishForLifecycle()
        draining.continuation.yield(())
        await scans.waitForCompletion()
    }, resumeWork: { measurements.resume() })
    update.request(cleanupRunning: false, maintenanceRunning: false, install: { installations += 1 }, cancel: { cancellations += 1 })
    var started = draining.stream.makeAsyncIterator()
    _ = await started.next()
    let oldPreparation = Task {
        waiting.continuation.yield(())
        await update.waitForPreparation()
    }
    var waitingStarted = waiting.stream.makeAsyncIterator()
    _ = await waitingStarted.next()
    update.cancel()
    #expect(!update.blocksNewWork && cancellations == 1)
    measurements.schedule(wait: { _ in true }) { wait in measured.continuation.yield(await wait(.seconds(60))) }
    var outcomes = measured.stream.makeAsyncIterator()
    #expect(await outcomes.next() == true)
    // A subsequent attempt may wait on the same write, but only that attempt can install.
    update.request(cleanupRunning: false, maintenanceRunning: false, install: { installations += 1 }, cancel: {})
    _ = await started.next()
    let repeated = update.request(cleanupRunning: false, maintenanceRunning: false, install: { installations += 100 }, cancel: {})
    #expect(!repeated)
    #expect(try await store.activities().isEmpty)
    releaseScan.continuation.yield(())
    releaseScan.continuation.finish()
    await oldPreparation.value
    await update.waitForPreparation()
    #expect(installations == 1)
    #expect(try await store.activities().map(\.id) == [activity.id])
    update.failed()
    measurements.schedule(wait: { _ in true }) { wait in measured.continuation.yield(await wait(.seconds(60))) }
    #expect(await outcomes.next() == true)
    await measurements.finishForLifecycle()
}

@Test @MainActor func updatePreparationFailureRestoresAvailabilityAndAllowsRetry() async {
    enum Failure: Error { case cannotFinish }
    var attempts = 0, installs = 0, canceled = 0, resumes = 0
    let update = UpdateInstallation(finishWork: {
        attempts += 1
        if attempts == 1 { throw Failure.cannotFinish }
    }, resumeWork: { resumes += 1 })
    update.request(cleanupRunning: false, maintenanceRunning: false, install: { installs += 1 }, cancel: { canceled += 1 })
    await update.waitForPreparation()
    #expect(!update.blocksNewWork && canceled == 1 && resumes == 1 && installs == 0)
    update.request(cleanupRunning: false, maintenanceRunning: false, install: { installs += 1 }, cancel: {})
    await update.waitForPreparation()
    #expect(installs == 1 && update.state == .installing)
}

@Test @MainActor func installationSkipsSleepingMeasurementsButWaitsForRunningFindingsToSave() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropUpdateMeasurement-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = root.appendingPathComponent(".npm/_cacache")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 4096).write(to: cache.appendingPathComponent("blob"))
    let catalog = Catalog(rules: fixtureRules)
    let candidate = try #require(catalog.discover(fixture: root).first)
    let approval = CatalogApproval(candidates: [candidate], dryRun: false)
    let journal = try SQLiteCleanupJournal(url: root.appendingPathComponent("history.sqlite"))
    var record = CleanupRecord(batchID: approval.id, approvedAt: approval.approvedAt, candidate: candidate, dryRun: false)
    record.state = .failed; record.mayStillBeFinishing = true; record.partlyRemoved = true
    #expect(try journal.claim(batchID: approval.id, records: [record]))
    let original = CatalogExecutionResult(batchID: approval.id, records: [record], dryRun: false, rejectedReplay: false,
                                          journalFailure: nil, estimatedBytes: candidate.estimatedBytes)
    let executor = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: FixtureNothingRunning(), home: root))
    let measurements = LaterMeasurements()
    let running = AsyncStream<Void>.makeStream(), release = AsyncStream<Void>.makeStream()
    let sleeping = AsyncStream<Void>.makeStream(), skipped = AsyncStream<Void>.makeStream()
    var installed = false
    measurements.schedule(wait: { _ in true }) { wait in
        _ = await executor.measureAgainLater(original, of: approval, wait: wait) { candidates in
            running.continuation.yield(())
            for await _ in release.stream { break }
            return [candidates[0].id: .remaining(bytes: 1)]
        }
    }
    var began = running.stream.makeAsyncIterator()
    _ = await began.next()
    measurements.schedule(wait: { _ in
        sleeping.continuation.yield(())
        let never = AsyncStream<Void> { _ in }
        for await _ in never { }
        skipped.continuation.yield(())
        return false
    }) { wait in
        if await wait(.seconds(300)) { Issue.record("Sleeping optional measurement ran during installation") }
    }
    var timer = sleeping.stream.makeAsyncIterator()
    _ = await timer.next()
    let update = UpdateInstallation(finishWork: { await measurements.finishForLifecycle() }, resumeWork: { measurements.resume() })
    update.request(cleanupRunning: false, maintenanceRunning: false, install: { installed = true }, cancel: {})
    var canceled = skipped.stream.makeAsyncIterator()
    _ = await canceled.next()
    #expect(!installed && update.blocksNewWork)
    #expect(try journal.records().first?.laterMeasurement == nil)
    release.continuation.yield(())
    await update.waitForPreparation()
    #expect(installed)
    let saved = try #require(try journal.records().first)
    #expect(saved.state == .failed && saved.partlyRemoved == true)
    #expect(saved.laterMeasurement?.finding == .remaining(bytes: 1))
    #expect(saved.laterMeasurement?.afterSeconds == 60)
}
