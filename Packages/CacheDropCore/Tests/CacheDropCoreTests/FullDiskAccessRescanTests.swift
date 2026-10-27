import Testing
@testable import CacheDropCore

/// A probe that answers whatever the test sets, so no folder is opened.
private final class FakeProbe: FullDiskAccessDetecting, @unchecked Sendable {
    var answer: FullDiskAccessStatus
    init(_ answer: FullDiskAccessStatus) { self.answer = answer }
    func status() -> FullDiskAccessStatus { answer }
}

@Test func rescansOnceWhenFullDiskAccessIsGrantedWhileAway() {
    var rescan = FullDiskAccessRescan()
    rescan.scanned(.notGranted)
    let probe = FakeProbe(.granted)
    let first = rescan.activated(probing: probe), second = rescan.activated(probing: probe)
    #expect(first)
    #expect(!second, "One rescan per change")
}

@Test(arguments: [
    (FullDiskAccessStatus?.some(.notGranted), FullDiskAccessStatus.notGranted),
    (.some(.granted), .granted),
    (.some(.granted), .notGranted),
    (.some(.unknown), .granted),
    (nil, .granted), // No scan yet: the launch scan probes for itself.
])
func noRescanWhenFullDiskAccessDidNotBecomeGranted(scanned: FullDiskAccessStatus?, now: FullDiskAccessStatus) {
    var rescan = FullDiskAccessRescan()
    if let scanned { rescan.scanned(scanned) }
    let decision = rescan.activated(probing: FakeProbe(now))
    #expect(!decision)
}

@Test func aRescanThatStillSeesNoAccessKeepsWatchingForTheGrant() {
    var rescan = FullDiskAccessRescan()
    rescan.scanned(.granted)
    let revoked = rescan.activated(probing: FakeProbe(.notGranted))
    rescan.scanned(.notGranted)
    let granted = rescan.activated(probing: FakeProbe(.granted))
    #expect(!revoked)
    #expect(granted)
}
