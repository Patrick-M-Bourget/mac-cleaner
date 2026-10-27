import AppKit
import Observation
import StillCore
import SwiftUI

#if DEBUG
/// A UI test's opener: records the folder in `<home>/.still-test-opened-trash` instead of opening Finder.
struct FixtureTrashOpener: TrashOpening {
    func open(_ folder: URL) -> Bool {
        // The Trash folder is `<home>/.Trash`, and only a fixture home reaches here.
        (try? folder.path.write(to: folder.deletingLastPathComponent().appendingPathComponent(".still-test-opened-trash"), atomically: true, encoding: .utf8)) != nil
    }
}
#endif
