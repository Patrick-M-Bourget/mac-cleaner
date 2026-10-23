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
    let first = policy.observe(available: 1_000_000_000, total: 512_000_000_000, at: Date(timeIntervalSince1970: 0))
    policy.submissionFailed()
    let tooSoon = policy.observe(available: 1_000_000_000, total: 512_000_000_000, at: Date(timeIntervalSince1970: 10))
    let retry = policy.observe(available: 1_000_000_000, total: 512_000_000_000, at: Date(timeIntervalSince1970: 900))
    let duplicate = policy.observe(available: 1_000_000_000, total: 512_000_000_000)
    #expect(first && !tooSoon && retry && !duplicate)
}
@Test func restartAndPreferenceEditsPreserveSuppression() throws {
    var policy = AlertPolicy(); policy.enabled = true
    let first = policy.observe(available: 30_000_000_000, total: 512_000_000_000)
    var restored = try JSONDecoder().decode(AlertPolicy.self, from: JSONEncoder().encode(policy))
    restored.enabled = false; restored.enabled = true; restored.thresholdBytes = 20_000_000_000
    let edited = restored.observe(available: 30_000_000_000, total: 512_000_000_000)
    restored.thresholdBytes = 40_000_000_000
    let duplicate = restored.observe(available: 30_000_000_000, total: 512_000_000_000)
    #expect(first && !edited && !duplicate)
}
@Test func durableSnoozeAllowsExactlyOneReminderAfterValidResumption() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AlertStateStore(url: root.appendingPathComponent("alerts/state.json"))
    var policy = AlertPolicy(); policy.enabled = true
    let first = policy.observe(available: 30_000_000_000, total: 512_000_000_000, at: Date(timeIntervalSince1970: 0))
    policy.submissionAccepted(at: Date(timeIntervalSince1970: 0))
    policy.remindLater(at: Date(timeIntervalSince1970: 10))
    try store.save(policy)
    var restored = try store.load()
    let early = restored.observe(available: 30_000_000_000, total: 512_000_000_000, at: Date(timeIntervalSince1970: 86_409))
    let missing = restored.observe(available: nil, total: 512_000_000_000, at: Date(timeIntervalSince1970: 86_410))
    let reminder = restored.observe(available: 30_000_000_000, total: 512_000_000_000, at: Date(timeIntervalSince1970: 86_410))
    restored.submissionAccepted(at: Date(timeIntervalSince1970: 86_410))
    let duplicate = restored.observe(available: 30_000_000_000, total: 512_000_000_000, at: Date(timeIntervalSince1970: 200_000))
    #expect(first && !early && !missing && reminder && !duplicate)
}
@Test func metricChangesCannotManufactureRecoveryAndNewVolumesRequireBaseline() {
    var policy = AlertPolicy(); policy.enabled = true
    let first = policy.observe(available: 30_000_000_000, total: 512_000_000_000)
    policy.submissionAccepted()
    let changedMetric = policy.observe(available: 100_000_000_000, total: 512_000_000_000, metric: "fallback")
    let sameEpisode = policy.observe(available: 30_000_000_000, total: 512_000_000_000, metric: "fallback")
    let newBaseline = policy.observe(available: 30_000_000_000, total: 512_000_000_000, volumeID: "new", metric: "fallback")
    let newVolume = policy.observe(available: 30_000_000_000, total: 512_000_000_000, volumeID: "new", metric: "fallback")
    #expect(first && !changedMetric && !sameEpisode && !newBaseline && newVolume)
}
@Test func uncertainSubmissionAfterCrashIsSuppressedAndCorruptStateFailsClosed() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AlertStateStore(url: root.appendingPathComponent("state.json"))
    var policy = AlertPolicy(); policy.enabled = true
    _ = policy.observe(available: 0, total: 512_000_000_000)
    try store.save(policy)
    var restored = try store.load()
    let replay = restored.observe(available: 0, total: 512_000_000_000)
    #expect(!replay)
    try Data("broken".utf8).write(to: store.url)
    #expect(throws: (any Error).self) { try store.load() }
}
@Test func disablingCancelsReminderButCannotBypassEpisodeAndRecoveryCapsAtCapacity() {
    var policy = AlertPolicy(); policy.enabled = true; policy.thresholdBytes = 48_000_000_000
    let first = policy.observe(available: 40_000_000_000, total: 50_000_000_000, at: Date(timeIntervalSince1970: 0))
    policy.submissionAccepted(at: Date(timeIntervalSince1970: 0))
    policy.remindLater(at: Date(timeIntervalSince1970: 10))
    policy.enabled = false; policy.enabled = true
    let cancelledReminder = policy.observe(available: 40_000_000_000, total: 50_000_000_000, at: Date(timeIntervalSince1970: 100_000))
    let recovered = policy.observe(available: 50_000_000_000, total: 50_000_000_000, at: Date(timeIntervalSince1970: 100_100))
    let rearmed = policy.observe(available: 40_000_000_000, total: 50_000_000_000, at: Date(timeIntervalSince1970: 101_000))
    #expect(first && !cancelledReminder && !recovered && rearmed)
    #expect(policy.snoozedUntil == nil)
}
