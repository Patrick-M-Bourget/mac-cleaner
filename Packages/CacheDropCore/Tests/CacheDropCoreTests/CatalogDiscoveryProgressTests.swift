import Foundation
import Testing
@testable import CacheDropCore

/// A temp home folder; tests never read or write the real home.
private func progressHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropProgress-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home.resolvingSymlinksInPath()
}
private func write(_ bytes: Int, at relative: String, in home: URL) throws {
    let file = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: file)
}
private func rule(_ id: String, title: String, locations: [String]? = nil, base: LocationBase = .home, action: CleanupAction = .delete) -> CleanupRule {
    CleanupRule(id: id, category: .developer, title: title, detail: "", consequence: "", regen: .cache, action: action, locations: locations ?? [id], owner: nil, base: base)
}
private func discovery(_ catalog: Catalog, home: URL, steps: inout [CatalogDiscoveryProgress]) -> CatalogDiscovery {
    var recorded: [CatalogDiscoveryProgress] = []
    let result = catalog.discovery(home: home, inUse: FixtureNothingInUse(), locateTool: { _ in nil }, systemRoot: home, cloud: FakeCloud(), access: .granted,
                                   progress: { recorded.append($0) })
    steps = recorded
    return result
}

@Test func discoveryReportsEachLocationAsItIsCheckedThenWhatItFoundInCatalogOrder() throws {
    let home = try progressHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(4096, at: "a/f", in: home)
    try write(8192, at: "c/f", in: home)
    // Guidance is sized elsewhere and a user-folder rule has no base here: neither is checked, so neither counts.
    let catalog = Catalog(rules: [rule("a", title: "Alpha"), rule("guide", title: "Guide", action: .guidance), rule("b", title: "Beta"),
                                  rule("temp", title: "Temp", base: .userFolder), rule("c", title: "Gamma")])
    var steps: [CatalogDiscoveryProgress] = []
    let result = discovery(catalog, home: home, steps: &steps)

    #expect(steps.map(\.summary) == ["checking a Alpha 1/3", "finished a 1/3 found 1", "checking b Beta 2/3", "finished b 2/3 found 0",
                                     "checking c Gamma 3/3", "finished c 3/3 found 1"])
    // What the steps found, in order, is exactly what discovery returns.
    let found = steps.flatMap { step -> [Candidate] in if case .finished(_, _, _, let found) = step { found } else { [] } }
    #expect(found.map(\.url) == result.candidates.map(\.url))
    #expect(result.candidates.map(\.url.lastPathComponent) == ["a", "c"])
}

@Test func spaceAnEarlierLocationClaimedIsReportedOnceUnderIt() throws {
    let home = try progressHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(4096, at: "shared/f", in: home)
    let catalog = Catalog(rules: [rule("first", title: "First", locations: ["shared"]), rule("second", title: "Second", locations: ["shared"])])
    var steps: [CatalogDiscoveryProgress] = []
    let result = discovery(catalog, home: home, steps: &steps)

    #expect(steps.map(\.summary) == ["checking first First 1/2", "finished first 1/2 found 1", "checking second Second 2/2", "finished second 2/2 found 0"])
    #expect(result.candidates.map(\.ruleID) == ["first"])
}

private extension CatalogDiscoveryProgress {
    var summary: String {
        switch self {
        case .checking(let id, let title, let number, let total): "checking \(id) \(title) \(number)/\(total)"
        case .finished(let id, let number, let total, let found): "finished \(id) \(number)/\(total) found \(found.count)"
        }
    }
}

@Test func stoppedCatalogDiscoveryDoesNotBeginAnotherLocationOrRecordItAsEmpty() throws {
    let home = try progressHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try write(4096, at: "a/f", in: home)
    try write(8192, at: "b/f", in: home)
    let catalog = Catalog(rules: [rule("a", title: "Alpha"), rule("b", title: "Beta")])
    let cancellation = ScanCancellation()
    var steps: [CatalogDiscoveryProgress] = []
    let discovery = catalog.discovery(home: home, inUse: FixtureNothingInUse(), locateTool: { _ in nil }, systemRoot: home, cloud: FakeCloud(), access: .granted,
                                      cancellation: cancellation) { step in
        steps.append(step)
        if case .finished = step { cancellation.cancel() }
    }
    #expect(discovery.scannedRuleIDs == ["a"])
    #expect(discovery.candidates.map(\.ruleID) == ["a"])
    #expect(steps.map(\.summary) == ["checking a Alpha 1/2", "finished a 1/2 found 1"])
    #expect(StorageTrendsCatalog.groups(discovery, catalog: catalog, fullDiskAccess: .granted).map(\.ruleID) == ["a"])
}
