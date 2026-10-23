import Foundation
import Testing
@testable import SafariProbe
@Test func deniedAccessNeverBecomesAnEmptySupportedCache() {
    let result = SafariCapability.assess(.init(safariVersion: "unknown", osVersion: "unknown", access: .denied, grouping: .unknown, ownerInactive: nil))
    #expect(!result.canMutate)
    #expect(result.reasons.contains("Access unavailable"))
    #expect(result.groupLabel == "Safari cache boundary unknown")
}

@Test func claimedAccessAndGroupingDoNotCertifyTheLayoutOrOwner() {
    let result = SafariCapability.assess(.init(safariVersion: "27.0.1", osVersion: "27.0.1", access: .granted, grouping: .profile, ownerInactive: true))
    #expect(!result.canMutate)
    #expect(result.reasons.contains("No validated Safari asset-only mapping"))
    #expect(result.reasons.contains("Exclusive Safari/helper ownership unproven"))
    #expect(result.groupLabel == "Safari cache boundary unknown")
}

@Test func unsupportedReviewPreservesProtectedDisposableWebsiteData() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("still-safari-fixture-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let sentinels = ["Profile/History.db", "Profile/Cookies.binarycookies", "Profile/WebsiteData/IndexedDB/db", "Profile/WebsiteData/LocalStorage/db", "Profile/WebsiteData/ServiceWorkers/offline", "Profile/LastSession.plist", "Profile/TabGroups.plist", "Shared/Passwords.db", "Shared/AutoFill.db", "Shared/ReadingList/offline", "Downloads/document.pdf", "UnknownCache/object"]
    let marker = Data([0, 83, 65, 70, 69, 255])
    for path in sentinels {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try marker.write(to: url)
    }
    let result = SafariCapability.assess(.init(safariVersion: "future", osVersion: "future", access: .granted, grouping: .shared, ownerInactive: false))
    #expect(!result.canMutate)
    for path in sentinels { #expect(try Data(contentsOf: root.appendingPathComponent(path)) == marker) }
}

@Test func activeAndUnknownOwnersExplainWhyReviewCannotProceed() {
    for inactive in [false, nil] as [Bool?] {
        let result = SafariCapability.assess(.init(safariVersion: "27.0.1", osVersion: "27.0.1", access: .granted, grouping: .unknown, ownerInactive: inactive))
        #expect(result.reasons.contains("Safari or helper may be writing"))
    }
}
