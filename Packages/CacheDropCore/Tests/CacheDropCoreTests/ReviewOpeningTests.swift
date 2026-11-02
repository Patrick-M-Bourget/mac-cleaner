import Foundation
import Testing
@testable import CacheDropCore

// #463, Decision 126: the review sheet opens at the click with its checks running in it, and Clean up waits for them.
// The review is a plain value here; the checks themselves are CandidateCheck's and tested there.

@Test func theSheetOpensAtTheClickWithItsChecksRunningAndCleanUpUnavailable() {
    var opening = ReviewOpening<String>()
    #expect(opening.isOpen(for: .plan) == false)
    let attempt = opening.open(.plan, revision: 3)
    #expect(attempt != nil)
    #expect(opening.isOpen(for: .plan), "The sheet shows before any check finishes")
    #expect(opening.isOpen(for: .smartClean) == false, "Only the page that clicked opens its sheet")
    #expect(opening.isChecking)
    #expect(opening.review == nil, "Clean up has nothing to run until the checks finish")
}

@Test func cleanUpBecomesAvailableOnceTheChecksFinishForTheSameChoices() throws {
    var opening = ReviewOpening<String>()
    let opened = opening.open(.smartClean, revision: 7), attempt = try #require(opened)
    let outcome = opening.finish(attempt, with: .success("checked"), revision: 7)
    #expect(outcome == .ready)
    #expect(opening.review == "checked")
    #expect(opening.isChecking == false)
    #expect(opening.isOpen(for: .smartClean))
}

@Test func checksThatFinishAfterTheChoicesChangedNeverMakeCleanUpAvailable() throws {
    var opening = ReviewOpening<String>()
    let opened = opening.open(.plan, revision: 1), attempt = try #require(opened)
    // A tick on the page while the checks ran: what they checked is no longer what the page would clean (#307).
    let outcome = opening.finish(attempt, with: .success("checked"), revision: 2)
    #expect(outcome == .choicesChanged)
    #expect(opening.review == nil)
    #expect(opening.isOpen(for: .plan) == false, "The sheet closes and the page says the choices changed")
}

@Test func closingTheSheetDropsItsChecksAndAnEarlierClicksChecksNeverFillALaterSheet() throws {
    var opening = ReviewOpening<String>()
    let first = opening.open(.plan, revision: 4), earlier = try #require(first)
    opening.close()
    #expect(opening.isOpen(for: .plan) == false)
    #expect(opening.finish(earlier, with: .success("old"), revision: 4) == .dropped, "Cancelled: nothing opens again")
    #expect(opening.isOpen(for: .plan) == false)

    let second = opening.open(.plan, revision: 4), later = try #require(second)
    #expect(opening.finish(earlier, with: .success("old"), revision: 4) == .dropped, "Same choices, but another click's checks")
    #expect(opening.isChecking)
    #expect(opening.review == nil)
    #expect(opening.finish(later, with: .success("new"), revision: 4) == .ready)
    #expect(opening.review == "new")
}

private struct Unreadable: Error {}

@Test func checksThatFailCloseTheSheetSoThePageCanSayWhy() throws {
    var opening = ReviewOpening<String>()
    let opened = opening.open(.applications, revision: 2), attempt = try #require(opened)
    #expect(opening.finish(attempt, with: .failure(Unreadable()), revision: 2) == .failed)
    #expect(opening.isOpen(for: .applications) == false)
    #expect(opening.review == nil)
    let again = opening.open(.applications, revision: 2), retry = try #require(again, "A new click checks again")
    // Why the checks failed (settings unreadable, nothing left to clean) says more than the choices having moved meanwhile.
    #expect(opening.finish(retry, with: .failure(Unreadable()), revision: 3) == .failed)
}

@Test func onlyTheOpenPagesOwnChoicesChangingCloseItsSheetWhileCheckingOrReady() throws {
    var opening = ReviewOpening<String>()
    _ = opening.open(.smartClean, revision: 5)
    #expect(opening.choicesChanged(.plan, to: 9) == false, "Another page's choices leave this sheet open (Decision 54)")
    #expect(opening.choicesChanged(.smartClean, to: 5) == false, "Same revision: nothing changed")
    #expect(opening.isChecking)
    #expect(opening.choicesChanged(.smartClean, to: 6) == true, "Closed while checking")
    #expect(opening.isOpen(for: .smartClean) == false)

    let opened = opening.open(.smartClean, revision: 6), attempt = try #require(opened)
    _ = opening.finish(attempt, with: .success("checked"), revision: 6)
    #expect(opening.choicesChanged(.smartClean, to: 7) == true, "Closed when ready too")
    #expect(opening.review == nil)
    #expect(opening.choicesChanged(.smartClean, to: 8) == false, "Nothing open to close")
}

@Test func aSecondClickWhileASheetIsOpenStartsNoOtherChecks() {
    var opening = ReviewOpening<String>()
    _ = opening.open(.plan, revision: 1)
    #expect(opening.open(.applications, revision: 1) == nil)
    #expect(opening.open(.plan, revision: 1) == nil)
    #expect(opening.isOpen(for: .applications) == false)
}

// #563, Decision 126: Cancel stops the click-time checks at their next step; a step already running finishes and its result is dropped.

@Test func cancelledChecksStopBeforeTheirNextStep() async {
    let started = StepLog()
    let checks = Task {
        try await ReviewCheckSteps.run({
            await started.record("setup")
            withUnsafeCurrentTask { $0?.cancel() }
            return 1
        }, then: { (setup: Int) -> Int in
            await started.record("item checks")
            return setup + 1
        })
    }
    let result = await checks.result
    #expect(await started.steps == ["setup"], "The step running at Cancel finishes; the next never starts")
    #expect(throws: CancellationError.self) { try result.get() }
}

@Test func checksThatAreNotCancelledRunEveryStep() async throws {
    let started = StepLog()
    let value = try await ReviewCheckSteps.run({ await started.record("setup"); return 1 }, then: { (setup: Int) -> Int in
        await started.record("item checks"); return setup + 1
    })
    #expect(value == 2)
    #expect(await started.steps == ["setup", "item checks"])
}

@Test func checksCancelledBeforeTheyStartRunNoStep() async {
    let started = StepLog()
    let checks = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await ReviewCheckSteps.run({ await started.record("setup") }, then: { await started.record("item checks") })
    }
    await #expect(throws: CancellationError.self) { try await checks.value }
    #expect(await started.steps.isEmpty)
}

private actor StepLog {
    private(set) var steps: [String] = []
    func record(_ step: String) { steps.append(step) }
}
