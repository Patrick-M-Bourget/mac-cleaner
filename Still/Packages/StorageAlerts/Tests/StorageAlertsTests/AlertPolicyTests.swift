import Foundation
import Testing
@testable import StorageAlerts
@Test func defaultOffAndDeniedAuthorizationNeverSample() {
    var policy = AlertPolicy()
    let disabled = policy.shouldSample(at: Date(timeIntervalSince1970: 0), authorization: .allowed)
    #expect(!disabled)
    policy.enabled = true
    let denied = policy.shouldSample(at: Date(timeIntervalSince1970: 900), authorization: .denied)
    #expect(!denied)
}
@Test func activationBurstsCoalesceAndPeriodicSamplingResumes() {
    var policy = AlertPolicy(); policy.enabled = true
    let first = policy.shouldSample(at: Date(timeIntervalSince1970: 0), authorization: .allowed)
    let burst = policy.shouldSample(at: Date(timeIntervalSince1970: 2), authorization: .allowed)
    let next = policy.shouldSample(at: Date(timeIntervalSince1970: 900), authorization: .allowed)
    #expect(first && !burst && next)
}
@Test func unavailableSamplesPauseAndLowEpisodeNotifiesOnceUntilRecovery() {
    var policy = AlertPolicy(); policy.enabled = true
    let unavailable = policy.observe(available: nil, total: 512_000_000_000)
    let first = policy.observe(available: 30_000_000_000, total: 512_000_000_000)
    let repeated = policy.observe(available: 20_000_000_000, total: 512_000_000_000)
    let near = policy.observe(available: 42_000_000_000, total: 512_000_000_000)
    let stillSame = policy.observe(available: 30_000_000_000, total: 512_000_000_000)
    let recovered = policy.observe(available: 45_000_000_000, total: 512_000_000_000)
    let next = policy.observe(available: 39_000_000_000, total: 512_000_000_000)
    #expect(!unavailable && first && !repeated && !near && !stillSame && !recovered && next)
}
@Test func invalidThresholdsAndReadingsCannotCreateEpisodes() {
    #expect(!AlertPolicy.validThreshold(999_999_999, total: 512_000_000_000))
    #expect(!AlertPolicy.validThreshold(512_000_000_000, total: 512_000_000_000))
    #expect(!AlertPolicy.validThreshold(40_000_000_000, total: nil))
    #expect(AlertPolicy.validThreshold(1_000_000_000, total: 512_000_000_000))
    var policy = AlertPolicy(); policy.enabled = true
    let invalid = policy.observe(available: -1, total: 512_000_000_000)
    let absent = policy.observe(available: 0, total: nil)
    #expect(!invalid && !absent)
}
@Test func failedNotificationSubmissionCanRetryWithoutDuplicateSuccess() {
    var policy = AlertPolicy(); policy.enabled = true
    let first = policy.observe(available: 1_000_000_000, total: 512_000_000_000)
    policy.submissionFailed()
    let retry = policy.observe(available: 1_000_000_000, total: 512_000_000_000)
    let duplicate = policy.observe(available: 1_000_000_000, total: 512_000_000_000)
    #expect(first && retry && !duplicate)
}
