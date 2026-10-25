import Foundation
import Testing
import ChromeProbe

@Test func unqualifiedVersionCannotAuthorizeChromeCleanup() {
    let report = ChromeProbe.assess(.init(version: "999.0", ownerIdentified: true, profileMappingKnown: true, sharedOwnersKnown: true, browserOrHelperRunning: false, activeWrites: false, reopened: false, deniedAccess: false, symlinkSwap: false))
    #expect(report.supported == false)
    #expect(report.reasons.contains("version-not-qualified"))
}

@Test(arguments: ["owner", "profiles", "shared", "running", "writes", "reopen", "denied", "symlink", "unknown"])
func unsafeOrUnknownEnvironmentReportsGuidance(_ condition: String) {
    var environment = ChromeEnvironment(version: "fixture-only-1", ownerIdentified: true, profileMappingKnown: true, sharedOwnersKnown: true, browserOrHelperRunning: false, activeWrites: false, reopened: false, deniedAccess: false, symlinkSwap: false)
    switch condition {
    case "owner": environment.ownerIdentified = false
    case "profiles": environment.profileMappingKnown = false
    case "shared": environment.sharedOwnersKnown = false
    case "running": environment.browserOrHelperRunning = true
    case "writes": environment.activeWrites = true
    case "reopen": environment.reopened = true
    case "denied": environment.deniedAccess = true
    case "symlink": environment.symlinkSwap = true
    default: environment.browserOrHelperRunning = nil
    }
    #expect(ChromeProbe.assess(environment).reasons.contains("inactivity-or-ownership-unproven"))
}

@Test func disposableCustomProfilesKeepProtectedSentinelsUntouched() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillChromeProbe-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let profiles = ["Custom A", "Nested/Personal"]
    let protected = ["Cookies", "Login Data", "History", "Web Data", "Downloads", "Sessions/Session_1", "Local Storage/site", "IndexedDB/site", "Service Worker/CacheStorage/site"]
    for profile in profiles {
        for file in protected + ["Cache/Cache_Data/asset"] {
            let url = root.appendingPathComponent(profile).appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("sentinel".utf8).write(to: url)
        }
    }
    let report = try ChromeProbe.inspectDisposableFixture(root: root, profilePaths: profiles)
    #expect(report == ["Custom A/Cache/Cache_Data", "Nested/Personal/Cache/Cache_Data"])
    for profile in profiles {
        for file in protected {
            #expect(try Data(contentsOf: root.appendingPathComponent(profile).appendingPathComponent(file)) == Data("sentinel".utf8))
        }
    }
}

@Test func symlinkCacheSwapIsRefused() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillChromeProbe-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Custom/Cache"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Custom/Cache/Cache_Data"), withDestinationURL: root)
    #expect(throws: (any Error).self) { try ChromeProbe.inspectDisposableFixture(root: root, profilePaths: ["Custom"]) }
}
