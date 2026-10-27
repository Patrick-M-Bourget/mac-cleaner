import Foundation
import Testing
import CacheDropCore

private func records(_ actions: [CleanupAction], previewOnly: Bool = false) throws -> (URL, [CleanupRecord]) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("StillWording-\(UUID())").resolvingSymlinksInPath()
    var rules: [CleanupRule] = []
    for (index, action) in actions.enumerated() {
        try FileManager.default.createDirectory(at: home.appendingPathComponent("item\(index)"), withIntermediateDirectories: true)
        rules.append(CleanupRule(id: "r\(index)", category: .developer, title: "R", detail: "", consequence: "", regen: .cache, action: action, locations: ["item\(index)"], owner: nil,
                                 tool: action == .tool ? ToolCommand(executables: ["/usr/bin/true"], arguments: [], timeout: 1) : nil))
    }
    let batch = UUID()
    let made = Catalog(rules: rules).discover(fixture: home, locateTool: { _ in home.appendingPathComponent("tool") }).map { CleanupRecord(batchID: batch, approvedAt: Date(), candidate: $0, previewOnly: previewOnly) }
    // One record per action, so tests can index them without crashing.
    try #require(made.count == actions.count)
    return (home, made)
}

@Test func eachRecordNamesWhatHappenedForItsOwnAction() throws {
    let (home, made) = try records([.delete, .trash])
    defer { try? FileManager.default.removeItem(at: home) }
    var delete = made[0], trash = made[1]
    #expect(delete.actionTitle == "Delete permanently")
    #expect(trash.actionTitle == "Move to Trash")
    delete.state = .succeeded; trash.state = .succeeded
    #expect(delete.outcomeTitle == "Deleted")
    #expect(trash.outcomeTitle == "Moved to Trash")
    delete.state = .unknown; trash.state = .intent
    #expect(delete.outcomeTitle == "Unresolved")
    #expect(delete.recoveryStateText == "Unresolved · It may be partly deleted")
    #expect(trash.recoveryStateText == "Unresolved · It may or may not be in the Trash")
    delete.state = .skipped
    #expect(delete.outcomeTitle == "Skipped")
    let (toolHome, toolRecords) = try records([.tool])
    defer { try? FileManager.default.removeItem(at: toolHome) }
    var tool = try #require(toolRecords.first)
    #expect(tool.actionTitle == "Run its cleanup command")
    tool.state = .succeeded
    #expect(tool.outcomeTitle == "Cleaned")
    tool.state = .unknown
    #expect(tool.recoveryStateText == "Unresolved · It may be partly deleted")
    #expect(delete.recoveryStateText == "Recorded skip · Not changed")
}

@Test func downloadsEraRecordsReadAsTrashMoves() throws {
    let legacy = #"{"action":"moveToTrash","approvedAt":0,"batchID":"FD8FB579-0EB5-4CC1-925B-F038F4B44EEB","id":"x","logicalBytes":3,"message":"Moved to Trash","modifiedNanoseconds":0,"modifiedSeconds":0,"observedAt":0,"originalURL":"file:\/\/\/x\/Setup.dmg","policyVersion":1,"resourceID":"1:2","scopeResourceID":"1:1","scopeURL":"file:\/\/\/x\/","state":"succeeded"}"#
    let record = try JSONDecoder().decode(CleanupRecord.self, from: Data(legacy.utf8))
    #expect(record.outcomeTitle == "Moved to Trash")
    #expect(record.recoveryStateText == "Recorded success · Moved to Trash")
}

@Test func aDryRunReadsAsADryRunNotAsSkippedOrFailed() async throws {
    let (home, made) = try records([.delete, .trash], previewOnly: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("j.sqlite"))
    struct Closed: RunningAppChecking { func isRunning(_ owner: RuleOwner) -> Bool? { false } }
    let catalog = Catalog(rules: [
        CleanupRule(id: "r0", category: .developer, title: "R", detail: "", consequence: "", regen: .cache, action: .delete, locations: ["item0"], owner: nil),
        CleanupRule(id: "r1", category: .developer, title: "R", detail: "", consequence: "", regen: .cache, action: .trash, locations: ["item1"], owner: nil),
    ])
    let candidates = catalog.discover(fixture: home)
    #expect(candidates.count == made.count)
    let result = await CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: Closed()), measure: { _ in nil }, trash: TrashNeverUsed())
        .execute(CatalogApproval(candidates: candidates, previewOnly: true))
    #expect(result.records.map(\.outcomeTitle) == ["Would delete", "Would move to Trash"])
    #expect(result.records.allSatisfy { $0.message.hasPrefix("Dry run: would ") })
    #expect(result.records.first?.recoveryStateText == "Dry run · Would delete")
    let run = try #require(try journal.completedHistory().completedRuns.first)
    #expect(run.isPreview)
    #expect(run.title == "Dry run · Nothing changed")
    #expect(run.trashHeldAllocatedBytes == 0)
}

/// Records journaled while the switch was called "Preview only" still read as a dry run.
@Test func previewOnlyEraRecordsStillReadAsADryRun() throws {
    let (home, made) = try records([.delete], previewOnly: true)
    defer { try? FileManager.default.removeItem(at: home) }
    var record = try #require(made.first)
    record.state = .skipped; record.message = "Dry run: would delete (10 KB). Checks passed; nothing changed."
    #expect(record.wasPreviewed)
    #expect(record.outcomeTitle == "Would delete")
    #expect(CleanupHistorySnapshot(records: [record]).completedRuns.first?.title == "Dry run · Nothing changed")
}

@Test func aRealRunIsTitledByTheActionsItTook() throws {
    let (home, made) = try records([.delete, .trash])
    defer { try? FileManager.default.removeItem(at: home) }
    var snapshot = CleanupHistorySnapshot(records: made.map { var r = $0; r.state = .succeeded; return r })
    #expect(snapshot.completedRuns.first?.isPreview == false)
    #expect(snapshot.completedRuns.first?.title == "Cleanup · Deleted and moved to Trash")
    snapshot = CleanupHistorySnapshot(records: [made[1]].map { var r = $0; r.state = .succeeded; return r })
    #expect(snapshot.completedRuns.first?.title == "Cleanup · Moved to Trash")
    snapshot = CleanupHistorySnapshot(records: [made[0]].map { var r = $0; r.state = .succeeded; return r })
    #expect(snapshot.completedRuns.first?.title == "Cleanup · Deleted")
}

private struct ArrayJournal: CleanupJournaling {
    let stored: [CleanupRecord]
    func claim(batchID: UUID, records: [CleanupRecord]) throws -> Bool { false }
    func intent(_ record: CleanupRecord) throws {}
    func outcome(_ record: CleanupRecord) throws {}
    func records() throws -> [CleanupRecord] { stored }
}

@Test func recoveryExplainsAnUnresolvedDeleteDifferentlyFromAnUnresolvedTrashMove() throws {
    let (home, made) = try records([.delete, .trash])
    defer { try? FileManager.default.removeItem(at: home) }
    func notice(_ records: [CleanupRecord]) throws -> String { try CleanupRecoverySnapshot(journal: ArrayJournal(stored: records)).unresolvedNotice }
    var delete = made[0], trash = made[1]
    delete.state = .intent; trash.state = .unknown
    #expect(try notice([delete]) == "A missing original may have been permanently deleted, possibly only in part. Deleted items can’t be restored from the Trash. Current file locations have not been inspected.")
    #expect(try notice([trash]) == "A missing original does not prove it reached the Trash. Current file locations have not been inspected.")
    #expect(try notice([delete, trash]).hasPrefix("A missing original may have reached the Trash or been permanently deleted"))
}

@Test func aPartlyRemovedRecordNeverReadsAsNotChanged() throws {
    let (home, made) = try records([.delete, .tool])
    defer { try? FileManager.default.removeItem(at: home) }
    var delete = made[0], tool = made[1]
    delete.state = .failed; delete.partlyRemoved = true
    tool.state = .failed; tool.partlyRemoved = true
    #expect(delete.outcomeTitle == "Partly removed")
    #expect(delete.recoveryStateText == "Recorded failure · It may be partly deleted")
    #expect(tool.outcomeTitle == "Partly removed")
    #expect(tool.recoveryStateText == "Recorded failure · It may be partly deleted")
    #expect(CleanupHistorySnapshot(records: [delete, tool]).completedRuns.first?.title == "Cleanup · Partly deleted")
    delete.partlyRemoved = nil
    #expect(delete.recoveryStateText == "Recorded failure · Not changed")
}
