import Darwin
import Foundation

/// A scanned location that a recheck couldn't reach (#249). Its last observation is kept but never shown as current:
/// the explorer marks it with the same orange row and Choose again… as Overview (#223, #231).
/// The caller formats the date, with the explorer's own date style.
public enum UnavailableScannedFolder {
    /// "Folder not found" when nothing is at the path any more; otherwise the reason Overview's row gives.
    /// Called once, when the recheck fails, never while browsing.
    public static func reason(path: String, otherwise: String) -> String {
        var info = stat()
        return lstat(path, &info) != 0 && errno == ENOENT ? notFound : otherwise
    }
    /// The reason for a folder that was deleted or moved.
    public static let notFound = "Folder not found"
    /// The explorer's recovery row. A deleted or moved folder says when it was last observed; one that is there but
    /// unreadable keeps its reason alone, such as "Access unavailable" (#254, #257).
    public static func text(reason: String, lastObserved: String?) -> String {
        guard reason == notFound, let lastObserved else { return reason }
        return reason + " · last observed " + lastObserved
    }
    /// Overview's recovery row (#254): the location's name, then the explorer's wording.
    public static func overviewText(name: String, reason: String, lastObserved: String?) -> String {
        name + " · " + text(reason: reason, lastObserved: lastObserved)
    }
    /// The gone location that is `folder` or holds it.
    public static func location(holding folder: URL, among gone: [URL]) -> URL? {
        let path = folder.standardizedFileURL.pathComponents
        return gone.first { path.starts(with: $0.standardizedFileURL.pathComponents) }
    }
    /// Observations still current: those of a gone location are left out.
    public static func current(_ scans: [ScanResult], gone: [URL]) -> [ScanResult] {
        let paths = Set(gone.map(\.standardizedFileURL.path))
        return scans.filter { !paths.contains($0.scope.standardizedFileURL.path) }
    }
    public static func lastObserved(_ scope: URL, in scans: [ScanResult]) -> Date? {
        scans.filter { $0.scope.standardizedFileURL.path == scope.standardizedFileURL.path }.map(\.observedAt).max()
    }
}
