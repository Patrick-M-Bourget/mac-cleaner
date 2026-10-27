import Foundation

/// Moves one item to the Trash and returns where it landed. Never deletes as a fallback.
public protocol TrashMoving: Sendable {
    func moveToTrash(_ url: URL) throws -> URL?
}
/// The Finder Trash, through a coordinated write so other apps' file presenters see the move.
public struct FinderTrash: TrashMoving {
    public init() {}
    public func moveToTrash(_ url: URL) throws -> URL? {
        var coordinationError: NSError?, operationError: Error?, resulting: URL?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinated in
            do {
                var returned: NSURL?
                try FileManager.default.trashItem(at: coordinated, resultingItemURL: &returned)
                resulting = returned as URL?
            } catch { operationError = error }
        }
        if let error = operationError ?? coordinationError { throw error }
        return resulting
    }
}
