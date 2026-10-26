import Foundation
import Testing
@testable import StillCore

/// A temp home folder; tests never read or write the real home, Photos, Mail or Messages.
private func guidanceHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillGuidance-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func write(_ bytes: Int, at relative: String, in home: URL) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 3, count: bytes).write(to: file)
}

@Test func aGuidanceCategoryIsSizedButNeverACandidate() throws {
    let home = try guidanceHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(40_960, at: "Pictures/Photos Library.photoslibrary/originals/a.heic", in: home)
    let catalog = Catalog(rules: fixtureRules)

    #expect(catalog.discover(fixture: home).isEmpty)
    let findings = catalog.guidance(fixture: home)
    let photos = try #require(findings.first { $0.ruleID == "photos-library" })
    guard case .estimate(.measured(let bytes)) = photos.size else { Issue.record("Expected a measured size, got \(photos.size)"); return }
    #expect(bytes >= 40_960)
    #expect(catalog.rule("photos-library")?.action == .guidance)
}

private struct NothingRunning: RunningAppChecking {
    func isRunning(_ owner: RuleOwner) -> Bool? { false }
}

@Test func aGuidanceItemThatReachesTheExecutorIsRefusedAndLeftAsIs() async throws {
    let home = try guidanceHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(8192, at: "Library/Developer/Xcode/Archives/2026-10-26/App.xcarchive/Info.plist", in: home)
    let archives = home.appendingPathComponent("Library/Developer/Xcode/Archives")
    let catalog = Catalog(rules: fixtureRules)
    let rule = try #require(catalog.rule("xcode-archives"))
    var info = stat()
    #expect(lstat(archives.path, &info) == 0)
    // Discovery never builds one; this stands in for a bug or a forged plan.
    var candidate = catalog.candidate(rule, archives, info, logical: 8192, allocated: nil, complete: true, lastUsed: nil)
    candidate.scopeRoot = home
    let check = CandidateCheck(catalog: catalog, running: NothingRunning())
    #expect(check.check(candidate) == .guidanceOnly)

    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("journal.sqlite"))
    let executor = CleanupExecutor(journal: journal, check: check, measure: { _ in nil }, trash: TrashNeverUsed())
    let result = await executor.execute(CatalogApproval(candidates: [candidate], previewOnly: false))
    #expect(result.records.map(\.state) == [.skipped])
    #expect(result.records.first?.message == CheckRefusal.guidanceOnly.reason)
    #expect(FileManager.default.fileExists(atPath: archives.appendingPathComponent("2026-10-26/App.xcarchive/Info.plist").path))
}

@Test func anUnreadableGuidanceLocationIsNotAccessibleNeverZero() throws {
    let home = try guidanceHome()
    let attachments = home.appendingPathComponent("Library/Messages/Attachments")
    try write(4096, at: "Library/Messages/Attachments/ab/photo.jpg", in: home)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: attachments.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: attachments.path)
        try? FileManager.default.removeItem(at: home)
    }
    let findings = Catalog(rules: fixtureRules).guidance(fixture: home)
    #expect(findings.first { $0.ruleID == "messages-attachments" }?.size == .notAccessible)
    // Categories with no location on this Mac aren't listed.
    #expect(findings.map(\.ruleID) == ["messages-attachments"])
}

@Test func onePlugInFolderUnreadableMakesTheSizeALowerBound() throws {
    let home = try guidanceHome()
    try write(8192, at: "Library/Audio/Plug-Ins/Components/Synth.component/Contents/a", in: home)
    // The fixture home stands in for the system root, so `/Library/Audio/Plug-Ins` is the same folder here.
    // A second home makes the system one separate and unreadable.
    let root = try guidanceHome()
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Library/Audio/Plug-Ins"), withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: root.appendingPathComponent("Library/Audio/Plug-Ins").path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.appendingPathComponent("Library/Audio/Plug-Ins").path)
        try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: root)
    }
    let finding = try #require(Catalog(rules: fixtureRules).guidance(home: home, systemRoot: root, snapshots: FixtureSnapshots()).first { $0.ruleID == "audio-plug-ins" })
    guard case .estimate(.atLeast(let bytes)) = finding.size else { Issue.record("Expected a lower bound, got \(finding.size)"); return }
    #expect(bytes >= 8192)
    #expect(finding.folder?.path == root.appendingPathComponent("Library/Audio/Plug-Ins").path)
}

@Test func mailCountsOnlyItsAttachmentFolders() throws {
    let home = try guidanceHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(100_000, at: "Library/Mail/V10/acct/INBOX.mbox/uuid/Data/Messages/1.emlx", in: home)
    try write(12_288, at: "Library/Mail/V10/acct/INBOX.mbox/uuid/Data/Attachments/1/2/report.pdf", in: home)
    let finding = try #require(Catalog(rules: fixtureRules).guidance(fixture: home).first { $0.ruleID == "mail-attachments" })
    guard case .estimate(.measured(let bytes)) = finding.size else { Issue.record("Expected a measured size, got \(finding.size)"); return }
    #expect(bytes >= 12_288 && bytes < 100_000)
}

@Test func localSnapshotsShowTheirCountWithSizeUnknown() throws {
    let home = try guidanceHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let catalog = Catalog(rules: fixtureRules)
    #expect(catalog.guidance(fixture: home, snapshots: 3).first { $0.ruleID == "time-machine-snapshots" }?.size == .snapshots(3))
    #expect(catalog.guidance(fixture: home, snapshots: 0).isEmpty)
    // tmutil failing isn't a Full Disk Access refusal: the snapshots are not available, and access wouldn't help.
    #expect(catalog.guidance(fixture: home, snapshots: nil).first?.size == .unavailable)
    let output = "Snapshots for disk /:\ncom.apple.TimeMachine.2026-10-26-101010.local\ncom.apple.TimeMachine.2026-10-26-111010.local\n"
    #expect(TmutilSnapshots.count(in: output) == 2)
    #expect(TmutilSnapshots.count(in: "Snapshots for disk /:\n") == 0)
}

/// Records what would open; nothing actually opens in tests.
private actor RecordingOpener: GuidanceOpening {
    private(set) var targets: [GuidanceTarget] = []
    func open(_ target: GuidanceTarget) async -> Bool { targets.append(target); return true }
}

@Test func openGoesToTheOwningAppSettingsOrFolder() async throws {
    let home = try guidanceHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(4096, at: "Pictures/Photos Library.photoslibrary/database/x", in: home)
    try write(4096, at: "Library/Audio/Plug-Ins/VST3/Synth.vst3/a", in: home)
    try write(4096, at: "Library/Developer/Xcode/Archives/a/b", in: home)
    let catalog = Catalog(rules: fixtureRules)
    let findings = catalog.guidance(fixture: home, snapshots: 1)
    let opener = RecordingOpener()
    for id in ["photos-library", "audio-plug-ins", "xcode-archives", "time-machine-snapshots"] {
        let finding = try #require(findings.first { $0.ruleID == id })
        #expect(await catalog.open(finding, using: opener))
    }
    #expect(await opener.targets == [.app(bundleID: "com.apple.Photos"),
                               .folder(home.appendingPathComponent("Library/Audio/Plug-Ins")),
                               .app(bundleID: "com.apple.dt.Xcode"),
                               .url(URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!)])
    #expect(catalog.rule("photos-library")?.guidance?.openTitle == "Open Photos")
}

@Test func everyGuidanceRuleHasAnExplanationAndAPlaceToManageIt() {
    let rules = fixtureRules.filter { $0.action == .guidance }
    #expect(Set(rules.map(\.id)) == ["device-backups", "mail-attachments", "messages-attachments", "photos-library", "time-machine-snapshots", "xcode-archives", "audio-plug-ins", "rack-extensions"])
    for rule in rules {
        #expect(!rule.detail.isEmpty)
        #expect(rule.guidance?.openTitle.hasPrefix("Open ") == true)
    }
}

@Test func withoutFullDiskAccessProtectedGuidanceIsNotAccessibleWithoutBeingRead() throws {
    let home = try guidanceHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(4096, at: "Library/Mail/V10/acct/Attachments/1/a.pdf", in: home)
    try write(4096, at: "Library/Developer/Xcode/Archives/a/b", in: home)
    let catalog = Catalog(rules: fixtureRules)
    let findings = catalog.guidance(home: home, systemRoot: home, snapshots: FixtureSnapshots(), fullDiskAccess: .notGranted)
    // Protected places aren't touched at all, so no privacy prompt can appear; each is listed as not accessible.
    #expect(Set(findings.filter { $0.size == .notAccessible }.map(\.ruleID)) == ["device-backups", "mail-attachments", "messages-attachments", "photos-library"])
    #expect(findings.first { $0.ruleID == "xcode-archives" }.map { $0.size != .notAccessible } == true)
    #expect(catalog.guidance(home: home, systemRoot: home, snapshots: FixtureSnapshots(), fullDiskAccess: .granted).first { $0.ruleID == "mail-attachments" }?.size != .notAccessible)
}
