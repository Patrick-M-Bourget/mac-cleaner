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

/// Opens the Trash folder with NSWorkspace, which shows it as Finder's Trash.
struct WorkspaceTrashOpener: TrashOpening {
    func open(_ folder: URL) -> Bool { NSWorkspace.shared.open(folder) }
}

#if DEBUG
/// A UI test's opener: records the folder in `<home>/.still-test-opened-trash` instead of opening Finder.
struct FixtureTrashOpener: TrashOpening {
    func open(_ folder: URL) -> Bool {
        // The Trash folder is `<home>/.Trash`, and only a fixture home reaches here.
        (try? folder.path.write(to: folder.deletingLastPathComponent().appendingPathComponent(".still-test-opened-trash"), atomically: true, encoding: .utf8)) != nil
    }
}
#endif

/// One quiet line with an Open Trash link, as `FullDiskAccessNote` is drawn (Decision 25).
private struct TrashLine: View {
    let text: String
    let identifier: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: StillDesign.Space.xs) {
            Image(systemName: "trash").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(text + " ·").foregroundStyle(.secondary).accessibilityIdentifier(identifier)
            Button("Open Trash") { TrashModel.shared.open() }.buttonStyle(.link).accessibilityIdentifier(identifier + "Open")
        }.font(StillDesign.TypeStyle.caption).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
    }
}

/// Overview: "Trash holds X · Open Trash", only when the Trash isn't empty; unknown when it can't be read.
struct TrashNote: View {
    private var model = TrashModel.shared
    var body: some View {
        // Measured by Overview's own task (`TrashModel.refresh`): a task here wouldn't run while the line is hidden.
        if let text = model.contents?.overviewText { TrashLine(text: text, identifier: "overviewTrash") }
    }
}

/// Results after a run moved items to the Trash: "Empty the Trash in Finder to free X · Open Trash", measured after the run.
struct TrashEmptyHint: View {
    let movedBytes: Int64
    @State private var measured: TrashContents?
    var body: some View {
        Group {
            if let text = measured?.emptyHint(movedBytes: movedBytes) { TrashLine(text: text, identifier: "resultsTrash") }
        }.task { measured = await TrashModel.shared.refresh() ?? .unknown }
    }
}
