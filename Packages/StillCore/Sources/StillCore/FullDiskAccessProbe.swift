import Foundation
import Darwin

/// Checks whether a folder macOS protects behind Full Disk Access can be opened.
/// It only opens the folder itself and closes it again: it never lists or reads anything inside,
/// and never asks for access. The probed folders are ones macOS guards with Full Disk Access alone,
/// so a refusal never shows a privacy prompt (other apps' containers would, so they're not probed).
public struct FullDiskAccessProbe: FullDiskAccessDetecting {
    /// Folders inside the home folder, tried in order; the first that exists decides.
    public static let protectedFolders = ["Library/Safari", "Library/Application Support/com.apple.TCC"]
    public let home: URL
    public let folders: [String]
    public init(home: URL, folders: [String] = FullDiskAccessProbe.protectedFolders) { self.home = home; self.folders = folders }

    public func status() -> FullDiskAccessStatus {
        for folder in folders {
            let path = home.appendingPathComponent(folder).path
            let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if fd >= 0 { close(fd); return .granted }
            switch errno {
            case EPERM, EACCES: return .notGranted
            default: continue // Missing or not a folder: try the next one.
            }
        }
        return .unknown
    }
}
