import Foundation
import Testing
import StorageAlerts

@Test @MainActor func resetDuringDelayedSubmissionFailureCannotChangeOffStateOrRecreatePersistence() async {
    let gate = AlertDeliveryGate()
    let began = AsyncStream<Void>.makeStream(), completed = AsyncStream<Bool>.makeStream()
    var persistedOutcomes = 0
    var status = "Monitoring"
    let pending = Task {
        let result = await gate.submit {
            began.continuation.yield(())
            for await accepted in completed.stream {
                if !accepted { throw CocoaError(.fileWriteUnknown) }
                break
            }
        }
        if result == .accepted || result == .failed { persistedOutcomes += 1; status = "Submission updated" }
        return result
    }
    var started = began.stream.makeAsyncIterator(); _ = await started.next()
    gate.invalidate(); status = "Alerts are off."
    completed.continuation.yield(false)
    #expect(await pending.value == .staleFailure)
    #expect(persistedOutcomes == 0)
    #expect(status == "Alerts are off.")
}

@Test @MainActor func currentDeliveryResultsRemainObservableAndStaleSuccessIsDistinct() async {
    let gate = AlertDeliveryGate()
    #expect(await gate.submit { } == .accepted)
    #expect(await gate.submit { throw CocoaError(.fileWriteUnknown) } == .failed)
    #expect(await gate.submit { gate.invalidate() } == .staleSuccess)
}
