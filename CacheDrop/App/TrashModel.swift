import AppKit
import Observation
import CacheDropCore
import SwiftUI

/// What the Finder Trash holds, measured read-only off the main thread, and CacheDrop's own items in it. CacheDrop never
/// empties the Trash; it deletes from it only items it moved there itself, when you ask (SPEC section 2, Decision 68).
@MainActor @Observable final class TrashModel {
    static let shared = TrashModel()
    /// nil until measured, and with no catalog home (a debug test run without a fixture home).
    private(set) var contents: TrashContents?
    /// CacheDrop's own items still in the Trash, unchanged and not put back (#359); nil until read.
    private(set) var emptyable: TrashEmptyingReview?
    private var generation = 0

    /// Measures the Trash again and returns what it holds, and reads which of CacheDrop's items are still there; the
    /// newest measurement wins.
    @discardableResult
    func refresh() async -> TrashContents? {
        guard let home = CatalogCleanupModel.home else { contents = nil; emptyable = nil; return nil }
        generation += 1
        let mine = generation
        let (measured, review) = await Task.detached(priority: .utility) { (TrashSpace.measure(home: home), Self.readEmptyable(home: home)) }.value
        if mine == generation { contents = measured; emptyable = review }
        return measured
    }
    /// Read-only: never creates the journal. A debug test run offers only what is in its fixture home's Trash.
    nonisolated private static func readEmptyable(home: URL) -> TrashEmptyingReview? {
        guard let journal = try? CleanupJournalLocation.existingReader() else { return nil }
        guard let review = try? TrashEmptying(journal: journal).review() else { return nil }
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            let trash = TrashSpace.folder(home: home).standardizedFileURL.path + "/"
            return TrashEmptyingReview(items: review.items.filter { $0.trashURL?.standardizedFileURL.path.hasPrefix(trash) == true })
        }
        #endif
        return review
    }
    /// CacheDrop's own items in the Trash, by their recorded sizes; 0 until read or with none.
    var emptyableBytes: Int64 { emptyable?.bytes ?? 0 }
    /// What the last emptying did, for its sheet (#359); nil until one ran.
    private(set) var emptyingResult: TrashEmptyingResult?
    private(set) var isEmptying = false
    /// Trash moves deleted from the Trash this session, so Results and History drop their Put back.
    private(set) var emptiedIDs: Set<String> = []

    /// Deletes `items` from the Trash, each checked again first, or with the Settings dry run on only checks them. Then
    /// measures the Trash again for Results and Overview.
    func empty(_ items: [CleanupRecord]) async {
        guard !isEmptying, !items.isEmpty else { return }
        isEmptying = true
        defer { isEmptying = false }
        let dryRun = AppLifecycleController.shared.selection.catalog.dryRun
        let result = await Task.detached(priority: .userInitiated) { () -> TrashEmptyingResult in
            guard let journal = try? CleanupJournalLocation.writer() else {
                return TrashEmptyingResult(records: [], dryRun: dryRun, journalFailure: "CacheDrop couldn’t open its cleanup history, so nothing was changed.")
            }
            return TrashEmptying(journal: journal).empty(items, dryRun: dryRun)
        }.value
        emptyingResult = result
        if !result.dryRun { emptiedIDs.formUnion(result.records.filter { $0.state == .succeeded }.compactMap(\.emptyOf)) }
        await refresh()
    }
    func dismissEmptyingResult() { emptyingResult = nil }
    /// What each put back led to, by the Trash move's record id, for Results and History (#159).
    private(set) var putBackOutcomes: [String: PutBackOutcome] = [:]
    private(set) var puttingBack: Set<String> = []

    /// Puts an item a run moved to the Trash back where it was, then measures the Trash again for Overview's line. A restored
    /// item starts a catalog rescan, so an app or installer it returned is offered again without Scan again (#306).
    func putBack(_ record: CleanupRecord) async {
        guard !puttingBack.contains(record.id), putBackOutcomes[record.id] != .restored(record.originalURL) else { return }
        puttingBack.insert(record.id)
        defer { puttingBack.remove(record.id) }
        let outcome = await Task.detached(priority: .userInitiated) { () -> PutBackOutcome in
            guard let journal = try? CleanupJournalLocation.writer() else { return .refused(.couldNotRecord) }
            return TrashPutBack(journal: journal).putBack(record)
        }.value
        putBackOutcomes[record.id] = outcome
        if case .restored = outcome { Task { await AppLifecycleController.shared.selection.catalog.rescan() } }
        await refresh()
    }

    /// Opens the Trash in Finder, where the user empties it.
    func open() {
        guard let home = CatalogCleanupModel.home else { return }
        TrashSpace.open(home: home, with: Self.opener)
    }
    /// Where a run's Trash moves go: Finder's Trash, or in a debug test run the fixture home's (or none, without one).
    static var mover: any TrashMoving {
        #if DEBUG
        if LocalStateLocation.isDisposableTest, let home = CatalogCleanupModel.home { return FixtureTrashMover(home: home) }
        #endif
        return FinderTrash()
    }
    private static var opener: any TrashOpening {
        #if DEBUG
        if LocalStateLocation.isDisposableTest { return FixtureTrashOpener() }
        #endif
        return WorkspaceTrashOpener()
    }
}
