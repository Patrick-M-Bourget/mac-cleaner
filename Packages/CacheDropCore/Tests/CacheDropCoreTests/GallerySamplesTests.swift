import Foundation
import Testing
@testable import CacheDropCore

// #794: the Design gallery's made-up review and Trash items. They name paths that don't exist; nothing is read or changed.

private let gone = fixtureNoHome.appendingPathComponent("Gallery")
private let rule = CleanupRule(id: "gallery-cache", category: .developer, title: "Gallery cache", detail: "", consequence: "", regen: .cache,
                               action: .delete, locations: ["Gallery"], owner: nil)

@Test func aGallerySampleCandidateLandsInItsRulesGroupWithItsSizeAndName() {
    let item = Candidate.gallerySample(rule: rule, url: gone.appendingPathComponent("model"), bytes: 2_000, itemName: "llama3:latest")
    #expect(item.ruleID == "gallery-cache" && item.action == .delete && item.estimatedBytes == 2_000 && item.itemName == "llama3:latest")
    #expect(!FileManager.default.fileExists(atPath: item.url.path))
    let groups = ReviewGroup.groups(catalog: Catalog(rules: [rule]), candidates: [item])
    #expect(groups.map(\.consequence) == [.permanentlyRemoved] && groups[0].lines.map(\.category) == [.developer])
}

@Test func gallerySampleCandidatesAtDifferentPathsAreDifferentItems() {
    let first = Candidate.gallerySample(rule: rule, url: gone.appendingPathComponent("a"), bytes: 1)
    let second = Candidate.gallerySample(rule: rule, url: gone.appendingPathComponent("b"), bytes: 1)
    #expect(first.id != second.id)
}

@Test func aGallerySampleTrashItemIsNamedAndSizedAsGiven() {
    let item = TrashItem.gallerySample(url: gone.appendingPathComponent("Old project.zip"), bytes: 3_000)
    #expect(item.name == "Old project.zip" && item.bytes == 3_000)
}
