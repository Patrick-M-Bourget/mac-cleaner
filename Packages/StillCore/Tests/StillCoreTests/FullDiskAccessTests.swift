import Foundation
import Testing
@testable import StillCore

/// A fixture home with the probed protected folder in the given state. Never the real home.
private func fixtureHome(_ safari: FolderState) throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillFDA-\(UUID())")
    try FileManager.default.createDirectory(at: home.appendingPathComponent("Library"), withIntermediateDirectories: true)
    let folder = home.appendingPathComponent("Library/Safari")
    switch safari {
    case .missing: break
    case .readable: try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    case .blocked:
        // macOS answers a protected folder with EPERM; a folder with no permissions answers EACCES. Both mean "can't open".
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: folder.path)
    }
    return home
}
private enum FolderState { case missing, readable, blocked }
private func cleanUp(_ home: URL) {
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: home.appendingPathComponent("Library/Safari").path)
    try? FileManager.default.removeItem(at: home)
}

@Test func detectsFullDiskAccessWhenAProtectedFolderOpens() throws {
    let home = try fixtureHome(.readable); defer { cleanUp(home) }
    #expect(FullDiskAccessProbe(home: home).status() == .granted)
}

@Test func detectsNoFullDiskAccessWhenAProtectedFolderRefusesToOpen() throws {
    let home = try fixtureHome(.blocked); defer { cleanUp(home) }
    #expect(FullDiskAccessProbe(home: home).status() == .notGranted)
}

@Test func detectionIsUnknownWhenNoProtectedFolderExists() throws {
    let home = try fixtureHome(.missing); defer { cleanUp(home) }
    #expect(FullDiskAccessProbe(home: home).status() == .unknown)
}

@Test func detectionFallsBackToTheNextProtectedFolderWhenSafariIsMissing() throws {
    let home = try fixtureHome(.missing); defer { cleanUp(home) }
    let tcc = home.appendingPathComponent("Library/Application Support/com.apple.TCC")
    try FileManager.default.createDirectory(at: tcc, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: tcc.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tcc.path) }
    #expect(FullDiskAccessProbe(home: home).status() == .notGranted)
}

/// Stands in for the probe so rule tests never depend on this Mac's grants.
private struct FakeFullDiskAccess: FullDiskAccessDetecting {
    let answer: FullDiskAccessStatus
    func status() -> FullDiskAccessStatus { answer }
}
private func rule(requiringFullDiskAccess: Bool) -> CleanupRule {
    CleanupRule(id: "protected-cache", category: .browser, title: "Protected cache", detail: "", consequence: "", regen: .cache, action: .delete,
                locations: ["Library/Caches/Protected"], owner: nil, requiresFullDiskAccess: requiringFullDiskAccess)
}

@Test func aRuleThatRequiresFullDiskAccessIsNotAccessibleUntilItIsGranted() {
    let protected = rule(requiringFullDiskAccess: true)
    #expect(protected.access(given: FakeFullDiskAccess(answer: .notGranted).status()) == .needsFullDiskAccess)
    #expect(protected.access(given: FakeFullDiskAccess(answer: .granted).status()) == .available)
    // Unknown means no protected folder exists to check; the rule's own sizing then reports what it couldn't read.
    #expect(protected.access(given: FakeFullDiskAccess(answer: .unknown).status()) == .available)
}

@Test func ordinaryRulesNeverWaitForFullDiskAccess() {
    #expect(rule(requiringFullDiskAccess: false).access(given: .notGranted) == .available)
    #expect(fixtureRules.allSatisfy { !$0.requiresFullDiskAccess })
}
