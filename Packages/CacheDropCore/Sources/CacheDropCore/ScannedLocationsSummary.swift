import Foundation

/// Overview's one-line summary of what was scanned (#223): the observed folders and the catalog's known cache folders.
/// Unknown coverage isn't repeated here; the row for the unavailable location explains it.
public enum ScannedLocationsSummary {
    public static func text(folders: Int?, observedBytes: Int64?, complete: Bool, knownCacheFolders: Int?, checking: Bool) -> String {
        var parts: [String] = []
        if let folders {
            let count = folders == 1 ? "1 folder" : "\(folders) folders"
            if let observedBytes {
                let size = ByteCountFormatter.string(fromByteCount: observedBytes, countStyle: .decimal)
                parts.append((complete ? "" : "at least ") + size + " in " + count)
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
