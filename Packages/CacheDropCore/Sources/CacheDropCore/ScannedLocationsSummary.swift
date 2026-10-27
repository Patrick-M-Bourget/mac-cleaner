import Foundation

/// Overview's one-line summary of what was scanned (#223): what was observed in the folders, and the catalog's known cache
/// folders. Unknown coverage isn't repeated here; the row for the unavailable location explains it. The caller formats the
/// observed size with Overview's own byte formatter (#232).
public enum ScannedLocationsSummary {
    public static func text(folders: Int?, observedSize: String?, complete: Bool, knownCacheFolders: Int?, checking: Bool) -> String {
        var parts: [String] = []
        if let folders {
            let count = folders == 1 ? "1 folder" : "\(folders) folders"
            if let observedSize {
                parts.append((complete ? "" : "at least ") + observedSize + " observed in " + count)
            } else {
                parts.append(count)
            }
        }
        if let knownCacheFolders {
            parts.append(knownCacheFolders == 1 ? "1 known cache folder" : "\(knownCacheFolders) known cache folders")
        } else if checking {
            parts.append("Checking known cache folders…")
        }
        return parts.isEmpty ? "No folders chosen yet" : parts.joined(separator: " · ")
    }
}
