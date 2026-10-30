import Foundation
import Testing
import CacheDropCore

private func rule(_ id: String, _ category: CatalogCategory, _ action: CleanupAction) -> CleanupRule {
    CleanupRule(id: id, category: category, title: id, detail: "", consequence: "", regen: .cache, action: action, locations: [id], owner: nil,
                tool: action == .tool ? ToolCommand(executables: ["/usr/bin/true"], arguments: [], timeout: 1) : nil)
}

private func fixture(_ rules: [CleanupRule]) throws -> (URL, Catalog, [Candidate]) {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropPresentation-\(UUID())").resolvingSymlinksInPath()
    for rule in rules {
        let file = home.appendingPathComponent(rule.id + "/entry")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10_000).write(to: file)
    }
    let catalog = Catalog(rules: rules)
    return (home, catalog, catalog.discover(fixture: home, locateTool: { _ in home.appendingPathComponent("tool") }))
}

@Test func reviewGroupsByConsequenceThenCategoryInCatalogOrder() throws {
    let rules = [rule("npm", .developer, .delete), rule("brew", .developer, .tool), rule("installers", .downloads, .trash),
                 rule("chrome", .browser, .delete), rule("yarn", .developer, .delete)]
    let (home, catalog, candidates) = try fixture(rules)
    defer { try? FileManager.default.removeItem(at: home) }
    let groups = ReviewGroup.groups(catalog: catalog, candidates: candidates)
    #expect(groups.map(\.consequence) == [.permanentlyRemoved, .movedToTrash, .commandsRun])
    #expect(ConsequenceGroup.allCases.map(\.title) == ["Delete permanently", "Move to Trash", "Remove local copies", "Run cleanup commands"])
    #expect(ConsequenceGroup(.evict) == .localCopiesRemoved)
    let removed = try #require(groups.first)
    #expect(removed.lines.map(\.category) == [.developer, .browser])
    let developer = try #require(removed.lines.first)
    #expect(developer.rules.map(\.id) == ["npm", "yarn"])
    #expect(developer.candidates.count == 2)
    let commands = try #require(groups.last)
    #expect(commands.lines.map { $0.rules.map(\.id) } == [["brew"]])
}

@Test func reviewGroupsLeaveOutConsequencesNothingChosenHas() throws {
    let rules = [rule("npm", .developer, .delete), rule("installers", .downloads, .trash)]
    let (home, catalog, candidates) = try fixture(rules)
    defer { try? FileManager.default.removeItem(at: home) }
    let groups = ReviewGroup.groups(catalog: catalog, candidates: candidates.filter { $0.ruleID == "installers" })
    #expect(groups.map(\.consequence) == [.movedToTrash])
    #expect(ConsequenceGroup(.guidance) == nil)
}

@Test func resultsListRecordsThatNeedAttentionFirstInRunOrder() throws {
    let rules = [rule("a", .developer, .delete), rule("b", .developer, .delete), rule("c", .developer, .delete), rule("d", .developer, .delete)]
    let (home, _, candidates) = try fixture(rules)
    defer { try? FileManager.default.removeItem(at: home) }
    let batch = UUID()
    var records = candidates.map { CleanupRecord(batchID: batch, approvedAt: Date(), candidate: $0, dryRun: false) }
    try #require(records.count == 4)
    records[0].state = .succeeded; records[1].state = .skipped; records[2].state = .succeeded; records[3].state = .failed
    #expect(records.attentionFirst.map(\.ruleID) == ["b", "d", "a", "c"])
    #expect(records[1].needsAttention && !records[0].needsAttention)
}

@Test func aCleanPreviewNeedsNoAttention() throws {
    let (home, _, candidates) = try fixture([rule("a", .developer, .delete)])
    defer { try? FileManager.default.removeItem(at: home) }
    var record = try #require(candidates.first.map { CleanupRecord(batchID: UUID(), approvedAt: Date(), candidate: $0, dryRun: true) })
    record.state = .skipped; record.message = "Dry run: would delete (10 KB). Checks passed; nothing changed."
    #expect(!record.needsAttention)
    record.message = "Google Chrome is running. Quit it, then scan again."
    #expect(record.needsAttention)
}

@Test func catalogItemsNameICloudDriveByNameAndOtherwiseUseShortLocations() {
    let home = URL(fileURLWithPath: "/Users/someone")
    let short = { PathDisplay.shortLocation(of: home.appendingPathComponent($0), home: home) }
    #expect(short("Downloads/Setup.dmg") == "~/Downloads")
    #expect(short("Library/Caches/Google/Chrome/Default/Cache") == "…/Chrome/Default")
    #expect(short("Library/Mobile Documents/com~apple~CloudDocs/Report.pdf") == "iCloud Drive")
    #expect(short("Library/Mobile Documents/com~apple~CloudDocs/Taxes/Report.pdf") == "iCloud Drive › Taxes")
}
