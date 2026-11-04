import Foundation
import Testing
@testable import CacheDropCore

/// A fixture home with the probed protected folder in the given state. Never the real home.
private func fixtureHome(_ safari: FolderState) throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropFDA-\(UUID())")
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
    // Besides guidance rules (Mail, Messages, Photos, device backups), Safari’s cache and sandboxed apps’ caches need it.
    #expect(fixtureRules.filter { $0.action != .guidance && $0.requiresFullDiskAccess }.map(\.id) == ["safari-cache", "container-caches"])
}

@Test func theExplanationSaysFullDiskAccessIsBroadOptionalAndScansStayReadOnly() {
    // #161: a sheet-sized title and a two-line explanation, as in the prototype.
    #expect(FullDiskAccessGuide.title == "Broader access is optional")
    #expect(FullDiskAccessGuide.summary == "Full Disk Access lets CacheDrop see protected places like Mail and Safari data. macOS grants more than reading; CacheDrop’s scans only read.")
}

@Test func theNoteSaysWhereToTurnFullDiskAccessOn() {
    #expect(FullDiskAccessGuide.howToTurnOn == "Turn on CacheDrop in System Settings › Privacy & Security › Full Disk Access.")
}

@Test func theCoverageTableSaysWhetherProtectedAppDataIsIncluded() {
    #expect(FullDiskAccessGuide.coverage(nil).map(\.title) == ["Scanned now", "Protected app data"])
    #expect(FullDiskAccessGuide.coverage(.granted).map(\.value) == ["Your folders and app caches", "Included"])
    #expect(FullDiskAccessGuide.coverage(.notGranted).map(\.value) == ["Your folders and app caches", "Not included"])
    #expect(FullDiskAccessGuide.coverage(.unknown).map(\.value) == ["Your folders and app caches", "Couldn’t check"])
    #expect(FullDiskAccessGuide.coverage(nil).map(\.value) == ["Your folders and app caches", "Checking…"])
    #expect(FullDiskAccessGuide.coverage(.granted).map(\.included) == [true, true])
    #expect(FullDiskAccessGuide.coverage(.notGranted).map(\.included) == [true, false])
}

@Test func theSettingsLinkOpensTheFullDiskAccessPane() {
    // The Privacy & Security pane keeps the legacy id "com.apple.preference.security" and the "Privacy_AllFiles" anchor on macOS 14 and later.
    #expect(FullDiskAccessGuide.settingsURL.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
}

@Test func eachStatusHasPlainWords() {
    #expect(FullDiskAccessGuide.statusText(.granted) == "Granted")
    #expect(FullDiskAccessGuide.statusText(.notGranted) == "Not granted")
    #expect(FullDiskAccessGuide.statusText(.unknown) == "Couldn’t check")
}

@Test func withoutFullDiskAccessSafarisCacheIsNotAccessibleNeverZeroAndIsNotRead() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropSafariAccess-\(UUID())").resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: home) }
    let cache = home.appendingPathComponent("Library/Caches/com.apple.Safari/WebKit/NetworkCache/Version 17/Records/AB")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 2_048).write(to: cache.appendingPathComponent("0123"))
    let catalog = Catalog(rules: fixtureRules)

    let denied = catalog.discovery(fixture: home, access: .notGranted)
    #expect(denied.notAccessible.map(\.id) == ["safari-cache", "container-caches"])
    // Not offered and not sized, so Overview can't show it as 0: it's listed as not accessible instead.
    #expect(!denied.candidates.contains { $0.ruleID == "safari-cache" })

    let granted = catalog.discovery(fixture: home, access: .granted)
    #expect(granted.notAccessible.isEmpty)
    #expect(granted.candidates.filter { $0.ruleID == "safari-cache" }.map(\.logicalBytes) == [2_048])
}
