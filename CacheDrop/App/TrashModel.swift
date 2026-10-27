import AppKit
import Observation
import CacheDropCore
import SwiftUI

/// What the Finder Trash holds, measured read-only off the main thread. CacheDrop never empties the Trash (SPEC section 2).
@MainActor @Observable final class TrashModel {
    static let shared = TrashModel()
    /// nil until measured, and with no catalog home (a debug test run without a fixture home).
    private(set) var contents: TrashContents?
    private var generation = 0

    /// Measures the Trash again and returns what it holds; the newest measurement wins.
    @discardableResult
    func refresh() async -> TrashContents? {
        guard let home = CatalogCleanupModel.home else { contents = nil; return nil }
        generation += 1
        let mine = generation
        let measured = await Task.detached(priority: .utility) { TrashSpace.measure(home: home) }.value
        if mine == generation { contents = measured }
        return measured
    }
    /// What each put back led to, by the Trash move's record id, for Results and History (#159).
    private(set) var putBackOutcomes: [String: PutBackOutcome] = [:]
    private(set) var puttingBack: Set<String> = []

    /// Puts an item a run moved to the Trash back where it was, then measures the Trash again for Overview's line.
    func putBack(_ record: CleanupRecord) async {
        guard !puttingBack.contains(record.id), putBackOutcomes[record.id] != .restored(record.originalURL) else { return }
        puttingBack.insert(record.id)
        defer { puttingBack.remove(record.id) }
        let outcome = await Task.detached(priority: .userInitiated) { () -> PutBackOutcome in
            guard let journal = try? CleanupJournalLocation.writer() else { return .refused(.couldNotRecord) }
            return TrashPutBack(journal: journal).putBack(record)
        }.value
        putBackOutcomes[record.id] = outcome
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
