import AppKit
import Observation
import CacheDropCore
import SwiftUI

/// Opens the Trash folder with NSWorkspace, which shows it as Finder's Trash.
struct WorkspaceTrashOpener: TrashOpening {
    func open(_ folder: URL) -> Bool { Finder.open(folder) }
}
