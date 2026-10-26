import Foundation

/// Where an item sits, short enough for a row: the scanned location's name and the folders below it, such as
/// "Projects › Renders". Rows show this; the full path goes in the inspector or a tooltip.
public enum ShortLocation {
    public static func of(_ item: URL, in scope: URL) -> String {
        let folder = item.standardizedFileURL.deletingLastPathComponent().pathComponents
        let root = scope.standardizedFileURL.pathComponents
        // Outside the scope (never expected): fall back to the containing folder's name.
        guard folder.starts(with: root), let name = root.last else { return folder.last ?? "" }
        return ([name] + folder.dropFirst(root.count)).joined(separator: " › ")
    }
}
