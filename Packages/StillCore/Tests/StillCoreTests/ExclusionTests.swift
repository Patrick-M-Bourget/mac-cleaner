import Foundation
import Testing
import StillCore

@Test func explicitPathRulesPersistAndDistinguishRenameReplacementVolumeAndOverlaps() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("StillExclusions-" + UUID().uuidString).resolvingSymlinksInPath()
    let folder = base.appendingPathComponent("Chosen"), file = folder.appendingPathComponent("one.txt")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    try Data([1]).write(to: file)
    let rule = try ExclusionRule.capture(file)
    let parent = try ExclusionRule.capture(folder)
    let store = ExclusionStore(directory: base.appendingPathComponent("State"))
    try await store.add(rule); try await store.add(parent)
    let saved = try await ExclusionStore(directory: base.appendingPathComponent("State")).policy()
    #expect(saved.rules.count == 2)
    #expect(saved.matches(file, volumeID: rule.volumeID))
    #expect(!saved.matches(file, volumeID: "another-volume"))
    let renamed = folder.appendingPathComponent("renamed.txt")
    try FileManager.default.moveItem(at: file, to: renamed)
    #expect(!ExclusionPolicy(rules: [rule]).matches(renamed, volumeID: rule.volumeID))
    try Data([9]).write(to: file)
    #expect(saved.matches(file, volumeID: rule.volumeID))
    try await store.remove(parent.id)
    #expect(try await store.policy().matches(file, volumeID: rule.volumeID))
    #expect(try await store.policy().matches(renamed, volumeID: rule.volumeID) == false)
    try await store.reset()
    #expect(try await store.policy().rules.isEmpty)
}

private struct ExclusionMetadata: MetadataSupplementReading {
    func read(_ url: URL) throws -> MetadataSupplement {
        if url.lastPathComponent == "do-not-read.txt" { throw CocoaError(.fileReadNoPermission) }
        return .init(allocatedBytes: 3, locality: .local, cloud: .init(membership: false))
    }
}
@Test func excludedBoundariesAreNotEnumeratedAndHardlinkAliasesRemainIndependent() async throws {
    let scope = FileManager.default.temporaryDirectory.appendingPathComponent("StillExclusions-" + UUID().uuidString).resolvingSymlinksInPath()
    let hidden = scope.appendingPathComponent("Excluded")
    try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scope) }
    try Data([9, 9, 9, 9, 9]).write(to: hidden.appendingPathComponent("do-not-read.txt"))
    try Data([1, 2, 3]).write(to: scope.appendingPathComponent("keep.txt"))
    let original = scope.appendingPathComponent("one.txt"), alias = scope.appendingPathComponent("alias.txt")
    try Data([1, 2, 3, 4]).write(to: original); try FileManager.default.linkItem(at: original, to: alias)
    let policy = ExclusionPolicy(rules: [try .capture(hidden), try .capture(original)])
    let result = try await FolderScanner(supplement: ExclusionMetadata()).scan(scope, exclusions: policy)
    #expect(result.isComplete && result.logicalBytes == 7)
    #expect(result.totalLogicalBytes == nil)
    #expect(result.excludedEntryCount == 2)
    #expect(result.exclusionFingerprint == policy.fingerprint)
    #expect(!result.observations.contains { $0.url.lastPathComponent == "Excluded" || $0.url.lastPathComponent == "one.txt" || $0.url.lastPathComponent == "do-not-read.txt" })
    #expect(result.observations.contains { $0.url.lastPathComponent == "alias.txt" })
    let excludedRoot = try await FolderScanner().scan(hidden, exclusions: policy)
    #expect(!excludedRoot.isComplete && excludedRoot.totalLogicalBytes == nil)
}

@Test func changedExclusionCoverageRequiresANewCompatibleGrowthBaseline() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("StillExclusions-" + UUID().uuidString)
    let scope = base.appendingPathComponent("Scope")
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    try Data([1, 2, 3]).write(to: scope.appendingPathComponent("keep.txt"))
    let hidden = scope.appendingPathComponent("hidden.txt")
    try Data([1, 2, 3, 4]).write(to: hidden)
    let store = GrowthHistoryStore(directory: base.appendingPathComponent("Growth"))
    let recorder = GrowthScanRecorder(store: store)
    let first = try await recorder.begin(scope: scope)
    let full = try await FolderScanner(supplement: ExclusionMetadata()).scan(scope)
    #expect(try await recorder.complete(full, token: first).state == .firstBaseline)
    let policy = ExclusionPolicy(rules: [try .capture(hidden)])
    let token = try await recorder.begin(scope: scope, exclusionFingerprint: policy.fingerprint)
    let included = try await FolderScanner(supplement: ExclusionMetadata()).scan(scope, exclusions: policy)
    #expect(included.includedLogicalBytes == 3 && included.totalLogicalBytes == nil)
    #expect(try await recorder.complete(included, token: token).state == .coverageChanged)
    let second = try await recorder.begin(scope: scope, exclusionFingerprint: policy.fingerprint)
    let repeated = try await FolderScanner(supplement: ExclusionMetadata()).scan(scope, exclusions: policy)
    #expect(try await recorder.complete(repeated, token: second).state == .compared)
    let wrong = try await recorder.begin(scope: scope)
    #expect(try await recorder.complete(repeated, token: wrong).state == .unknown)
}

@Test func savingRulesRequiresRefreshAndRemovalNeverSelectsNewlyVisibleFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillExclusions-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("chosen.txt")
    try Data([1]).write(to: file)
    let scanner = FolderScanner(supplement: ExclusionMetadata())
    let initial = try await scanner.scan(root)
    var draft = PlanDraft(), refresh = RefreshChoices()
    try draft.select(try #require(initial.observations.first), in: initial, downloadsRoot: root)
    refresh.invalidateCoverage(draft: &draft)
    #expect(draft.selectedCount == 1 && !refresh.canReview(draft))
    let policy = ExclusionPolicy(rules: [try .capture(file)])
    let request = refresh.begin(scope: root, draft: &draft)
    let excluded = try await scanner.scan(root, exclusions: policy)
    refresh.finish(await RefreshValidator().validate(request, against: excluded), draft: &draft)
    #expect(draft.selectedCount == 0 && refresh.notices.count == 1)
    #expect(refresh.notices.first?.message == "File is outside the latest included findings. Its previous selection was cleared.")
    let restored = refresh.begin(scope: root, draft: &draft)
    refresh.finish(await RefreshValidator().validate(restored, against: try await scanner.scan(root)), draft: &draft)
    #expect(draft.selectedCount == 0)
}

@Test func changingCoverageRejectsOldInflightGrowthWithoutClearingHistory() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("StillExclusions-" + UUID().uuidString)
    let scope = base.appendingPathComponent("Scope")
    try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    try Data([1]).write(to: scope.appendingPathComponent("one.txt"))
    let store = GrowthHistoryStore(directory: base.appendingPathComponent("Growth")), scanner = FolderScanner(supplement: ExclusionMetadata())
    let recorder = GrowthScanRecorder(store: store)
    let initial = try await recorder.begin(scope: scope)
    _ = try await recorder.complete(scanner.scan(scope), token: initial)
    let stale = try await recorder.begin(scope: scope)
    let observation = try await scanner.scan(scope)
    try await store.invalidateCoverage()
    #expect(try await recorder.complete(observation, token: stale).state == .unknown)
    #expect(try await store.snapshots().count == 1)
}

@Test func corruptExclusionSettingsNeverBecomeAnEmptyPolicy() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("StillExclusions-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let store = ExclusionStore(directory: base)
    try Data("invalid-settings".utf8).write(to: base.appendingPathComponent("rules-v1.json"))
    await #expect(throws: (any Error).self) { try await store.policy() }
    // An explicitly authorized reset recovers only this store; unrelated authority survives.
    let other = base.appendingPathComponent("unrelated-journal")
    try Data([7]).write(to: other)
    try await store.reset()
    #expect(try await store.policy().rules.isEmpty)
    #expect(try Data(contentsOf: other) == Data([7]))
}
