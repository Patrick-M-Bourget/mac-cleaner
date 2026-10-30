import Foundation
import Testing
import StorageAlerts

@Test @MainActor func disabledLateFailureReleasesOwnedReservationAndRetriesAfterCadenceIncludingRestart() async throws {
    for restart in [false, true] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropAlertReservation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AlertStateStore(url: root.appendingPathComponent("episode.json"))
        var policy = AlertPolicy(); policy.enabled = true
        let time = Date(timeIntervalSince1970: 1_000_000)
        let initial = policy.observe(available: 10_000_000_000, total: 100_000_000_000, at: time)
        #expect(initial)
        let reservation = try #require(policy.pendingSubmission)
        try store.save(policy)
        let gate = AlertDeliveryGate()
        let began = AsyncStream<Void>.makeStream(), completed = AsyncStream<Bool>.makeStream()
        var status = "Monitoring"
        let request = Task {
            await gate.submit {
                began.continuation.yield(())
                for await accepted in completed.stream { if !accepted { throw CocoaError(.fileWriteUnknown) }; break }
            }
        }
        var iterator = began.stream.makeAsyncIterator(); _ = await iterator.next()
        policy.enabled = false; gate.setEnabled(false); status = "Alerts are off."
        try store.save(policy)
        completed.continuation.yield(false)
        let result = await request.value
        #expect(result == .staleFailure)
        if policy.reconcileSubmission(result, reservation: reservation, at: time.addingTimeInterval(10)) { try store.save(policy) }
        if result == .failed { status = "Submission failed" }
        #expect(status == "Alerts are off.")
        var resumed = restart ? try store.load() : policy
        resumed.enabled = true
        let early = resumed.observe(available: 10_000_000_000, total: 100_000_000_000, at: time.addingTimeInterval(899))
        #expect(!early)
        let retry = resumed.observe(available: 10_000_000_000, total: 100_000_000_000, at: time.addingTimeInterval(900))
        #expect(retry)
    }
}

@Test @MainActor func acceptedUncertainAndResetReservationsCannotBeReleasedByLateFailure() async throws {
    let time = Date(timeIntervalSince1970: 1_000_000)
    for disposition in ["accepted", "uncertain", "reset", "replacement"] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropAlertReservation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AlertStateStore(url: root.appendingPathComponent("episode.json"))
        var policy = AlertPolicy(); policy.enabled = true
        let initial = policy.observe(available: 10_000_000_000, total: 100_000_000_000, at: time)
        #expect(initial)
        let reservation = try #require(policy.pendingSubmission)
        policy.enabled = false
        try store.save(policy)
        switch disposition {
        case "accepted":
            let accepted = policy.reconcileSubmission(.staleSuccess, reservation: reservation, at: time)
            #expect(accepted)
            try store.save(policy)
            policy = try store.load()
        case "uncertain": policy = try store.load()
        case "reset":
            policy = AlertPolicy()
            try FileManager.default.removeItem(at: store.url)
        default:
            policy.enabled = true
            _ = policy.observe(available: 50_000_000_000, total: 100_000_000_000, at: time.addingTimeInterval(900))
            let next = policy.observe(available: 10_000_000_000, total: 100_000_000_000, at: time.addingTimeInterval(901))
            #expect(next)
        }
        let changed = policy.reconcileSubmission(.staleFailure, reservation: reservation, at: time.addingTimeInterval(902))
        #expect(!changed)
        if changed { try store.save(policy) }
        if disposition == "reset" { #expect(!FileManager.default.fileExists(atPath: store.url.path)) }
        policy.enabled = true
        let retry = policy.observe(available: 10_000_000_000, total: 100_000_000_000, at: time.addingTimeInterval(1801))
        #expect(retry == (disposition == "reset"))
    }
}
