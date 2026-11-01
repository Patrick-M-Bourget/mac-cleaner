import Foundation
import Testing
import CacheDropCore

private func records(_ actions: [CleanupAction], dryRun: Bool = false) throws -> (URL, [CleanupRecord]) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropWording-\(UUID())").resolvingSymlinksInPath()
    var rules: [CleanupRule] = []
    for (index, action) in actions.enumerated() {
        try FileManager.default.createDirectory(at: home.appendingPathComponent("item\(index)"), withIntermediateDirectories: true)
        rules.append(CleanupRule(id: "r\(index)", category: .developer, title: "R", detail: "", consequence: "", regen: .cache, action: action, locations: ["item\(index)"], owner: nil,
                                 tool: action == .tool ? ToolCommand(executables: ["/usr/bin/true"], arguments: [], timeout: 1) : nil))
    }
    let batch = UUID()
    let made = Catalog(rules: rules).discover(fixture: home, locateTool: { _ in home.appendingPathComponent("tool") }).map { CleanupRecord(batchID: batch, approvedAt: Date(), candidate: $0, dryRun: dryRun) }
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
    #expect(delete.recoveryStateText == "Unfinished · It may be partly deleted")
    #expect(trash.recoveryStateText == "Unfinished · It may or may not be in the Trash")
    delete.state = .skipped
    #expect(delete.outcomeTitle == "Skipped")
    let (toolHome, toolRecords) = try records([.tool])
    defer { try? FileManager.default.removeItem(at: toolHome) }
    var tool = try #require(toolRecords.first)
    #expect(tool.actionTitle == "Run its cleanup command")
    tool.state = .succeeded
    // #312: one verb for the same kind of result; a cleanup command's removal is permanent too.
    #expect(tool.outcomeTitle == "Deleted")
    tool.state = .unknown
    #expect(tool.recoveryStateText == "Unfinished · It may be partly deleted")
    #expect(delete.recoveryStateText == "Skipped · Not changed")
}

@Test func downloadsEraRecordsReadAsTrashMoves() throws {
    let legacy = #"{"action":"moveToTrash","approvedAt":0,"batchID":"FD8FB579-0EB5-4CC1-925B-F038F4B44EEB","id":"x","logicalBytes":3,"message":"Moved to Trash","modifiedNanoseconds":0,"modifiedSeconds":0,"observedAt":0,"originalURL":"file:\/\/\/x\/Setup.dmg","policyVersion":1,"resourceID":"1:2","scopeResourceID":"1:1","scopeURL":"file:\/\/\/x\/","state":"succeeded"}"#
    let record = try JSONDecoder().decode(CleanupRecord.self, from: Data(legacy.utf8))
    #expect(record.outcomeTitle == "Moved to Trash")
    #expect(record.recoveryStateText == "Finished · Moved to Trash")
}

@Test func aDryRunReadsAsADryRunNotAsSkippedOrFailed() async throws {
    let (home, made) = try records([.delete, .trash], dryRun: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let journal = try SQLiteCleanupJournal(url: home.appendingPathComponent("j.sqlite"))
    let catalog = Catalog(rules: [
        CleanupRule(id: "r0", category: .developer, title: "R", detail: "", consequence: "", regen: .cache, action: .delete, locations: ["item0"], owner: nil),
        CleanupRule(id: "r1", category: .developer, title: "R", detail: "", consequence: "", regen: .cache, action: .trash, locations: ["item1"], owner: nil),
    ])
    let candidates = catalog.discover(fixture: home)
    #expect(candidates.count == made.count)
    let result = await CleanupExecutor(journal: journal, check: CandidateCheck(catalog: catalog, running: FixtureNothingRunning()), measure: { _ in nil }, trash: TrashNeverUsed())
        .execute(CatalogApproval(candidates: candidates, dryRun: true))
    #expect(result.records.map(\.outcomeTitle) == ["Would delete", "Would move to Trash"])
    #expect(result.records.allSatisfy { $0.message.hasPrefix("Dry run: would ") })
    #expect(result.records.first?.recoveryStateText == "Dry run · Would delete")
    #expect(Set(result.cleanedCandidateIDs) == Set(candidates.map(\.id)), "What a dry run would clean leaves the selection as a real run's does (#349)")
    let run = try #require(try journal.completedHistory().completedRuns.first)
    #expect(run.isPreview)
    #expect(run.title == "Dry run · Nothing changed")
    #expect(run.trashHeldAllocatedBytes == 0)
}

/// Records journaled while the switch was called "Preview only" still read as a dry run.
@Test func dryRunEraRecordsStillReadAsADryRun() throws {
    let (home, made) = try records([.delete], dryRun: true)
    defer { try? FileManager.default.removeItem(at: home) }
    var record = try #require(made.first)
    record.state = .skipped; record.message = "Dry run: would delete (10 KB). Checks passed; nothing changed."
    #expect(record.wasDryRun)
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

@Test func aPartlyRemovedRecordNeverReadsAsNotChanged() throws {
    let (home, made) = try records([.delete, .tool])
    defer { try? FileManager.default.removeItem(at: home) }
    var delete = made[0], tool = made[1]
    delete.state = .failed; delete.partlyRemoved = true
    tool.state = .failed; tool.partlyRemoved = true
    #expect(delete.outcomeTitle == "Partly deleted")
    #expect(delete.recoveryStateText == "Failed · It may be partly deleted")
    #expect(tool.outcomeTitle == "Partly deleted")
    #expect(tool.recoveryStateText == "Failed · It may be partly deleted")
    #expect(CleanupHistorySnapshot(records: [delete, tool]).completedRuns.first?.title == "Cleanup · Partly deleted")
    delete.partlyRemoved = nil
    #expect(delete.recoveryStateText == "Failed · Not changed")
}

/// #312: History shows a record's message only when it adds to its outcome ("Moved to Trash · Moved to Trash" read twice).
@Test func historyShowsAMessageOnlyWhenItAddsToTheOutcome() throws {
    let (home, made) = try records([.trash, .delete, .tool])
    defer { try? FileManager.default.removeItem(at: home) }
    var trash = made[0], delete = made[1], tool = made[2]
    trash.state = .succeeded; trash.message = "Moved to Trash"
    delete.state = .succeeded; delete.message = "Permanently removed"
    tool.state = .succeeded; tool.message = "Ran brew"
    #expect(trash.outcomeLine == "Moved to Trash")
    #expect(delete.outcomeLine == "Deleted")
    #expect(tool.outcomeLine == "Deleted · Ran brew")
    delete.state = .failed; delete.message = "Couldn’t remove it (Permission denied). Left unchanged."
    #expect(delete.outcomeLine == "Failed · Couldn’t remove it (Permission denied). Left unchanged.")
}
