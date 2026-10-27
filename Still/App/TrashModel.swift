import AppKit
import Observation
import StillCore
import SwiftUI

/// What the Finder Trash holds, measured read-only off the main thread. Still never empties the Trash (SPEC section 2).
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
    /// Opens the Trash in Finder, where the user empties it.
    func open() {
        guard let home = CatalogCleanupModel.home else { return }
        TrashSpace.open(home: home, with: Self.opener)
    }
    private static var opener: any TrashOpening {
        #if DEBUG
        if LocalStateLocation.isDisposableTest { return FixtureTrashOpener() }
        #endif
        return WorkspaceTrashOpener()
    }
}
