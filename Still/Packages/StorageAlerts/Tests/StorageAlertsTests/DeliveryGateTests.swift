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

@Test @MainActor func disablingDuringPendingSuccessOrFailureKeepsOffAndDiscardsLateRequest() async {
    for accepted in [true, false] {
        let gate = AlertDeliveryGate()
        let began = AsyncStream<Void>.makeStream(), completed = AsyncStream<Bool>.makeStream()
        var status = "Monitoring", savedOutcomes = 0, pendingRequest = false
        let pending = Task {
            let result = await gate.submit {
                began.continuation.yield(())
                for await succeeds in completed.stream {
                    if !succeeds { throw CocoaError(.fileWriteUnknown) }
                    pendingRequest = true
                    break
                }
            }
            switch result {
            case .accepted, .failed: savedOutcomes += 1; status = "Submission updated"
            case .staleSuccess: pendingRequest = false
            case .staleFailure: break
            }
            return result
        }
        var iterator = began.stream.makeAsyncIterator(); _ = await iterator.next()
        gate.setEnabled(false); status = "Alerts are off."; pendingRequest = false
        completed.continuation.yield(accepted)
        #expect(await pending.value == (accepted ? .staleSuccess : .staleFailure))
        #expect(savedOutcomes == 0)
        #expect(!pendingRequest)
        #expect(status == "Alerts are off.")
    }
}
