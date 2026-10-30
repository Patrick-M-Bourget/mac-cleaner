import Foundation
import Testing
@testable import CacheDropCore

@Test @MainActor func lifecycleHandoffSkipsSleepingMeasurementsAndCanResume() async {
    let measurements = LaterMeasurements()
    let sleeping = AsyncStream<Void>.makeStream()
    let finished = AsyncStream<Bool>.makeStream()
    measurements.schedule(wait: { delay in
        #expect(delay == .seconds(300))
        sleeping.continuation.yield(())
        // Cancellation, not elapsed time, ends this controlled sleep.
        let never = AsyncStream<Void> { _ in }
        for await _ in never { }
        return false
    }) { wait in
        finished.continuation.yield(await wait(.seconds(300)))
    }
    var sleeps = sleeping.stream.makeAsyncIterator()
    _ = await sleeps.next()
    await measurements.finishForLifecycle()
    var outcomes = finished.stream.makeAsyncIterator()
    #expect(await outcomes.next() == false)
    await measurements.finishForLifecycle()
    // A lifecycle handoff keeps newly scheduled optional work from starting.
    measurements.schedule { _ in Issue.record("Optional work started during handoff") }
    await measurements.finishForLifecycle()
    measurements.resume()
    measurements.schedule(wait: { _ in true }) { wait in
        finished.continuation.yield(await wait(.seconds(60)))
    }
    #expect(await outcomes.next() == true)
    await measurements.finishForLifecycle()
}

private struct NoMeasurementOwnersRunning: RunningAppChecking {
    func isRunning(_ owner: RuleOwner) -> Bool? { false }
}

@Test @MainActor func lifecycleHandoffWaitsForRunningMeasurementToSaveAndSkipsItsRetry() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropLater-\(UUID())")
    let cache = home.appendingPathComponent(".npm/_cacache")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    try Data(repeating: 1, count: 4096).write(to: cache.appendingPathComponent("blob"))
    let catalog = Catalog(rules: fixtureRules)
    let candidate = try #require(catalog.discover(fixture: home).first)
    let approval = CatalogApproval(candidates: [candidate], dryRun: false)
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("history.sqlite"))
    var record = CleanupRecord(batchID: approval.id, approvedAt: approval.approvedAt, candidate: candidate, dryRun: false)
    record.state = .failed; record.mayStillBeFinishing = true; record.partlyRemoved = true
    #expect(try journal.claim(batchID: approval.id, records: [record]))
    let original = CatalogExecutionResult(batchID: approval.id, records: [record], dryRun: false, rejectedReplay: false,
                                          journalFailure: nil, estimatedBytes: candidate.estimatedBytes)
    let run = CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: NoMeasurementOwnersRunning(), home: home))
    let measurements = LaterMeasurements()
    let measuring = AsyncStream<Void>.makeStream(), release = AsyncStream<Void>.makeStream()
    let sleeperBegan = AsyncStream<Void>.makeStream(), sleeperEnded = AsyncStream<Void>.makeStream()
    var finished = false
    measurements.schedule(wait: { _ in true }) { wait in
        let result = await run.measureAgainLater(original, of: approval, wait: wait) { candidates in
            measuring.continuation.yield(())
            for await _ in release.stream { break }
            return [candidates[0].id: .remaining(bytes: 1)]
        }
        #expect(result.records[0].laterMeasurement?.finding == .remaining(bytes: 1))
        #expect(result.records[0].laterMeasurement?.afterSeconds == 60)
    }
    var started = measuring.stream.makeAsyncIterator()
    _ = await started.next()
    // A second controlled sleeper acknowledges that handoff has actually started, while the first
    // measurement is held before its journal write. No scheduling delay stands in for that handshake.
    measurements.schedule(wait: { _ in
        sleeperBegan.continuation.yield(())
        let never = AsyncStream<Void> { _ in }
        for await _ in never { }
        sleeperEnded.continuation.yield(())
        return false
    }) { wait in _ = await wait(.seconds(60)) }
    var sleeping = sleeperBegan.stream.makeAsyncIterator()
    _ = await sleeping.next()
    let handoff = Task { await measurements.finishForLifecycle(); finished = true }
    var canceled = sleeperEnded.stream.makeAsyncIterator()
    _ = await canceled.next()
    #expect(!finished)
    #expect(try journal.records().first?.laterMeasurement == nil)
    release.continuation.yield(())
    await handoff.value
    #expect(finished)
    let saved = try #require(try journal.records().first)
    #expect(saved.state == .failed && saved.partlyRemoved == true)
    #expect(saved.laterMeasurement?.finding == .remaining(bytes: 1))
    #expect(saved.laterMeasurement?.afterSeconds == 60)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let savedData = try encoder.encode([saved])
    await measurements.finishForLifecycle()
    #expect(try encoder.encode(journal.records()) == savedData)
}
