import Foundation

/// Short, row-sized names for paths (Decision 25: no long paths in rows; the full path goes in a tooltip).
public enum PathDisplay {
    /// The folder that contains `path`, with the home folder as `~` and anything deeper than two
    /// folders shortened to its last two: `~/Workspace`, `…/Clients/Acme`, `/Volumes/Backup`.
    public static func shortLocation(of path: String, home: String = NSHomeDirectory()) -> String {
        let parent = URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent().path
        let homePath = URL(fileURLWithPath: home).standardizedFileURL.path
        var root = "/"
        var components: [String]
        if parent == homePath { return "~" }
        if parent.hasPrefix(homePath + "/") {
            root = "~/"
            components = String(parent.dropFirst(homePath.count + 1)).split(separator: "/").map(String.init)
        } else {
            components = parent.split(separator: "/").map(String.init)
        }
        if components.isEmpty { return root == "~/" ? "~" : "/" }
        if components.count > 2 { return "…/" + components.suffix(2).joined(separator: "/") }
        return root + components.joined(separator: "/")
    }
}
