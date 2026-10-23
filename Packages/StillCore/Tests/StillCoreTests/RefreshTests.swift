import Foundation
import Testing
import StillCore

private struct RefreshLocalMetadata: MetadataSupplementReading {
    func read(_ url: URL) throws -> MetadataSupplement {
        MetadataSupplement(allocatedBytes: 3, locality: .local, cloud: CloudMetadata(membership: false))
    }
}
@Test func unchangedRefreshPreservesExactChoicesAndLeavesNewFindingsUnchecked() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRefresh-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1, 2, 3]).write(to: root.appendingPathComponent("chosen.pdf"))
    let scanner = FolderScanner(supplement: RefreshLocalMetadata())
    let initial = try await scanner.scan(root)
    var draft = PlanDraft()
    try draft.select(try #require(initial.observations.first), in: initial, downloadsRoot: root)
    let original = try #require(draft.selected.first)
    var refresh = RefreshChoices()
    let request = refresh.begin(scope: root, draft: &draft)
    #expect(refresh.requiresRefresh(original.id))
    #expect(draft.selected.first?.observedAt == original.observedAt)
    try Data([4]).write(to: root.appendingPathComponent("new.pdf"))
    let scan = try await scanner.scan(root)
    let outcome = await RefreshValidator().validate(request, against: scan)
    refresh.finish(outcome, draft: &draft)
    #expect(!refresh.requiresRefresh(original.id))
    #expect(draft.selected.map(\.id) == [original.id])
    #expect(draft.selected.first?.observedAt == scan.observedAt)
}
@Test func completeRefreshExplainsChangedAndRemovedChoicesWithoutSelectingReplacements() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRefresh-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let changed = root.appendingPathComponent("changed.pdf"), removed = root.appendingPathComponent("removed.pdf")
    try Data([1, 2, 3]).write(to: changed); try Data([1]).write(to: removed)
    let scanner = FolderScanner(supplement: RefreshLocalMetadata())
    let initial = try await scanner.scan(root)
    var draft = PlanDraft()
    for item in initial.observations { try draft.select(item, in: initial, downloadsRoot: root) }
    var refresh = RefreshChoices()
    let request = refresh.begin(scope: root, draft: &draft)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1234)], ofItemAtPath: changed.path)
    try FileManager.default.removeItem(at: removed)
    let fresh = try await scanner.scan(root)
    refresh.finish(await RefreshValidator().validate(request, against: fresh), draft: &draft)
    #expect(draft.selectedCount == 0)
    #expect(refresh.notices.first { $0.target.url.lastPathComponent == "changed.pdf" }?.message == "File changed or is no longer eligible. Review it again before selecting it.")
    #expect(refresh.notices.first { $0.target.url.lastPathComponent == "removed.pdf" }?.message == "File was removed or replaced. Its previous selection was cleared.")
}
@Test func cancelledAndIncompleteRefreshKeepChoicesVisibleUntilACompleteRecheck() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRefresh-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: root.appendingPathComponent("chosen.pdf"))
    let scanner = FolderScanner(supplement: RefreshLocalMetadata())
    let scan = try await scanner.scan(root)
    var draft = PlanDraft()
    try draft.select(try #require(scan.observations.first), in: scan, downloadsRoot: root)
    let id = try #require(draft.selected.first?.id)
    var refresh = RefreshChoices()
    let cancelled = refresh.begin(scope: root, draft: &draft)
    #expect(refresh.status(id) == .refreshing)
    let stale = await RefreshValidator().validate(cancelled, against: try await scanner.scan(root))
    refresh.cancel(cancelled)
    refresh.finish(stale, draft: &draft)
    #expect(refresh.status(id) == .required)
    #expect(!refresh.canReview(draft) && draft.selectedCount == 1)
    try Data([2]).write(to: root.appendingPathComponent("another.pdf"))
    let incomplete = refresh.begin(scope: root, draft: &draft)
    let limited = try await FolderScanner(supplement: RefreshLocalMetadata(), maximumEntries: 0).scan(root)
    refresh.finish(await RefreshValidator().validate(incomplete, against: limited), draft: &draft)
    #expect(refresh.status(id) == .required)
    #expect(draft.selected.first?.observedAt == scan.observedAt)
    let successful = refresh.begin(scope: root, draft: &draft)
    refresh.finish(await RefreshValidator().validate(successful, against: try await scanner.scan(root)), draft: &draft)
    #expect(refresh.status(id) == .ready && refresh.canReview(draft))
}
@Test func cachedObservationCannotMakePendingChoicesReady() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRefresh-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: root.appendingPathComponent("chosen.pdf"))
    let cached = try await FolderScanner(supplement: RefreshLocalMetadata()).scan(root)
    var draft = PlanDraft()
    try draft.select(try #require(cached.observations.first), in: cached, downloadsRoot: root)
    let id = try #require(draft.selected.first?.id)
    var refresh = RefreshChoices()
    let request = refresh.begin(scope: root, draft: &draft)
    refresh.finish(await RefreshValidator().validate(request, against: cached), draft: &draft)
    #expect(refresh.status(id) == .required)
    #expect(!refresh.canReview(draft))
}
@Test func olderCompletionCannotReplaceNewRefreshOrResurrectDeselectedTargets() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRefresh-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: root.appendingPathComponent("chosen.pdf"))
    let scanner = FolderScanner(supplement: RefreshLocalMetadata())
    let first = try await scanner.scan(root)
    var draft = PlanDraft()
    try draft.select(try #require(first.observations.first), in: first, downloadsRoot: root)
    let id = try #require(draft.selected.first?.id)
    var refresh = RefreshChoices()
    let old = refresh.begin(scope: root, draft: &draft)
    let oldResult = await RefreshValidator().validate(old, against: try await scanner.scan(root))
    let newest = refresh.begin(scope: root, draft: &draft)
    refresh.finish(oldResult, draft: &draft)
    refresh.cancel(old)
    #expect(refresh.status(id) == .refreshing)
    let latest = await RefreshValidator().validate(newest, against: try await scanner.scan(root))
    draft.remove(id)
    refresh.finish(latest, draft: &draft)
    #expect(draft.selectedCount == 0 && refresh.notices.isEmpty)
}

private struct RefreshDeniedAccess: ScanAccessChecking {
    func check(_ url: URL) throws { throw CocoaError(.fileReadNoPermission) }
}
@Test func lostScopeAccessKeepsOnlyAffectedChoicesPendingAndPreservesIndependentEvidence() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRefresh-" + UUID().uuidString)
    let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
    try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: a.appendingPathComponent("a.pdf")); try Data([2]).write(to: b.appendingPathComponent("b.pdf"))
    let scanner = FolderScanner(supplement: RefreshLocalMetadata())
    var draft = PlanDraft()
    let initialA = try await scanner.scan(a), initialB = try await scanner.scan(b)
    try draft.select(try #require(initialA.observations.first), in: initialA, downloadsRoot: root)
    try draft.select(try #require(initialB.observations.first), in: initialB, downloadsRoot: root)
    let selectedA = try #require(draft.selected.first { $0.url.lastPathComponent == "a.pdf" })
    let selectedB = try #require(draft.selected.first { $0.url.lastPathComponent == "b.pdf" })
    var refresh = RefreshChoices()
    let request = refresh.begin(scope: a, draft: &draft)
    let denied = try await FolderScanner(supplement: RefreshLocalMetadata(), access: RefreshDeniedAccess()).scan(a)
    refresh.finish(await RefreshValidator().validate(request, against: denied), draft: &draft)
    #expect(refresh.status(selectedA.id) == .required)
    #expect(refresh.status(selectedB.id) == .ready)
    #expect(draft.selectedCount == 2 && !refresh.canReview(draft))
    draft.remove(selectedA.id)
    #expect(refresh.canReview(draft))
    #expect(draft.selected.first?.observedAt == initialB.observedAt)
}

@Test func startingRefreshInvalidatesAnAlreadyReviewedExactBatch() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRefresh-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: root.appendingPathComponent("chosen.pdf"))
    let scan = try await FolderScanner(supplement: RefreshLocalMetadata()).scan(root)
    var draft = PlanDraft()
    try draft.select(try #require(scan.observations.first), in: scan, downloadsRoot: root)
    let reviewed = try draft.review()
    var refresh = RefreshChoices()
    _ = refresh.begin(scope: root, draft: &draft)
    #expect(throws: PlanSelectionError.self) { try draft.approve(reviewed) }
    #expect(!refresh.canReview(draft))
}
