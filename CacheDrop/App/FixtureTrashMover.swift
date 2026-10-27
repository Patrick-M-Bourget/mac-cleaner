import Foundation
import CacheDropCore

#if DEBUG
/// A UI test's Trash: moves items into the fixture home's `.Trash` instead of the user's, so a journey that cleans for real
/// never touches the real Trash.
struct FixtureTrashMover: TrashMoving {
    let home: URL
    func moveToTrash(_ url: URL) throws -> URL? {
        let folder = TrashSpace.folder(home: home)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}
#endif
